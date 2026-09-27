//! The global hotkey. Parsing lives apart from Windows so it can be tested,
//! and the numbers below are the Win32 ones `RegisterHotKey` expects.

use anyhow::{Result, anyhow, bail};

const MOD_ALT: u32 = 0x0001;
const MOD_CONTROL: u32 = 0x0002;
const MOD_SHIFT: u32 = 0x0004;
const MOD_WIN: u32 = 0x0008;
/// Without this, holding the keys down fires over and over.
const MOD_NOREPEAT: u32 = 0x4000;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Hotkey {
    pub mods: u32,
    pub vk: u32,
}

/// Reads a combination like `Ctrl+Alt+C` or `Strg+Umschalt+F9`. Names are
/// accepted in English and German and the case does not matter.
pub fn parse(spec: &str) -> Result<Hotkey> {
    let mut mods = MOD_NOREPEAT;
    let mut key = None;
    for part in spec.split('+').map(str::trim).filter(|p| !p.is_empty()) {
        let lower = part.to_lowercase();
        let m = match lower.as_str() {
            "ctrl" | "control" | "strg" => Some(MOD_CONTROL),
            "alt" => Some(MOD_ALT),
            "shift" | "umschalt" => Some(MOD_SHIFT),
            "win" | "super" | "meta" => Some(MOD_WIN),
            _ => None,
        };
        match m {
            Some(m) => mods |= m,
            None => {
                if key.replace(vk_of(&lower).ok_or_else(|| anyhow!("unbekannte Taste {part:?} in {spec:?}"))?).is_some() {
                    bail!("{spec:?} nennt mehr als eine Taste");
                }
            }
        }
    }
    let vk = key.ok_or_else(|| anyhow!("{spec:?} nennt keine Taste"))?;
    // A lone key would swallow it system-wide; at least one modifier is needed.
    if mods == MOD_NOREPEAT {
        bail!("{spec:?} braucht mindestens Strg, Alt, Umschalt oder Win");
    }
    Ok(Hotkey { mods, vk })
}

/// Virtual key code for a single, already lowercased key name.
fn vk_of(name: &str) -> Option<u32> {
    if let Some(n) = name.strip_prefix('f').and_then(|n| n.parse::<u32>().ok()) {
        // F1 to F24 are consecutive from 0x70.
        return (1..=24).contains(&n).then(|| 0x6F + n);
    }
    let mut chars = name.chars();
    if let (Some(c), None) = (chars.next(), chars.next())
        && c.is_ascii_alphanumeric()
    {
        return Some(c.to_ascii_uppercase() as u32);
    }
    Some(match name {
        "space" | "leertaste" => 0x20,
        "tab" | "tabulator" => 0x09,
        "enter" | "return" | "eingabe" => 0x0D,
        "insert" | "einfg" | "einfügen" => 0x2D,
        "delete" | "entf" | "entfernen" => 0x2E,
        "home" | "pos1" => 0x24,
        "end" | "ende" => 0x23,
        "pageup" | "bild-auf" | "bildauf" => 0x21,
        "pagedown" | "bild-ab" | "bildab" => 0x22,
        "print" | "printscreen" | "druck" => 0x2C,
        "pause" => 0x13,
        "left" | "links" => 0x25,
        "up" | "hoch" => 0x26,
        "right" | "rechts" => 0x27,
        "down" | "runter" => 0x28,
        _ => return None,
    })
}

/// Registers the hotkey and runs the message loop, calling `on_press` on every
/// press. Returns only if the loop ends, which in practice means the process is
/// shutting down.
#[cfg(windows)]
pub fn listen(hk: Hotkey, spec: &str, mut on_press: impl FnMut()) -> Result<()> {
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::{RegisterHotKey, UnregisterHotKey};
    use windows_sys::Win32::UI::WindowsAndMessaging::{GetMessageW, MSG, WM_HOTKEY};

    const ID: i32 = 1;
    // SAFETY: a null window makes the message land in this thread's own queue,
    // which is exactly the queue pumped below.
    if unsafe { RegisterHotKey(std::ptr::null_mut(), ID, hk.mods, hk.vk) } == 0 {
        let err = std::io::Error::last_os_error();
        bail!("Hotkey {spec} lässt sich nicht belegen ({err}) — nimmt ihn schon ein anderes Programm?");
    }
    let mut msg: MSG = unsafe { std::mem::zeroed() };
    // SAFETY: plain message pump on a zeroed MSG we own.
    while unsafe { GetMessageW(&mut msg, std::ptr::null_mut(), 0, 0) } > 0 {
        if msg.message == WM_HOTKEY && msg.wParam == ID as usize {
            on_press();
        }
    }
    // SAFETY: undoing our own registration.
    unsafe { UnregisterHotKey(std::ptr::null_mut(), ID) };
    Ok(())
}

#[cfg(not(windows))]
pub fn listen(_hk: Hotkey, _spec: &str, _on_press: impl FnMut()) -> Result<()> {
    bail!("Globale Hotkeys gibt es in clipd nur unter Windows")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_english_and_german_names() {
        let a = parse("Ctrl+Alt+C").unwrap();
        let b = parse("strg + alt + c").unwrap();
        assert_eq!(a, b, "Schreibweise und Leerzeichen sind gleichgültig");
        assert_eq!(a.mods, MOD_NOREPEAT | MOD_CONTROL | MOD_ALT);
        assert_eq!(a.vk, 'C' as u32);
        assert_eq!(parse("Umschalt+F9").unwrap(), parse("Shift+f9").unwrap());
    }

    /// Die Tastennamen müssen auf die Win32-Codes treffen.
    #[test]
    fn maps_keys_to_win32_codes() {
        assert_eq!(parse("Alt+F1").unwrap().vk, 0x70);
        assert_eq!(parse("Alt+F12").unwrap().vk, 0x7B);
        assert_eq!(parse("Alt+F24").unwrap().vk, 0x87);
        assert_eq!(parse("Alt+7").unwrap().vk, '7' as u32);
        assert_eq!(parse("Alt+Leertaste").unwrap().vk, 0x20);
        assert_eq!(parse("Alt+Entf").unwrap().vk, 0x2E);
        assert_eq!(parse("Alt+Druck").unwrap().vk, 0x2C);
    }

    /// Jede Belegung muss wiederholungsfrei sein, sonst feuert Halten dauernd.
    #[test]
    fn always_asks_for_norepeat() {
        assert_eq!(parse("Win+K").unwrap().mods & MOD_NOREPEAT, MOD_NOREPEAT);
    }

    #[test]
    fn rejects_nonsense() {
        for spec in ["C", "Ctrl", "", "Ctrl+Alt", "Ctrl+Ü", "Ctrl+F25", "Ctrl+A+B", "Ctrl+F0"] {
            assert!(parse(spec).is_err(), "{spec:?} hätte abgelehnt werden müssen");
        }
    }
}
