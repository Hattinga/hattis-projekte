//! Which game a clip belongs to: the window in front at the moment it is
//! saved. A window that covers its whole monitor counts as a game; anything
//! else is the desktop.

pub const DESKTOP: &str = "Desktop";

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Foreground {
    /// Lower-case file name of the program, e.g. `valorant-win64-shipping.exe`.
    pub exe: String,
    pub title: String,
    /// FileDescription (or ProductName) from the program's version resource.
    pub description: String,
    pub fullscreen: bool,
    /// The window itself, for recording just it.
    pub hwnd: u64,
    /// The program's full path.
    pub path: String,
}

/// The window to record in game mode: a fullscreen game's, or none for the
/// screen.
pub fn game_window(fg: &Foreground) -> Option<u64> {
    (fg.fullscreen && !fg.exe.is_empty() && fg.hwnd != 0).then_some(fg.hwnd)
}

/// The name a clip's folder gets.
///
/// The version resource names most games properly ("Counter-Strike 2"), but
/// engines and runtimes describe themselves instead ("Java(TM) Platform SE
/// binary", "VALORANT-Win64-Shipping"); then the window title is the better
/// guess, and the file name the last resort.
pub fn game_name(fg: &Foreground) -> String {
    if !fg.fullscreen || fg.exe.is_empty() {
        return DESKTOP.into();
    }
    let desc = clean(&fg.description);
    if !desc.is_empty() && !generic(&desc) {
        return desc;
    }
    let title = clean(&fg.title);
    if !title.is_empty() && title.chars().count() <= 60 {
        return title;
    }
    let stem = fg.exe.trim_end_matches(".exe");
    let stem = ["-win64-shipping", "-win32-shipping", "_win64", "-win64"]
        .iter()
        .fold(stem.to_string(), |s, suffix| s.strip_suffix(suffix).map(str::to_string).unwrap_or(s));
    let mut c = stem.chars();
    match c.next() {
        Some(first) => first.to_uppercase().chain(c).collect(),
        None => DESKTOP.into(),
    }
}

