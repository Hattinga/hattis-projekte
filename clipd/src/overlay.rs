//! A short note in the top right corner — "Clip gespeichert" — that shows over
//! a game without taking the focus from it.
//!
//! A plain Win32 window rather than one of the app's web views: it has to
//! work for the command line too, it must never become the active window
//! (a game in exclusive fullscreen would drop out), clicks go through it,
//! and it keeps itself out of screen captures so it does not end up in the
//! next clip.

/// Shows the note for a moment; returns at once.
#[cfg(windows)]
pub fn flash(title: &str, detail: &str) {
    let (title, detail) = (title.to_string(), detail.to_string());
    let _ = std::thread::Builder::new().name("clipd-overlay".into()).spawn(move || {
        // SAFETY: the window lives and dies on this thread, which pumps its
        // messages until it is gone.
        unsafe { win::run(&title, &detail) }
    });
}

#[cfg(not(windows))]
pub fn flash(_title: &str, _detail: &str) {}

/// Opacity over time: in, hold, out. Returns `None` once it is over.
pub fn alpha_at(ms: u64) -> Option<u8> {
    const IN: u64 = 140;
    const HOLD: u64 = 2200;
    const OUT: u64 = 350;
    const FULL: f64 = 235.0;
    let a = match ms {
        t if t < IN => FULL * t as f64 / IN as f64,
        t if t < IN + HOLD => FULL,
        t if t < IN + HOLD + OUT => FULL * (1.0 - (t - IN - HOLD) as f64 / OUT as f64),
        _ => return None,
    };
    Some(a.round() as u8)
}

#[cfg(windows)]
mod win {
    use windows::Win32::Foundation::{COLORREF, HWND, LPARAM, LRESULT, POINT, RECT, WPARAM};
    use windows::Win32::Graphics::Gdi::*;
    use windows::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows::Win32::UI::WindowsAndMessaging::*;
    use windows::core::w;

    thread_local! {
        static TEXT: std::cell::RefCell<(Vec<u16>, Vec<u16>)> = Default::default();
        static STARTED: std::cell::Cell<Option<std::time::Instant>> = const { std::cell::Cell::new(None) };
    }

    const TIMER: usize = 1;

    pub unsafe fn run(title: &str, detail: &str) {
        unsafe {
            TEXT.with(|t| *t.borrow_mut() = (title.encode_utf16().collect(), detail.encode_utf16().collect()));
            let instance = GetModuleHandleW(None).unwrap_or_default();
            let class = w!("clipd-overlay");
            let wc = WNDCLASSW {
                lpfnWndProc: Some(proc),
                hInstance: instance.into(),
                lpszClassName: class,
                hCursor: LoadCursorW(None, IDC_ARROW).unwrap_or_default(),
                ..Default::default()
            };
            // A second note finds the class already there, which is fine.
            RegisterClassW(&wc);

            // Sized to the system DPI, placed on the monitor with the game.
            let dc = GetDC(None);
            let dpi = GetDeviceCaps(Some(dc), LOGPIXELSX).max(96);
            ReleaseDC(None, dc);
            let px = |v: i32| v * dpi / 96;
            let (w, h) = (px(300), px(62));
            let monitor = MonitorFromWindow(GetForegroundWindow(), MONITOR_DEFAULTTOPRIMARY);
            let mut info = MONITORINFO { cbSize: std::mem::size_of::<MONITORINFO>() as u32, ..Default::default() };
            let _ = GetMonitorInfoW(monitor, &mut info);
            let area = info.rcWork;
            let (x, y) = (area.right - w - px(24), area.top + px(24));

            let Ok(hwnd) = CreateWindowExW(
                WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW,
                class,
                w!("clipd"),
                WS_POPUP,
                x,
                y,
                w,
                h,
                None,
                None,
                Some(instance.into()),
                None,
            ) else {
                return;
            };
            // Out of every screen capture, clipd's own included.
            let _ = SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE);
            let region = CreateRoundRectRgn(0, 0, w + 1, h + 1, px(26), px(26));
            SetWindowRgn(hwnd, Some(region), false);
            let _ = SetLayeredWindowAttributes(hwnd, COLORREF(0), 0, LWA_ALPHA);
            let _ = ShowWindow(hwnd, SW_SHOWNOACTIVATE);
            STARTED.with(|s| s.set(Some(std::time::Instant::now())));
            SetTimer(Some(hwnd), TIMER, 15, None);

            let mut msg = MSG::default();
            while GetMessageW(&mut msg, None, 0, 0).as_bool() {
                let _ = TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
        }
    }

