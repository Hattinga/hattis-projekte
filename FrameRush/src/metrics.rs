//! Frame counters and software timing.
//!
//! Every timestamp here is taken by this process with `Instant::now()`. They
//! describe the software path only (frame available → handed to the
//! presentation engine). They do **not** include capture-card buffering, USB
//! transfer, DWM composition, display scan-out or panel response, so they are
//! a lower bound for, not a measurement of, HDMI-to-photon latency.

use std::time::{Duration, Instant};

use crate::capture::mailbox::MailboxStats;

/// Count, mean, min and max of a set of durations.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct DurationStats {
    count: u32,
    total: Duration,
    min: Duration,
    max: Duration,
}

impl DurationStats {
    pub fn record(&mut self, value: Duration) {
        if self.count == 0 {
            self.min = value;
            self.max = value;
        } else {
            self.min = self.min.min(value);
            self.max = self.max.max(value);
        }
        self.count += 1;
        self.total += value;
    }

    pub fn mean(&self) -> Option<Duration> {
        (self.count > 0).then(|| self.total / self.count)
    }

    pub fn min(&self) -> Option<Duration> {
        (self.count > 0).then_some(self.min)
    }

    pub fn max(&self) -> Option<Duration> {
        (self.count > 0).then_some(self.max)
    }
}

/// Measurements over one reporting window plus totals since start.
#[derive(Debug, Clone, Copy)]
pub struct Snapshot {
    /// Frames the source published per second.
    pub input_fps: f64,
    /// New frames presented per second (re-presents of an old frame, e.g. on
    /// resize, are not counted).
    pub shown_fps: f64,
    /// Frame ready → taken by the renderer (includes waiting for a swapchain
    /// image, because the renderer acquires before it takes).
    pub ready_to_take: DurationStats,
    /// Frame ready → `present()` returned.
    pub ready_to_present: DurationStats,
    /// Interval between consecutive presents of new frames (frame pacing).
    pub present_interval: DurationStats,
    pub total_published: u64,
    pub total_shown: u64,
    /// Replaced in the mailbox before the renderer took them.
    pub dropped_mailbox: u64,
    /// Sequence numbers the source never delivered.
    pub dropped_source: u64,
    /// Taken but not presented (window minimized, surface unavailable).
    pub not_shown: u64,
}

pub struct ViewerMetrics {
    window_start: Instant,
    published_at_window_start: u64,
    shown_in_window: u64,
    ready_to_take: DurationStats,
    ready_to_present: DurationStats,
    present_interval: DurationStats,
    last_present: Option<Instant>,
    last_sequence: Option<u64>,
    total_shown: u64,
    sequence_gaps: u64,
    not_shown: u64,
}

impl ViewerMetrics {
    pub fn new(now: Instant) -> Self {
        Self {
            window_start: now,
            published_at_window_start: 0,
            shown_in_window: 0,
            ready_to_take: DurationStats::default(),
            ready_to_present: DurationStats::default(),
            present_interval: DurationStats::default(),
            last_present: None,
            last_sequence: None,
            total_shown: 0,
            sequence_gaps: 0,
            not_shown: 0,
        }
    }

    fn track_sequence(&mut self, sequence: u64) {
        if let Some(last) = self.last_sequence
            && sequence > last
        {
            self.sequence_gaps += sequence - last - 1;
        }
        self.last_sequence = Some(sequence);
    }

    /// A new frame was taken from the mailbox and presented.
    pub fn record_shown(
        &mut self,
        sequence: u64,
        ready_at: Instant,
        taken_at: Instant,
        presented_at: Instant,
    ) {
        self.track_sequence(sequence);
        self.ready_to_take
            .record(taken_at.saturating_duration_since(ready_at));
        self.ready_to_present
            .record(presented_at.saturating_duration_since(ready_at));
        if let Some(last) = self.last_present {
            self.present_interval
                .record(presented_at.saturating_duration_since(last));
        }
        self.last_present = Some(presented_at);
        self.shown_in_window += 1;
        self.total_shown += 1;
    }

