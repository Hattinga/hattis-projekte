//! Media Foundation: device discovery and capture.
//!
//! This file lists video capture devices and the native media types each
//! driver reports, and holds the COM/MF helpers. Nothing here assumes a
//! particular device, resolution, frame rate or pixel format: it prints what
//! Media Foundation returns. The capture source itself is in
//! [`source`] (asynchronous `IMFSourceReader`).
//!
//! COM threading: every thread that touches MF objects initializes COM as
//! multithreaded apartment ([`MfSession`]). Listing runs on its own thread,
//! capture on the capture thread. Neither may be the winit event-loop thread,
//! which winit initializes as STA (OLE) for drag and drop.

mod source;

pub use source::{MediaFoundationSource, ReaderOptions};

use std::fmt;

use windows::Win32::Foundation::E_POINTER;
use windows::Win32::Media::MediaFoundation::{
    IMFActivate, IMFAttributes, IMFMediaSource, IMFMediaType, MF_ATTRIBUTE_BLOB,
    MF_ATTRIBUTE_DOUBLE, MF_ATTRIBUTE_GUID, MF_ATTRIBUTE_IUNKNOWN, MF_ATTRIBUTE_STRING,
    MF_ATTRIBUTE_UINT32, MF_ATTRIBUTE_UINT64, MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME,
    MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE, MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID,
    MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, MF_E_NO_MORE_TYPES,
    MF_MT_ALL_SAMPLES_INDEPENDENT, MF_MT_AVG_BITRATE, MF_MT_DEFAULT_STRIDE,
    MF_MT_FIXED_SIZE_SAMPLES, MF_MT_FRAME_RATE, MF_MT_FRAME_RATE_RANGE_MAX,
    MF_MT_FRAME_RATE_RANGE_MIN, MF_MT_FRAME_SIZE, MF_MT_GEOMETRIC_APERTURE, MF_MT_INTERLACE_MODE,
    MF_MT_MAJOR_TYPE, MF_MT_MINIMUM_DISPLAY_APERTURE, MF_MT_PIXEL_ASPECT_RATIO, MF_MT_SAMPLE_SIZE,
    MF_MT_SUBTYPE, MF_MT_TRANSFER_FUNCTION, MF_MT_VIDEO_CHROMA_SITING, MF_MT_VIDEO_NOMINAL_RANGE,
    MF_MT_VIDEO_PRIMARIES, MF_MT_YUV_MATRIX, MF_SOURCE_READER_FIRST_VIDEO_STREAM, MF_VERSION,
    MFCreateAttributes, MFCreateSourceReaderFromMediaSource, MFEnumDeviceSources,
    MFMediaType_Video, MFSTARTUP_FULL, MFShutdown, MFStartup, MFVideoFormat_ARGB32,
    MFVideoFormat_I420, MFVideoFormat_MJPG, MFVideoFormat_NV12, MFVideoFormat_RGB24,
    MFVideoFormat_RGB32, MFVideoFormat_UYVY, MFVideoFormat_YUY2,
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
/// Must outlive every MF object created on the thread.
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
        tracing::debug!("drop: MFShutdown");
        // SAFETY: start() succeeded with both calls on this thread, and all
        // COM objects created in the session have been released already.
        unsafe {
            if let Err(err) = MFShutdown() {
                tracing::warn!(%err, "MFShutdown failed");
            }
            CoUninitialize();
        }
        tracing::debug!("drop: COM and Media Foundation released");
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

/// Every attribute of `attributes` as `(name, value)` text, in storage order.
/// Unknown keys are shown as GUIDs, so nothing the driver sets is hidden.
pub fn dump_attributes(attributes: &IMFAttributes) -> Vec<(String, String)> {
    // SAFETY: plain query on a live attribute store.
    let count = unsafe { attributes.GetCount() }.unwrap_or(0);
    (0..count)
        .filter_map(|index| {
            let mut key = GUID::zeroed();
            // SAFETY: valid out-pointer for the key; the value is not
            // requested (None), so no PROPVARIANT needs clearing.
            unsafe { attributes.GetItemByIndex(index, &mut key, None) }.ok()?;
            Some((attribute_name(key), attribute_value(attributes, &key)))
        })
        .collect()
}

fn attribute_name(key: GUID) -> String {
    const NAMES: [(GUID, &str); 20] = [
        (MF_MT_MAJOR_TYPE, "MF_MT_MAJOR_TYPE"),
        (MF_MT_SUBTYPE, "MF_MT_SUBTYPE"),
        (MF_MT_FRAME_SIZE, "MF_MT_FRAME_SIZE"),
        (MF_MT_FRAME_RATE, "MF_MT_FRAME_RATE"),
        (MF_MT_FRAME_RATE_RANGE_MIN, "MF_MT_FRAME_RATE_RANGE_MIN"),
        (MF_MT_FRAME_RATE_RANGE_MAX, "MF_MT_FRAME_RATE_RANGE_MAX"),
        (MF_MT_PIXEL_ASPECT_RATIO, "MF_MT_PIXEL_ASPECT_RATIO"),
        (MF_MT_INTERLACE_MODE, "MF_MT_INTERLACE_MODE"),
        (MF_MT_DEFAULT_STRIDE, "MF_MT_DEFAULT_STRIDE"),
        (MF_MT_SAMPLE_SIZE, "MF_MT_SAMPLE_SIZE"),
        (MF_MT_FIXED_SIZE_SAMPLES, "MF_MT_FIXED_SIZE_SAMPLES"),
        (
            MF_MT_ALL_SAMPLES_INDEPENDENT,
            "MF_MT_ALL_SAMPLES_INDEPENDENT",
        ),
        (MF_MT_AVG_BITRATE, "MF_MT_AVG_BITRATE"),
        (MF_MT_YUV_MATRIX, "MF_MT_YUV_MATRIX"),
        (MF_MT_VIDEO_NOMINAL_RANGE, "MF_MT_VIDEO_NOMINAL_RANGE"),
        (MF_MT_VIDEO_PRIMARIES, "MF_MT_VIDEO_PRIMARIES"),
        (MF_MT_TRANSFER_FUNCTION, "MF_MT_TRANSFER_FUNCTION"),
        (MF_MT_VIDEO_CHROMA_SITING, "MF_MT_VIDEO_CHROMA_SITING"),
        (MF_MT_GEOMETRIC_APERTURE, "MF_MT_GEOMETRIC_APERTURE"),
        (
            MF_MT_MINIMUM_DISPLAY_APERTURE,
            "MF_MT_MINIMUM_DISPLAY_APERTURE",
        ),
    ];
    NAMES
        .iter()
        .find(|(guid, _)| *guid == key)
        .map_or_else(|| format!("{key:?}"), |(_, name)| (*name).to_string())
}

fn attribute_value(attributes: &IMFAttributes, key: &GUID) -> String {
    let split = |v: u64| ((v >> 32) as u32, v as u32);
    // SAFETY (all calls below): typed reads on a live attribute store, each
    // matching the type GetItemType reported for the key.
    unsafe {
        let Ok(kind) = attributes.GetItemType(key) else {
            return "?".into();
        };
        match kind {
            MF_ATTRIBUTE_UINT32 => match attributes.GetUINT32(key) {
                // The stride is a signed value stored as UINT32.
                Ok(v) if *key == MF_MT_DEFAULT_STRIDE => format!("{}", v as i32),
                Ok(v) => match enum_label(key, v) {
                    Some(label) => format!("{v} ({label})"),
                    None => v.to_string(),
                },
                Err(e) => format!("<{e}>"),
            },
            MF_ATTRIBUTE_UINT64 => match attributes.GetUINT64(key) {
                Ok(v) if *key == MF_MT_FRAME_SIZE => {
                    let (w, h) = split(v);
                    format!("{w} x {h}")
                }
                Ok(v)
                    if [
                        MF_MT_FRAME_RATE,
                        MF_MT_FRAME_RATE_RANGE_MIN,
                        MF_MT_FRAME_RATE_RANGE_MAX,
                        MF_MT_PIXEL_ASPECT_RATIO,
                    ]
                    .contains(key) =>
                {
                    let (n, d) = split(v);
                    format!("{n}/{d}")
                }
                Ok(v) => v.to_string(),
                Err(e) => format!("<{e}>"),
            },
            MF_ATTRIBUTE_GUID => match attributes.GetGUID(key) {
                Ok(v) if v == MFMediaType_Video => "Video".into(),
                Ok(v) if *key == MF_MT_SUBTYPE => subtype_name(v),
                Ok(v) => format!("{v:?}"),
                Err(e) => format!("<{e}>"),
            },
            MF_ATTRIBUTE_DOUBLE => attributes
                .GetDouble(key)
                .map_or_else(|e| format!("<{e}>"), |v| v.to_string()),
            MF_ATTRIBUTE_STRING => allocated_string(attributes, key)
                .map_or_else(|e| format!("<{e}>"), |s| format!("{s:?}")),
            MF_ATTRIBUTE_BLOB => {
                let size = attributes.GetBlobSize(key).unwrap_or(0) as usize;
                let mut blob = vec![0u8; size];
                match attributes.GetBlob(key, &mut blob, None) {
                    Ok(()) => {
                        let hex: Vec<String> =
                            blob.iter().take(32).map(|b| format!("{b:02x}")).collect();
                        format!("blob, {size} bytes: {}", hex.join(" "))
                    }
                    Err(e) => format!("<blob, {size} bytes: {e}>"),
                }
            }
            MF_ATTRIBUTE_IUNKNOWN => "<COM object>".into(),
            other => format!("<type {}>", other.0),
        }
    }
}

/// Names for the enum values of a few colour and layout attributes
/// (mfobjects.h: MFVideoInterlaceMode, MFVideoTransferMatrix,
/// MFNominalRange, MFVideoPrimaries, MFVideoTransferFunction).
fn enum_label(key: &GUID, value: u32) -> Option<&'static str> {
    let table: &[&str] = if *key == MF_MT_INTERLACE_MODE {
        &[
            "unknown",
            "",
            "progressive",
            "field interleaved upper first",
            "field interleaved lower first",
            "field single upper",
            "field single lower",
            "mixed interlace or progressive",
        ]
    } else if *key == MF_MT_YUV_MATRIX {
        &[
            "unknown",
            "BT.709",
            "BT.601",
            "SMPTE 240M",
            "BT.2020 10",
            "BT.2020 12",
        ]
    } else if *key == MF_MT_VIDEO_NOMINAL_RANGE {
        &[
            "unknown",
            "0-255 (full)",
            "16-235 (limited)",
            "48-208",
            "64-127",
        ]
    } else if *key == MF_MT_VIDEO_PRIMARIES {
        &[
            "unknown",
            "reserved",
            "BT.709",
            "BT.470-2 System M",
            "BT.470-2 System B,G",
            "SMPTE 170M",
            "SMPTE 240M",
            "EBU 3213",
            "SMPTE C",
            "BT.2020",
        ]
    } else if *key == MF_MT_TRANSFER_FUNCTION {
        &[
            "unknown",
            "linear",
            "1.8",
            "2.0",
            "2.2",
            "BT.709",
            "SMPTE 240M",
            "sRGB",
            "2.8",
            "log 100",
            "log 316",
            "BT.709 sym",
            "BT.2020 const",
            "BT.2020",
            "2.6",
            "ST 2084 (PQ)",
            "HLG",
        ]
    } else {
        return None;
    };
    table
        .get(value as usize)
        .copied()
        .filter(|label| !label.is_empty())
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

    /// The label tables are hand-written; check them against the crate's
    /// enum constants.
    #[test]
    fn enum_labels_match_the_sdk_values() {
        use windows::Win32::Media::MediaFoundation::{
            MFNominalRange_0_255, MFNominalRange_16_235, MFVideoInterlace_Progressive,
            MFVideoPrimaries_BT709, MFVideoPrimaries_BT2020, MFVideoTransFunc_709,
            MFVideoTransFunc_2084, MFVideoTransFunc_HLG, MFVideoTransFunc_sRGB,
            MFVideoTransferMatrix_BT601, MFVideoTransferMatrix_BT709,
        };
        let label = |key: &GUID, value: i32| enum_label(key, value as u32);
        assert_eq!(
            label(&MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive.0),
            Some("progressive")
        );
        assert_eq!(
            label(&MF_MT_YUV_MATRIX, MFVideoTransferMatrix_BT709.0),
            Some("BT.709")
        );
        assert_eq!(
            label(&MF_MT_YUV_MATRIX, MFVideoTransferMatrix_BT601.0),
            Some("BT.601")
        );
        assert_eq!(
            label(&MF_MT_VIDEO_NOMINAL_RANGE, MFNominalRange_0_255.0),
            Some("0-255 (full)")
        );
        assert_eq!(
            label(&MF_MT_VIDEO_NOMINAL_RANGE, MFNominalRange_16_235.0),
            Some("16-235 (limited)")
        );
        assert_eq!(
            label(&MF_MT_VIDEO_PRIMARIES, MFVideoPrimaries_BT709.0),
            Some("BT.709")
        );
        assert_eq!(
            label(&MF_MT_VIDEO_PRIMARIES, MFVideoPrimaries_BT2020.0),
            Some("BT.2020")
        );
        assert_eq!(
            label(&MF_MT_TRANSFER_FUNCTION, MFVideoTransFunc_709.0),
            Some("BT.709")
        );
        assert_eq!(
            label(&MF_MT_TRANSFER_FUNCTION, MFVideoTransFunc_sRGB.0),
            Some("sRGB")
        );
        assert_eq!(
            label(&MF_MT_TRANSFER_FUNCTION, MFVideoTransFunc_2084.0),
            Some("ST 2084 (PQ)")
        );
        assert_eq!(
            label(&MF_MT_TRANSFER_FUNCTION, MFVideoTransFunc_HLG.0),
            Some("HLG")
        );
        assert_eq!(label(&MF_MT_INTERLACE_MODE, 1), None);
        assert_eq!(label(&MF_MT_SUBTYPE, 1), None);
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
    /// Ignored by default because it briefly opens every camera attached
    /// (webcam LEDs flash): `cargo test -- --ignored`.
    #[test]
    #[ignore = "opens every attached camera; run with --ignored"]
    fn enumeration_runs() {
        let devices = list_video_devices().expect("Media Foundation enumeration failed");
        for device in &devices {
            assert!(!device.name.is_empty());
        }
    }
}