fn clean(s: &str) -> String {
    let s: String = s.chars().filter(|c| !matches!(c, '™' | '®' | '©')).collect();
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Descriptions of engines and runtimes rather than of games.
fn generic(desc: &str) -> bool {
    let d = desc.to_lowercase();
    const EXACT: &[&str] = &[
        "java(tm) platform se binary",
        "openjdk platform binary",
        "bootstrappackagedgame",
        "unrealgame",
        "unity",
        "electron",
        "python",
        "application",
        "game",
        "launcher",
    ];
    EXACT.contains(&d.as_str()) || d.contains("shipping") || d.contains("platform binary")
}

/// A name that works as a Windows folder name.
pub fn folder_name(name: &str) -> String {
    let s: String = name.chars().map(|c| if c.is_control() || "<>:\"/\\|?*".contains(c) { ' ' } else { c }).collect();
    let s = s.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut s: String = s.chars().take(60).collect();
    while s.ends_with('.') || s.ends_with(' ') {
        s.pop();
    }
    if s.is_empty() {
        return "Unbekannt".into();
    }
    // CON, PRN, AUX, NUL, COM1–9 and LPT1–9 name devices, not folders.
    let lower = s.to_lowercase();
    let port =
        |p: &str| lower.strip_prefix(p).is_some_and(|n| n.len() == 1 && n != "0" && n.chars().all(|c| c.is_ascii_digit()));
    if ["con", "prn", "aux", "nul"].contains(&lower.as_str()) || port("com") || port("lpt") {
        s.push('_');
    }
    s
}

/// The window in front right now, with the name its program gives itself.
/// clipd's own window counts as the desktop, so saving from the library does
/// not file the clip under "clipd".
pub fn foreground() -> Foreground {
    let mut fg = foreground_window();
    if !fg.path.is_empty() {
        fg.description = version_string(&fg.path);
    }
    fg
}

/// The window in front without reading the program's version resource —
/// cheap enough to ask every second.
#[cfg(windows)]
pub fn foreground_window() -> Foreground {
    use windows::Win32::Foundation::{CloseHandle, RECT};
    use windows::Win32::Graphics::Gdi::{GetMonitorInfoW, MONITOR_DEFAULTTONEAREST, MONITORINFO, MonitorFromWindow};
    use windows::Win32::System::Threading::{
        OpenProcess, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION, QueryFullProcessImageNameW,
    };
    use windows::Win32::UI::WindowsAndMessaging::{
        GetClassNameW, GetForegroundWindow, GetWindowRect, GetWindowTextW, GetWindowThreadProcessId,
    };
    use windows::core::PWSTR;

    // SAFETY: plain Win32 queries into buffers we own and pass with their sizes.
    unsafe {
        let hwnd = GetForegroundWindow();
        if hwnd.is_invalid() {
            return Foreground::default();
        }
        let mut class = [0u16; 128];
        let n = GetClassNameW(hwnd, &mut class).max(0) as usize;
        if matches!(String::from_utf16_lossy(&class[..n]).as_str(), "Progman" | "WorkerW" | "Shell_TrayWnd") {
            return Foreground::default();
        }
        let mut pid = 0u32;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == std::process::id() {
            return Foreground::default();
        }
        let mut title = [0u16; 256];
        let n = GetWindowTextW(hwnd, &mut title).max(0) as usize;
        let title = String::from_utf16_lossy(&title[..n]);

        let mut path = String::new();
        if let Ok(h) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) {
            let mut buf = [0u16; 1024];
            let mut len = buf.len() as u32;
            if QueryFullProcessImageNameW(h, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut len).is_ok() {
                path = String::from_utf16_lossy(&buf[..len as usize]);
            }
            let _ = CloseHandle(h);
        }
        let exe = std::path::Path::new(&path).file_name().map(|f| f.to_string_lossy().to_lowercase()).unwrap_or_default();

        let mut rect = RECT::default();
        let mut fullscreen = false;
        if GetWindowRect(hwnd, &mut rect).is_ok() {
            let mon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
            let mut info = MONITORINFO { cbSize: std::mem::size_of::<MONITORINFO>() as u32, ..Default::default() };
            if GetMonitorInfoW(mon, &mut info).as_bool() {
                let m = info.rcMonitor;
                fullscreen = rect.left <= m.left && rect.top <= m.top && rect.right >= m.right && rect.bottom >= m.bottom;
            }
        }
        Foreground { exe, title, description: String::new(), fullscreen, hwnd: hwnd.0 as u64, path }
    }
}

#[cfg(not(windows))]
pub fn foreground_window() -> Foreground {
    Foreground::default()
}

#[cfg(not(windows))]
fn version_string(_path: &str) -> String {
    String::new()
}