    unsafe extern "system" fn proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
        unsafe {
            match msg {
                WM_TIMER => {
                    let ms = STARTED.with(|s| s.get()).map_or(0, |t| t.elapsed().as_millis() as u64);
                    match super::alpha_at(ms) {
                        Some(a) => {
                            let _ = SetLayeredWindowAttributes(hwnd, COLORREF(0), a, LWA_ALPHA);
                        }
                        None => {
                            let _ = KillTimer(Some(hwnd), TIMER);
                            let _ = DestroyWindow(hwnd);
                        }
                    }
                    LRESULT(0)
                }
                WM_PAINT => {
                    paint(hwnd);
                    LRESULT(0)
                }
                // Never the active window, not even when clicked.
                WM_MOUSEACTIVATE => LRESULT(MA_NOACTIVATE as isize),
                WM_DESTROY => {
                    PostQuitMessage(0);
                    LRESULT(0)
                }
                _ => DefWindowProcW(hwnd, msg, wparam, lparam),
            }
        }
    }

    unsafe fn paint(hwnd: HWND) {
        unsafe {
            let mut ps = PAINTSTRUCT::default();
            let dc = BeginPaint(hwnd, &mut ps);
            let mut r = RECT::default();
            let _ = GetClientRect(hwnd, &mut r);
            let scale = |v: i32| v * r.bottom / 62;

            let bg = CreateSolidBrush(COLORREF(0x0020_1E1E));
            FillRect(dc, &r, bg);
            let _ = DeleteObject(bg.into());

            // The green circle with a white tick.
            let (cx, cy, rad) = (scale(31), r.bottom / 2, scale(15));
            let green = CreateSolidBrush(COLORREF(0x0058_D130));
            let old_brush = SelectObject(dc, green.into());
            let old_pen = SelectObject(dc, GetStockObject(NULL_PEN));
            let _ = Ellipse(dc, cx - rad, cy - rad, cx + rad + 1, cy + rad + 1);
            let pen = CreatePen(PS_SOLID, scale(3).max(2), COLORREF(0x00FF_FFFF));
            SelectObject(dc, pen.into());
            let tick = [
                POINT { x: cx - scale(7), y: cy },
                POINT { x: cx - scale(2), y: cy + scale(5) },
                POINT { x: cx + scale(7), y: cy - scale(5) },
            ];
            let _ = Polyline(dc, &tick);
            SelectObject(dc, old_pen);
            SelectObject(dc, old_brush);
            let _ = DeleteObject(pen.into());
            let _ = DeleteObject(green.into());

            SetBkMode(dc, TRANSPARENT);
            let font = |size: i32, weight: i32| {
                CreateFontW(
                    -scale(size),
                    0,
                    0,
                    0,
                    weight,
                    0,
                    0,
                    0,
                    DEFAULT_CHARSET,
                    OUT_DEFAULT_PRECIS,
                    CLIP_DEFAULT_PRECIS,
                    CLEARTYPE_QUALITY,
                    DEFAULT_PITCH.0 as u32,
                    w!("Segoe UI"),
                )
            };
            let (bold, regular) = (font(16, 600), font(13, 400));
            TEXT.with(|t| {
                let (title, detail) = &mut *t.borrow_mut();
                let left = scale(56);
                let old = SelectObject(dc, bold.into());
                SetTextColor(dc, COLORREF(0x00FF_FFFF));
                let mut top = RECT { left, top: scale(11), right: r.right - scale(14), bottom: scale(33) };
                DrawTextW(dc, title, &mut top, DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
                SelectObject(dc, regular.into());
                SetTextColor(dc, COLORREF(0x00B4_B4B4));
                let mut bottom = RECT { left, top: scale(33), right: r.right - scale(14), bottom: scale(54) };
                DrawTextW(dc, detail, &mut bottom, DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
                SelectObject(dc, old);
            });
            let _ = DeleteObject(bold.into());
            let _ = DeleteObject(regular.into());
            let _ = EndPaint(hwnd, &ps);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Weich rein, eine Weile stehen, weich raus, dann weg.
    #[test]
    fn fades_in_holds_and_fades_out() {
        assert_eq!(alpha_at(0), Some(0));
        assert!(alpha_at(70).unwrap() > 0 && alpha_at(70).unwrap() < 235);
        assert_eq!(alpha_at(1000), Some(235));
        assert!(alpha_at(2500).unwrap() < 235);
        assert_eq!(alpha_at(3000), None);
    }
}