    /// A frame was taken from the mailbox but could not be presented.
    pub fn record_not_shown(&mut self, sequence: u64) {
        self.track_sequence(sequence);
        self.not_shown += 1;
        // The next present interval would span the gap; do not count it as
        // a pacing hitch.
        self.last_present = None;
    }

    /// Returns the current window's figures and starts a new window.
    pub fn snapshot(&mut self, now: Instant, mailbox: MailboxStats) -> Snapshot {
        let window = now.saturating_duration_since(self.window_start);
        let secs = window.as_secs_f64();
        let rate = |count: u64| if secs > 0.0 { count as f64 / secs } else { 0.0 };
        let snapshot = Snapshot {
            input_fps: rate(
                mailbox
                    .published
                    .saturating_sub(self.published_at_window_start),
            ),
            shown_fps: rate(self.shown_in_window),
            ready_to_take: self.ready_to_take,
            ready_to_present: self.ready_to_present,
            present_interval: self.present_interval,
            total_published: mailbox.published,
            total_shown: self.total_shown,
            dropped_mailbox: mailbox.replaced,
            // Each replaced frame also shows up as a sequence gap once a newer
            // frame is shown; whatever remains was never delivered.
            dropped_source: self.sequence_gaps.saturating_sub(mailbox.replaced),
            not_shown: self.not_shown,
        };
        self.window_start = now;
        self.published_at_window_start = mailbox.published;
        self.shown_in_window = 0;
        self.ready_to_take = DurationStats::default();
        self.ready_to_present = DurationStats::default();
        self.present_interval = DurationStats::default();
        snapshot
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ms(v: u64) -> Duration {
        Duration::from_millis(v)
    }

    #[test]
    fn duration_stats() {
        let mut s = DurationStats::default();
        assert_eq!(s.mean(), None);
        s.record(ms(4));
        s.record(ms(2));
        s.record(ms(6));
        assert_eq!(s.mean(), Some(ms(4)));
        assert_eq!(s.min(), Some(ms(2)));
        assert_eq!(s.max(), Some(ms(6)));
    }

    #[test]
    fn rates_and_latency_over_a_window() {
        let t0 = Instant::now();
        let mut m = ViewerMetrics::new(t0);
        for i in 0..60u64 {
            let ready = t0 + ms(i * 16);
            m.record_shown(i, ready, ready + ms(1), ready + ms(3));
        }
        let mailbox = MailboxStats {
            published: 60,
            taken: 60,
            replaced: 0,
            pending: false,
        };
        let s = m.snapshot(t0 + ms(1000), mailbox);
        assert!((s.input_fps - 60.0).abs() < 1e-9);
        assert!((s.shown_fps - 60.0).abs() < 1e-9);
        assert_eq!(s.ready_to_present.mean(), Some(ms(3)));
        assert_eq!(s.ready_to_take.max(), Some(ms(1)));
        assert_eq!(s.present_interval.min(), Some(ms(16)));
        assert_eq!(s.dropped_source, 0);

        // The next window starts from zero.
        let s2 = m.snapshot(t0 + ms(2000), mailbox);
        assert_eq!(s2.input_fps, 0.0);
        assert_eq!(s2.ready_to_present.mean(), None);
        assert_eq!(s2.total_shown, 60);
    }

    #[test]
    fn drops_are_attributed_to_mailbox_source_or_render() {
        let t0 = Instant::now();
        let mut m = ViewerMetrics::new(t0);
        // Shown: 0, 1, 4, 5, 9. Sequences 2 and 3 were replaced in the
        // mailbox, 6 was taken but not shown, 7 and 8 never arrived.
        for seq in [0, 1, 4, 5] {
            m.record_shown(seq, t0, t0, t0);
        }
        m.record_not_shown(6);
        m.record_shown(9, t0, t0, t0);
        let mailbox = MailboxStats {
            published: 8,
            taken: 6,
            replaced: 2,
            pending: false,
        };
        let s = m.snapshot(t0 + ms(100), mailbox);
        assert_eq!(s.dropped_mailbox, 2);
        assert_eq!(s.dropped_source, 2);
        assert_eq!(s.not_shown, 1);
        assert_eq!(s.total_shown, 5);
    }
}