/// FileDescription, else ProductName, from a program's version resource.
#[cfg(windows)]
fn version_string(path: &str) -> String {
    use windows::Win32::Storage::FileSystem::{GetFileVersionInfoSizeW, GetFileVersionInfoW, VerQueryValueW};
    use windows::core::HSTRING;

    // SAFETY: the version block is read into a buffer of the size Windows asked
    // for, and every pointer VerQueryValueW hands back points into that buffer.
    unsafe {
        let p = HSTRING::from(path);
        let size = GetFileVersionInfoSizeW(&p, None);
        if size == 0 {
            return String::new();
        }
        let mut data = vec![0u8; size as usize];
        if GetFileVersionInfoW(&p, None, size, data.as_mut_ptr().cast()).is_err() {
            return String::new();
        }
        let query = |key: &str| -> Option<(*mut std::ffi::c_void, u32)> {
            let mut ptr = std::ptr::null_mut();
            let mut len = 0u32;
            VerQueryValueW(data.as_ptr().cast(), &HSTRING::from(key), &mut ptr, &mut len).as_bool().then_some((ptr, len))
        };
        let mut langs = vec![(0x0409u16, 0x04B0u16), (0x0409, 0x04E4), (0x0000, 0x04B0)];
        if let Some((ptr, len)) = query(r"\VarFileInfo\Translation") {
            let pairs = std::slice::from_raw_parts(ptr as *const u16, len as usize / 2);
            let listed: Vec<(u16, u16)> = pairs.as_chunks::<2>().0.iter().map(|&[lang, cp]| (lang, cp)).collect();
            langs.splice(0..0, listed);
        }
        for field in ["FileDescription", "ProductName"] {
            for (lang, cp) in &langs {
                let Some((ptr, len)) = query(&format!(r"\StringFileInfo\{lang:04x}{cp:04x}\{field}")) else { continue };
                if len > 1 {
                    let s = std::slice::from_raw_parts(ptr as *const u16, len as usize);
                    let end = s.iter().position(|&c| c == 0).unwrap_or(s.len());
                    let text = String::from_utf16_lossy(&s[..end]).trim().to_string();
                    if !text.is_empty() {
                        return text;
                    }
                }
            }
        }
        String::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fg(exe: &str, desc: &str, title: &str) -> Foreground {
        Foreground {
            exe: exe.into(),
            description: desc.into(),
            title: title.into(),
            fullscreen: true,
            hwnd: 7,
            path: String::new(),
        }
    }

    /// Die Beschreibung im Programm nennt die meisten Spiele richtig.
    #[test]
    fn prefers_the_exe_description() {
        assert_eq!(game_name(&fg("cs2.exe", "Counter-Strike 2", "Counter-Strike 2")), "Counter-Strike 2");
        assert_eq!(game_name(&fg("rocketleague.exe", "Rocket League®", "")), "Rocket League");
    }

    /// Engines und Laufzeitumgebungen beschreiben sich selbst, nicht das Spiel.
    #[test]
    fn engines_and_runtimes_fall_back_to_the_title() {
        assert_eq!(game_name(&fg("javaw.exe", "Java(TM) Platform SE binary", "Minecraft 1.21.4")), "Minecraft 1.21.4");
        assert_eq!(game_name(&fg("valorant-win64-shipping.exe", "VALORANT-Win64-Shipping", "VALORANT  ")), "VALORANT");
        assert_eq!(game_name(&fg("fortniteclient-win64-shipping.exe", "", "")), "Fortniteclient");
    }

    /// Ein Fenster, das nicht den ganzen Bildschirm füllt, ist kein Spiel.
    #[test]
    fn windowed_is_desktop() {
        let mut f = fg("chrome.exe", "Google Chrome", "YouTube - Google Chrome");
        f.fullscreen = false;
        assert_eq!(game_name(&f), DESKTOP);
        assert_eq!(game_name(&Foreground::default()), DESKTOP);
    }

    /// Nur ein Spiel im Vollbild wird allein aufgenommen.
    #[test]
    fn only_a_fullscreen_game_gets_its_own_capture() {
        assert_eq!(game_window(&fg("cs2.exe", "Counter-Strike 2", "")), Some(7));
        let windowed = Foreground { fullscreen: false, ..fg("cs2.exe", "", "") };
        assert_eq!(game_window(&windowed), None);
        assert_eq!(game_window(&Foreground::default()), None);
    }

    #[test]
    fn folder_names_are_safe() {
        assert_eq!(folder_name("Half-Life: Alyx"), "Half-Life Alyx");
        assert_eq!(folder_name("  ...  "), "Unbekannt");
        assert_eq!(folder_name("Game?.*"), "Game");
        assert_eq!(folder_name("con"), "con_");
        assert_eq!(folder_name("COM7"), "COM7_");
        assert_eq!(folder_name("lpt9"), "lpt9_");
        assert_eq!(folder_name("COM10"), "COM10", "nur einstellige Anschlüsse");
        assert_eq!(folder_name("Company"), "Company");
        assert_eq!(folder_name(&"x".repeat(100)).len(), 60);
    }
}
