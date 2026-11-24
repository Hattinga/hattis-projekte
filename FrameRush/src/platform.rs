//! Small Windows integrations: keeping the display awake, the console of the
//! release build and an error dialog. No-ops elsewhere.

/// While capturing, the PC itself gets no keyboard or mouse input (the
/// player uses the console's controller), so Windows would turn the display
/// off or sleep mid-game. Applies to the calling thread until reset.
pub fn keep_display_awake(on: bool) {
    #[cfg(windows)]
    {
        use windows::Win32::System::Power::{
            ES_CONTINUOUS, ES_DISPLAY_REQUIRED, ES_SYSTEM_REQUIRED, SetThreadExecutionState,
        };
        let flags = if on {
            ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED
        } else {
            ES_CONTINUOUS
        };
        // SAFETY: plain flag call; ES_CONTINUOUS alone clears the request.
        if unsafe { SetThreadExecutionState(flags) }.0 == 0 {
            tracing::warn!(on, "SetThreadExecutionState failed");
        }
    }
    #[cfg(not(windows))]
    let _ = on;
}

/// The release build has no console window of its own. When started from a
/// terminal, attach to that terminal so `--help`, `--list-devices` and the
/// probes still print there. Returns whether a console is available.
pub fn attach_parent_console() -> bool {
    #[cfg(windows)]
    {
        use windows::Win32::System::Console::{ATTACH_PARENT_PROCESS, AttachConsole};
        // SAFETY: attaching to the parent's console has no preconditions; it
        // fails harmlessly when there is none (started by double-click).
        unsafe { AttachConsole(ATTACH_PARENT_PROCESS) }.is_ok()
    }
    #[cfg(not(windows))]
    true
}

/// Shows a modal error dialog (release build without console).
pub fn error_box(message: &str) {
    #[cfg(windows)]
    {
        use windows::Win32::UI::WindowsAndMessaging::{MB_ICONERROR, MB_OK, MessageBoxW};
        use windows::core::HSTRING;
        // SAFETY: both strings live until the call returns; no owner window.
        unsafe {
            MessageBoxW(
                None,
                &HSTRING::from(message),
                &HSTRING::from("FrameRush"),
                MB_OK | MB_ICONERROR,
            );
        }
    }
    #[cfg(not(windows))]
    eprintln!("{message}");
}
