//! Media Foundation device discovery (read-only preparation for capture).
//!
//! Lists video capture devices and the native media types each driver
//! reports. Nothing here assumes a particular device, resolution, frame rate
//! or pixel format: it prints what Media Foundation returns.
//!
//! Deliberately **not** implemented yet (milestone M2, needs the real card):
//! a `VideoSource` built on `IMFSourceReader::ReadSample`, media-type
//! selection, stride/padding handling, YUV matrix/range detection and
//! device-loss handling. See docs/ARCHITECTURE.md for where it plugs in.
//!
//! COM threading: everything runs on one dedicated thread that initializes
//! COM as multithreaded apartment. It must not be the winit event-loop thread,
//! which winit initializes as STA (OLE) for drag and drop.

use std::fmt;

use windows::Win32::Foundation::E_POINTER;
use windows::Win32::Media::MediaFoundation::{
    IMFActivate, IMFAttributes, IMFMediaSource, IMFMediaType, MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME,
    MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE, MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID,
    MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, MF_E_NO_MORE_TYPES, MF_MT_FRAME_RATE,
    MF_MT_FRAME_SIZE, MF_MT_SUBTYPE, MF_SOURCE_READER_FIRST_VIDEO_STREAM, MF_VERSION,
    MFCreateAttributes, MFCreateSourceReaderFromMediaSource, MFEnumDeviceSources, MFSTARTUP_FULL,
    MFShutdown, MFStartup, MFVideoFormat_ARGB32, MFVideoFormat_I420, MFVideoFormat_MJPG,
    MFVideoFormat_NV12, MFVideoFormat_RGB24, MFVideoFormat_RGB32, MFVideoFormat_UYVY,
    MFVideoFormat_YUY2,
};
use windows::Win32::System::Com::{
    COINIT_MULTITHREADED, CoInitializeEx, CoTaskMemFree, CoUninitialize,
};
use windows::core::{GUID, PWSTR};

/// One capture device as reported by Media Foundation.
#[derive(Debug)]
pub struct DeviceInfo {
    pub name: String,
    /// Stable device identifier (symbolic link), used to reopen the device.
    pub symbolic_link: String,
    /// Native media types of the first video stream, in driver order, or the
    /// error that prevented reading them (e.g. device in use).
    pub media_types: Result<Vec<MediaTypeInfo>, String>,
}

/// One native media type. Fields are `None` when the driver omits them.
#[derive(Debug, Clone, Copy)]
pub struct MediaTypeInfo {
    pub subtype: Option<GUID>,
    pub frame_size: Option<(u32, u32)>,
    pub frame_rate: Option<(u32, u32)>,
}

impl fmt::Display for MediaTypeInfo {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let subtype = self.subtype.map_or_else(|| "?".to_string(), subtype_name);
        write!(f, "{subtype:<8}")?;
        match self.frame_size {
            Some((w, h)) => write!(f, " {:>11}", format!("{w}x{h}"))?,
            None => write!(f, " {:>11}", "?x?")?,
        }
        match self.frame_rate {
            Some((n, d)) if d != 0 => {
                write!(f, "  {:>8.3} fps ({n}/{d})", f64::from(n) / f64::from(d))
            }
            _ => write!(f, "  ? fps"),
        }
    }
}

/// Human-readable name for a video subtype GUID: known constants first, then
/// the FourCC for GUIDs built on the Media Foundation video-format base, else
/// the raw GUID.
pub fn subtype_name(subtype: GUID) -> String {
    const KNOWN: [(GUID, &str); 8] = [
        (MFVideoFormat_NV12, "NV12"),
        (MFVideoFormat_YUY2, "YUY2"),
        (MFVideoFormat_MJPG, "MJPG"),
        (MFVideoFormat_UYVY, "UYVY"),
        (MFVideoFormat_I420, "I420"),
        (MFVideoFormat_RGB32, "RGB32"),
        (MFVideoFormat_ARGB32, "ARGB32"),
        (MFVideoFormat_RGB24, "RGB24"),
    ];
    if let Some((_, name)) = KNOWN.iter().find(|(guid, _)| *guid == subtype) {
        return (*name).to_string();
    }
    // MFVideoFormat_* GUIDs are {FourCC-0000-0010-8000-00AA00389B71}.
    let base = MFVideoFormat_NV12;
    let fourcc = subtype.data1.to_le_bytes();
    if subtype.data2 == base.data2
        && subtype.data3 == base.data3
        && subtype.data4 == base.data4
        && fourcc.iter().all(|b| b.is_ascii_graphic() || *b == b' ')
    {
        return String::from_utf8_lossy(&fourcc).into_owned();
    }
    format!("{subtype:?}")
}

