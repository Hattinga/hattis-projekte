//! Synthetic video source: an animated test pattern at a fixed frame rate.
//!
//! It stands in for the capture card so the whole pipeline (capture thread →
//! mailbox → GPU upload → present) can be exercised without hardware. The
//! pattern is designed for judging the viewer, not for looking pretty:
//!
//! * a large frame counter and media timestamp (readable in screenshots and
//!   in slow-motion camera footage),
//! * a vertical bar that moves a fixed number of pixels per frame, so judder
//!   or tearing is visible,
//! * a row of 60 cells of which exactly one (`frame % 60`) is lit, like a
//!   frame clock,
//! * colour bars and a grey ramp to check YUV→RGB conversion and range.
//!
//! Frames are released on an absolute schedule (`start + n · period`). The
//! only wait in this source is that simulated hardware cadence; if the thread
//! falls behind, missed slots are skipped (visible as sequence gaps) rather
//! than delivered in a burst.

use std::thread;
use std::time::Instant;

use super::{Frame, PixelFormat, SourceError, SourceInfo, VideoMode, VideoSource};
use crate::font;

/// 75 % colour bars (white, yellow, cyan, green, magenta, red, blue, black).
const BARS: [[u8; 3]; 8] = [
    [191, 191, 191],
    [191, 191, 0],
    [0, 191, 191],
    [0, 191, 0],
    [191, 0, 191],
    [191, 0, 0],
    [0, 0, 191],
    [0, 0, 0],
];
const CLOCK_CELLS: usize = 60;
/// Frames the moving bar needs to cross the full width.
const SWEEP_FRAMES: usize = 120;

pub struct SyntheticSource {
    info: SourceInfo,
    layout: Layout,
    /// Static part of the pattern, rendered once.
    base: Vec<u8>,
    start: Option<Instant>,
    next_index: u64,
}

impl SyntheticSource {
    pub fn new(mode: VideoMode) -> Result<Self, SourceError> {
        if mode.format.frame_len(mode.width, mode.height).is_none() {
            return Err(SourceError::UnsupportedMode(format!(
                "{}x{} is not a valid size for {}",
                mode.width,
                mode.height,
                mode.format.name()
            )));
        }
        let layout = Layout::new(mode.width as usize, mode.height as usize);
        let mut source = Self {
            info: SourceInfo {
                name: "Synthetic test pattern".into(),
                mode,
            },
            layout,
            base: Vec::new(),
            start: None,
            next_index: 0,
        };
        source.base = source.render_base();
        Ok(source)
    }

    /// Renders frame `index` immediately, without any pacing.
    pub fn render(&self, index: u64) -> Vec<u8> {
        let mode = self.info.mode;
        let l = &self.layout;
        let mut data = self.base.clone();
        let mut canvas = Canvas::new(mode, &mut data);

        let step = (l.width / SWEEP_FRAMES).max(1);
        let travel = l.width.saturating_sub(l.bar_width).max(1);
        let x = (index as usize).wrapping_mul(step) % travel;
        canvas.fill_rect(x & !1, 0, l.bar_width, l.clock_top, [255, 255, 255]);

        let lit = index as usize % CLOCK_CELLS;
        canvas.fill_rect(
            l.clock_x(lit),
            l.clock_y,
            l.clock_cell,
            l.clock_h,
            [255, 255, 255],
        );

        let t = mode.frame_rate.time_of_frame(index);
        let line1 = format!("FRAME {index:07}");
        let line2 = format!(
            "T {:02}:{:02}.{:03}",
            t.as_secs() / 60,
            t.as_secs() % 60,
            t.subsec_millis()
        );
        let s = l.unit;
        let box_w = font::text_width(&line1).max(font::text_width(&line2)) * s + 4 * s;
        let box_h = (2 * font::GLYPH_HEIGHT + 3) * s + 4 * s;
        // Top right: the viewer's statistics overlay sits top left.
        let box_x = l.width.saturating_sub(l.margin + box_w) & !1;
        canvas.fill_rect(box_x, l.margin, box_w, box_h, [0, 0, 0]);
        canvas.text(box_x + 2 * s, l.margin + 2 * s, s, &line1, 255);
        canvas.text(
            box_x + 2 * s,
            l.margin + 2 * s + (font::GLYPH_HEIGHT + 3) * s,
            s,
            &line2,
            255,
        );
        data
    }

