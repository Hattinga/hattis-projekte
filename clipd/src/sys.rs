//! Platform specifics: making sure the capture dies with clipd.

/// Puts clipd into a job object that kills every process it started when clipd
/// exits, even after a crash. Otherwise an ffmpeg would keep recording into a
/// buffer nobody reads, holding on to the encoder the next start needs.
#[cfg(windows)]
pub fn kill_children_on_exit() {
    use windows_sys::Win32::System::JobObjects::*;
    use windows_sys::Win32::System::Threading::GetCurrentProcess;
    // SAFETY: plain Win32 calls on a zeroed struct whose size we pass along.
    unsafe {
        let job = CreateJobObjectW(std::ptr::null(), std::ptr::null());
        if job.is_null() {
            return;
        }
        let mut info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = std::mem::zeroed();
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_BREAKAWAY_OK;
        let ok = SetInformationJobObject(
            job,
            JobObjectExtendedLimitInformation,
            &info as *const _ as *const _,
            std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
        );
        if ok != 0 {
            AssignProcessToJobObject(job, GetCurrentProcess());
        }
        // The handle stays open for the life of the process; closing it at exit
        // is what ends the children.
    }
}

#[cfg(not(windows))]
pub fn kill_children_on_exit() {}

/// Switches the console to UTF-8. Rust prints UTF-8, but a Windows console
/// still defaults to a legacy code page, which turns every umlaut in clipd's
/// messages into mojibake.
#[cfg(windows)]
pub fn use_utf8_console() {
    use windows_sys::Win32::System::Console::SetConsoleOutputCP;
    const UTF8: u32 = 65001;
    // SAFETY: one call with a constant code page; a failure only means the
    // console keeps the old one.
    unsafe {
        SetConsoleOutputCP(UTF8);
    }
}

#[cfg(not(windows))]
pub fn use_utf8_console() {}