/// Enumerates video capture devices and their native media types.
///
/// Runs on a fresh thread so COM is initialized in a known state and never
/// touches the caller's (or winit's) apartment.
pub fn list_video_devices() -> Result<Vec<DeviceInfo>, String> {
    std::thread::Builder::new()
        .name("mf-probe".into())
        .spawn(|| list_on_current_thread().map_err(|e| format!("Media Foundation: {e}")))
        .map_err(|e| format!("cannot start probe thread: {e}"))?
        .join()
        .map_err(|_| "Media Foundation probe thread panicked".to_string())?
}

fn list_on_current_thread() -> windows::core::Result<Vec<DeviceInfo>> {
    // Declared first so it is dropped last, after every COM object below.
    let _session = MfSession::start()?;
    let activates = enumerate_video_sources()?;
    let devices = activates
        .iter()
        .map(|activate| DeviceInfo {
            name: allocated_string(activate, &MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME)
                .unwrap_or_else(|e| format!("<no friendly name: {e}>")),
            symbolic_link: allocated_string(
                activate,
                &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK,
            )
            .unwrap_or_else(|e| format!("<no symbolic link: {e}>")),
            media_types: native_media_types(activate).map_err(|e| e.to_string()),
        })
        .collect();
    Ok(devices)
}

/// COM (MTA) and Media Foundation for the current thread, undone on drop.
struct MfSession;

impl MfSession {
    fn start() -> windows::core::Result<Self> {
        // SAFETY: plain COM initialisation on the current thread; balanced by
        // CoUninitialize in Drop (or below on MFStartup failure). S_FALSE
        // ("already initialised") counts as success and must be balanced too.
        unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) }.ok()?;
        // SAFETY: COM is initialised on this thread; balanced by MFShutdown.
        if let Err(err) = unsafe { MFStartup(MF_VERSION, MFSTARTUP_FULL) } {
            // SAFETY: balances the successful CoInitializeEx above.
            unsafe { CoUninitialize() };
            return Err(err);
        }
        Ok(Self)
    }
}

impl Drop for MfSession {
    fn drop(&mut self) {
        // SAFETY: start() succeeded with both calls on this thread, and all
        // COM objects created in the session have been released already.
        unsafe {
            if let Err(err) = MFShutdown() {
                tracing::warn!(%err, "MFShutdown failed");
            }
            CoUninitialize();
        }
    }
}

fn enumerate_video_sources() -> windows::core::Result<Vec<IMFActivate>> {
    let mut attributes: Option<IMFAttributes> = None;
    // SAFETY: valid out-pointer; on success it receives an owned interface.
    unsafe { MFCreateAttributes(&mut attributes, 1) }?;
    let attributes = attributes.ok_or_else(|| windows::core::Error::from(E_POINTER))?;
    // SAFETY: both pointers reference valid GUID constants.
    unsafe {
        attributes.SetGUID(
            &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
            &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID,
        )
    }?;

    let mut array: *mut Option<IMFActivate> = std::ptr::null_mut();
    let mut count = 0u32;
    // SAFETY: valid out-pointers. On success MF hands us a CoTaskMemAlloc'ed
    // array of `count` interface pointers, each holding a reference we own.
    unsafe { MFEnumDeviceSources(&attributes, &mut array, &mut count) }?;
    let mut sources = Vec::with_capacity(count as usize);
    if !array.is_null() {
        for i in 0..count as usize {
            // SAFETY: `i < count`, so the element is inside the array. `take`
            // moves the owned reference out and leaves a null pointer behind.
            if let Some(activate) = unsafe { (*array.add(i)).take() } {
                sources.push(activate);
            }
        }
        // SAFETY: the array came from MFEnumDeviceSources and every element
        // has been moved out, so freeing it releases nothing twice.
        unsafe { CoTaskMemFree(Some(array.cast_const().cast())) };
    }
    Ok(sources)
}