    fn render_base(&self) -> Vec<u8> {
        let mode = self.info.mode;
        let l = &self.layout;
        let len = mode
            .format
            .frame_len(mode.width, mode.height)
            .expect("validated in new()");
        let mut data = vec![0; len];
        let mut canvas = Canvas::new(mode, &mut data);

        let bar_w = l.width.div_ceil(BARS.len());
        for (i, rgb) in BARS.iter().enumerate() {
            canvas.fill_rect(i * bar_w, 0, bar_w, l.ramp_top, *rgb);
        }
        for x in 0..l.width {
            let level = (x * 255 / (l.width - 1).max(1)) as u8;
            canvas.fill_rect(x, l.ramp_top, 1, l.clock_top - l.ramp_top, [level; 3]);
        }
        canvas.fill_rect(0, l.clock_top, l.width, l.height - l.clock_top, [0, 0, 0]);
        for cell in 0..CLOCK_CELLS {
            canvas.fill_rect(
                l.clock_x(cell),
                l.clock_y,
                l.clock_cell,
                l.clock_h,
                [48, 48, 48],
            );
        }
        let caption = format!("FRAMERUSH SYNTHETIC SOURCE  {}", mode).to_ascii_uppercase();
        let small = (l.unit / 2).max(1);
        canvas.text(
            l.margin,
            l.height
                .saturating_sub(l.margin + font::GLYPH_HEIGHT * small),
            small,
            &caption,
            200,
        );
        data
    }
}

impl VideoSource for SyntheticSource {
    fn info(&self) -> &SourceInfo {
        &self.info
    }

    fn next_frame(&mut self) -> Result<Frame, SourceError> {
        let rate = self.info.mode.frame_rate;
        let start = *self.start.get_or_insert_with(Instant::now);
        let index = self.next_index;
        let data = self.render(index);

        // Simulated hardware cadence: hold the finished frame until its slot.
        let deadline = start + rate.time_of_frame(index);
        if let Some(wait) = deadline.checked_duration_since(Instant::now()) {
            thread::sleep(wait);
        }
        let ready_at = Instant::now();

        // Continue with the next slot that has not started yet; if we are
        // late, skip the missed slots instead of bursting through them.
        let current_slot = rate.frame_at(ready_at - start);
        self.next_index = (index + 1).max(current_slot + 1);

        Ok(Frame {
            sequence: index,
            width: self.info.mode.width,
            height: self.info.mode.height,
            format: self.info.mode.format,
            data,
            ready_at,
        })
    }
}

/// Positions of the pattern elements, derived from the frame size.
struct Layout {
    width: usize,
    height: usize,
    /// Text scale for the counter: 10 px per font cell at 1080p.
    unit: usize,
    margin: usize,
    bar_width: usize,
    ramp_top: usize,
    clock_top: usize,
    clock_y: usize,
    clock_h: usize,
    clock_pitch: usize,
    clock_cell: usize,
}

impl Layout {
    fn new(width: usize, height: usize) -> Self {
        let unit = (height / 108).max(1);
        let clock_top = height * 13 / 16;
        let clock_pitch = (width / CLOCK_CELLS).max(1);
        Self {
            width,
            height,
            unit,
            margin: 4 * unit,
            bar_width: (2 * unit).max(2),
            ramp_top: height * 2 / 3,
            clock_top,
            clock_y: clock_top + 3 * unit,
            clock_h: 8 * unit,
            clock_pitch,
            clock_cell: (clock_pitch * 3 / 4).max(1),
        }
    }

    fn clock_x(&self, cell: usize) -> usize {
        cell * self.clock_pitch + (self.clock_pitch - self.clock_cell) / 2
    }
}

/// BT.709 limited-range Y'CbCr for an 8-bit sRGB-encoded colour.
pub(crate) fn rgb_to_ycbcr709([r, g, b]: [u8; 3]) -> (u8, u8, u8) {
    let (r, g, b) = (
        f32::from(r) / 255.0,
        f32::from(g) / 255.0,
        f32::from(b) / 255.0,
    );
    let y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    let cb = (b - y) / 1.8556;
    let cr = (r - y) / 1.5748;
    let to_u8 = |v: f32| v.round().clamp(0.0, 255.0) as u8;
    (
        to_u8(16.0 + 219.0 * y),
        to_u8(128.0 + 224.0 * cb),
        to_u8(128.0 + 224.0 * cr),
    )
}

/// Minimal drawing on a tightly packed frame buffer. All coordinates are
/// clipped to the frame.
struct Canvas<'a> {
    format: PixelFormat,
    width: usize,
    height: usize,
    data: &'a mut [u8],
}

impl<'a> Canvas<'a> {
    fn new(mode: VideoMode, data: &'a mut [u8]) -> Self {
        Self {
            format: mode.format,
            width: mode.width as usize,
            height: mode.height as usize,
            data,
        }
    }

    fn clip(&self, x: usize, y: usize, w: usize, h: usize) -> Option<(usize, usize, usize, usize)> {
        let x1 = x.saturating_add(w).min(self.width);
        let y1 = y.saturating_add(h).min(self.height);
        (x < x1 && y < y1).then_some((x, y, x1, y1))
    }