fn allocated_string(attributes: &IMFAttributes, key: &GUID) -> windows::core::Result<String> {
    let mut value = PWSTR::null();
    let mut len = 0u32;
    // SAFETY: valid out-pointers; on success `value` is a NUL-terminated
    // CoTaskMemAlloc'ed UTF-16 string that we must free.
    unsafe { attributes.GetAllocatedString(key, &mut value, &mut len) }?;
    // SAFETY: `value` is valid and NUL-terminated (see above).
    let text = unsafe { value.to_string() }.unwrap_or_else(|_| "<invalid UTF-16>".into());
    // SAFETY: frees the string allocated by GetAllocatedString exactly once.
    unsafe { CoTaskMemFree(Some(value.0.cast_const().cast())) };
    Ok(text)
}

fn native_media_types(activate: &IMFActivate) -> windows::core::Result<Vec<MediaTypeInfo>> {
    // SAFETY: activating a device source enumerated in this MF session.
    // This opens the device; it fails if another app holds it exclusively.
    let source: IMFMediaSource = unsafe { activate.ActivateObject() }?;
    let types = read_native_types(&source);
    // SAFETY: shuts down the source we activated; the reader created from it
    // has already been dropped inside read_native_types.
    unsafe {
        if let Err(err) = source.Shutdown() {
            tracing::debug!(%err, "IMFMediaSource::Shutdown failed");
        }
        if let Err(err) = activate.ShutdownObject() {
            tracing::debug!(%err, "IMFActivate::ShutdownObject failed");
        }
    }
    types
}

fn read_native_types(source: &IMFMediaSource) -> windows::core::Result<Vec<MediaTypeInfo>> {
    // SAFETY: `source` is a live media source; no extra attributes.
    let reader = unsafe { MFCreateSourceReaderFromMediaSource(source, None::<&IMFAttributes>) }?;
    let stream = MF_SOURCE_READER_FIRST_VIDEO_STREAM.0 as u32;
    let mut types = Vec::new();
    for index in 0.. {
        // SAFETY: plain query on a live reader; ends with MF_E_NO_MORE_TYPES.
        let media_type = match unsafe { reader.GetNativeMediaType(stream, index) } {
            Ok(media_type) => media_type,
            Err(err) if err.code() == MF_E_NO_MORE_TYPES => break,
            Err(err) => return Err(err),
        };
        types.push(describe(&media_type));
    }
    Ok(types)
}

fn describe(media_type: &IMFMediaType) -> MediaTypeInfo {
    // MF packs two u32 into one u64: high half first (width / numerator).
    let split = |v: u64| ((v >> 32) as u32, v as u32);
    // SAFETY: attribute reads on a live media type with valid GUID keys.
    unsafe {
        MediaTypeInfo {
            subtype: media_type.GetGUID(&MF_MT_SUBTYPE).ok(),
            frame_size: media_type.GetUINT64(&MF_MT_FRAME_SIZE).ok().map(split),
            frame_rate: media_type.GetUINT64(&MF_MT_FRAME_RATE).ok().map(split),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn subtype_names() {
        assert_eq!(subtype_name(MFVideoFormat_NV12), "NV12");
        assert_eq!(subtype_name(MFVideoFormat_RGB32), "RGB32");
        // A FourCC-based subtype that is not in the table.
        let hevc = GUID::from_u128(0x43564548_0000_0010_8000_00aa00389b71);
        assert_eq!(subtype_name(hevc), "HEVC");
        let random = GUID::from_u128(0x12345678_1234_1234_1234_123456789abc);
        assert!(subtype_name(random).contains("12345678"));
    }

    #[test]
    fn media_type_display() {
        let info = MediaTypeInfo {
            subtype: Some(MFVideoFormat_YUY2),
            frame_size: Some((1920, 1080)),
            frame_rate: Some((30, 1)),
        };
        let text = info.to_string();
        assert!(text.contains("YUY2") && text.contains("1920x1080") && text.contains("30.000 fps"));
    }

    /// Exercises the real COM/MF calls. Passes with zero devices too; it only
    /// proves that enumeration works without crashing on this machine.
    #[test]
    fn enumeration_runs() {
        let devices = list_video_devices().expect("Media Foundation enumeration failed");
        for device in &devices {
            assert!(!device.name.is_empty());
        }
    }
}