    fn fill_rect(&mut self, x: usize, y: usize, w: usize, h: usize, rgb: [u8; 3]) {
        let Some((x0, y0, x1, y1)) = self.clip(x, y, w, h) else {
            return;
        };
        let width = self.width;
        match self.format {
            PixelFormat::Bgra8 => {
                let px = [rgb[2], rgb[1], rgb[0], 255];
                for row in y0..y1 {
                    let line = &mut self.data[(row * width + x0) * 4..(row * width + x1) * 4];
                    for out in line.as_chunks_mut::<4>().0 {
                        *out = px;
                    }
                }
            }
            PixelFormat::Nv12 => {
                let (luma, cb, cr) = rgb_to_ycbcr709(rgb);
                for row in y0..y1 {
                    self.data[row * width + x0..row * width + x1].fill(luma);
                }
                // Chroma covers 2×2 pixel blocks; an odd edge colours the
                // neighbouring pixel's chroma too, which is fine for a pattern.
                let chroma = width * self.height;
                let (cx0, cx1) = (x0 / 2, x1.div_ceil(2));
                for row in y0 / 2..y1.div_ceil(2) {
                    let start = chroma + row * width;
                    for pair in self.data[start + cx0 * 2..start + cx1 * 2]
                        .as_chunks_mut::<2>()
                        .0
                    {
                        *pair = [cb, cr];
                    }
                }
            }
        }
    }

    /// Sets brightness only (full-range `level`). On NV12 the chroma below is
    /// kept, so this is for drawing on neutral (black/grey) backgrounds.
    fn fill_luma(&mut self, x: usize, y: usize, w: usize, h: usize, level: u8) {
        match self.format {
            PixelFormat::Bgra8 => self.fill_rect(x, y, w, h, [level; 3]),
            PixelFormat::Nv12 => {
                let Some((x0, y0, x1, y1)) = self.clip(x, y, w, h) else {
                    return;
                };
                let luma = rgb_to_ycbcr709([level; 3]).0;
                for row in y0..y1 {
                    self.data[row * self.width + x0..row * self.width + x1].fill(luma);
                }
            }
        }
    }

    fn text(&mut self, x: usize, y: usize, scale: usize, text: &str, level: u8) {
        font::rasterize(text, |cx, cy| {
            self.fill_luma(x + cx * scale, y + cy * scale, scale, scale, level);
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::capture::FrameRate;
    use std::time::Duration;

    fn mode(format: PixelFormat, fps: u32) -> VideoMode {
        VideoMode {
            width: 1920,
            height: 1080,
            format,
            frame_rate: FrameRate::new(fps, 1).unwrap(),
        }
    }

    #[test]
    fn bt709_limited_range_reference_values() {
        assert_eq!(rgb_to_ycbcr709([255, 255, 255]), (235, 128, 128));
        assert_eq!(rgb_to_ycbcr709([0, 0, 0]), (16, 128, 128));
        assert_eq!(rgb_to_ycbcr709([255, 0, 0]), (63, 102, 240));
        assert_eq!(rgb_to_ycbcr709([0, 0, 255]), (32, 240, 118));
    }

    #[test]
    fn frames_have_the_exact_plane_size() {
        for format in [PixelFormat::Nv12, PixelFormat::Bgra8] {
            let source = SyntheticSource::new(mode(format, 60)).unwrap();
            assert_eq!(
                source.render(0).len(),
                format.frame_len(1920, 1080).unwrap()
            );
        }
    }

    #[test]
    fn content_changes_every_frame() {
        let source = SyntheticSource::new(mode(PixelFormat::Nv12, 60)).unwrap();
        let a = source.render(41);
        let b = source.render(42);
        assert_ne!(a, b);
        assert_eq!(a, source.render(41), "rendering must be deterministic");
    }

    #[test]
    fn counter_text_is_drawn_white_on_black() {
        let source = SyntheticSource::new(mode(PixelFormat::Nv12, 60)).unwrap();
        let frame = source.render(0);
        // First text line at 1080p: right-aligned box at x 1070, text from
        // x 1090, rows 60..130 (scale 10).
        let row = |y: usize| &frame[y * 1920 + 1090..y * 1920 + 1860];
        assert!(
            (60..130).any(|y| row(y).contains(&235)),
            "white text luma missing"
        );
        assert!(
            (60..130).any(|y| row(y).contains(&16)),
            "black box luma missing"
        );
    }

    #[test]
    fn odd_nv12_size_is_rejected() {
        let mut bad = mode(PixelFormat::Nv12, 60);
        bad.width = 1919;
        assert!(SyntheticSource::new(bad).is_err());
    }

    #[test]
    fn frames_follow_the_schedule_and_never_burst() {
        let fps = 200;
        let mut source = SyntheticSource::new(VideoMode {
            width: 64,
            height: 64,
            format: PixelFormat::Bgra8,
            frame_rate: FrameRate::new(fps, 1).unwrap(),
        })
        .unwrap();
        let first = source.next_frame().unwrap();
        let mut last = first.sequence;
        for _ in 0..9 {
            let frame = source.next_frame().unwrap();
            assert!(frame.sequence > last);
            last = frame.sequence;
        }
        // Frame n is never released before start + n·period (lower bound only;
        // an upper bound would make the test depend on scheduler load).
        let period = Duration::from_secs(1) / fps;
        let elapsed = Instant::now() - first.ready_at;
        assert!(
            elapsed + Duration::from_millis(1) >= period * (last - first.sequence) as u32,
            "{elapsed:?} for {} frames",
            last - first.sequence
        );
    }
}
