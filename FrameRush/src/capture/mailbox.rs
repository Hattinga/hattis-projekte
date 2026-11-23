//! Single-slot "latest frame wins" mailbox between the capture thread and the
//! renderer.
//!
//! The mailbox never holds more than one item. Publishing while an item is
//! still waiting replaces (drops) the stale one, so a slow consumer can never
//! build up latency. This is the only buffer between capture and render.
//!
//! # Wake-up contract
//!
//! [`Mailbox::publish`] reports [`PublishOutcome::Stored`] exactly when the
//! slot went from empty to full. Only then must the producer wake the
//! consumer. As long as the consumer calls [`Mailbox::take`] **only** in
//! response to such a wake (once per wake), at most one wake-up is ever in
//! flight, so the wake channel (e.g. winit's event-loop proxy, which is
//! unbounded internally) cannot accumulate a backlog either. Every wake
//! finds an item, because nobody else empties the slot.

use std::sync::{Mutex, MutexGuard, PoisonError};

/// What happened to a published item.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PublishOutcome {
    /// The slot was empty. The consumer has not been told about a pending
    /// item yet and must be woken.
    Stored,
    /// An item the consumer had not taken yet was replaced and dropped. A
    /// wake-up for the slot is already outstanding; do not send another.
    Replaced,
}

impl PublishOutcome {
    /// Whether the producer has to wake the consumer.
    pub fn needs_wake(self) -> bool {
        matches!(self, Self::Stored)
    }
}

/// Counters since the mailbox was created.
///
/// Invariant: `published == taken + replaced + pending`, where `pending` is 1
/// while an item waits in the slot and 0 otherwise.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct MailboxStats {
    pub published: u64,
    pub taken: u64,
    /// Items dropped because a newer one arrived before the consumer took
    /// them.
    pub replaced: u64,
    pub pending: bool,
}

struct Inner<T> {
    slot: Option<T>,
    published: u64,
    taken: u64,
    replaced: u64,
}

/// A bounded (capacity 1) latest-value handoff. See the module docs.
pub struct Mailbox<T> {
    inner: Mutex<Inner<T>>,
}

impl<T> Default for Mailbox<T> {
    fn default() -> Self {
        Self::new()
    }
}

impl<T> Mailbox<T> {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(Inner {
                slot: None,
                published: 0,
                taken: 0,
                replaced: 0,
            }),
        }
    }

    /// Puts `item` into the slot, replacing any item still waiting there.
    ///
    /// Never blocks beyond a short critical section. A replaced item is
    /// dropped after the lock is released, so freeing a large frame buffer
    /// never stalls the consumer.
    pub fn publish(&self, item: T) -> PublishOutcome {
        let stale = {
            let mut inner = self.lock();
            inner.published += 1;
            let stale = inner.slot.replace(item);
            if stale.is_some() {
                inner.replaced += 1;
            }
            stale
        };
        match stale {
            Some(stale) => {
                drop(stale);
                PublishOutcome::Replaced
            }
            None => PublishOutcome::Stored,
        }
    }

    /// Takes the newest item, leaving the slot empty.
    pub fn take(&self) -> Option<T> {
        let mut inner = self.lock();
        let item = inner.slot.take();
        if item.is_some() {
            inner.taken += 1;
        }
        item
    }

    pub fn stats(&self) -> MailboxStats {
        let inner = self.lock();
        MailboxStats {
            published: inner.published,
            taken: inner.taken,
            replaced: inner.replaced,
            pending: inner.slot.is_some(),
        }
    }

    fn lock(&self) -> MutexGuard<'_, Inner<T>> {
        // The protected state is a plain Option plus counters; it is always
        // consistent between statements, so a panic elsewhere cannot leave it
        // half-updated. Recover instead of propagating the poison.
        self.inner.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::mpsc;
    use std::thread;

    #[test]
    fn empty_mailbox_yields_nothing() {
        let mailbox = Mailbox::<u32>::new();
        assert_eq!(mailbox.take(), None);
        assert_eq!(mailbox.stats(), MailboxStats::default());
    }

    #[test]
    fn take_returns_the_published_item_once() {
        let mailbox = Mailbox::new();
        assert_eq!(mailbox.publish(1), PublishOutcome::Stored);
        assert_eq!(mailbox.take(), Some(1));
        assert_eq!(mailbox.take(), None);
    }

    #[test]
    fn newer_item_replaces_unconsumed_one() {
        let mailbox = Mailbox::new();
        assert_eq!(mailbox.publish(1), PublishOutcome::Stored);
        assert_eq!(mailbox.publish(2), PublishOutcome::Replaced);
        assert_eq!(mailbox.publish(3), PublishOutcome::Replaced);
        assert_eq!(mailbox.take(), Some(3), "consumer must see the newest item");
        assert_eq!(mailbox.take(), None, "stale items must not be queued");
        let stats = mailbox.stats();
        assert_eq!(stats.published, 3);
        assert_eq!(stats.taken, 1);
        assert_eq!(stats.replaced, 2);
        assert!(!stats.pending);
    }

    #[test]
    fn only_empty_to_full_transition_requests_a_wake() {
        let mailbox = Mailbox::new();
        assert!(mailbox.publish(1).needs_wake());
        assert!(!mailbox.publish(2).needs_wake());
        assert!(!mailbox.publish(3).needs_wake());
        mailbox.take();
        assert!(mailbox.publish(4).needs_wake());
    }

    #[test]
    fn stats_track_pending_item() {
        let mailbox = Mailbox::new();
        mailbox.publish(1);
        assert!(mailbox.stats().pending);
        mailbox.take();
        assert!(!mailbox.stats().pending);
    }

    /// Counts live instances so the test can prove that replaced items are
    /// actually freed, i.e. memory stays bounded.
    struct Tracked(Arc<AtomicUsize>);
    impl Tracked {
        fn new(live: &Arc<AtomicUsize>) -> Self {
            live.fetch_add(1, Ordering::SeqCst);
            Self(Arc::clone(live))
        }
    }
    impl Drop for Tracked {
        fn drop(&mut self) {
            self.0.fetch_sub(1, Ordering::SeqCst);
        }
    }

    #[test]
    fn at_most_one_item_is_alive_without_a_consumer() {
        let live = Arc::new(AtomicUsize::new(0));
        let mailbox = Mailbox::new();
        for _ in 0..1000 {
            mailbox.publish(Tracked::new(&live));
            assert!(live.load(Ordering::SeqCst) <= 1);
        }
        assert_eq!(live.load(Ordering::SeqCst), 1);
        drop(mailbox.take());
        assert_eq!(live.load(Ordering::SeqCst), 0);
    }

    /// Producer and consumer on different threads, with the wake path modelled
    /// as a channel of capacity 1. If the wake contract were violated (two
    /// wakes in flight), `try_send` would fail with `Full`.
    #[test]
    fn concurrent_handoff_keeps_order_and_bounds_wakes() {
        const ITEMS: u64 = 50_000;
        let mailbox = Arc::new(Mailbox::new());
        let (wake_tx, wake_rx) = mpsc::sync_channel::<()>(1);

        let producer = {
            let mailbox = Arc::clone(&mailbox);
            thread::spawn(move || {
                for seq in 0..ITEMS {
                    if mailbox.publish(seq).needs_wake() {
                        wake_tx
                            .try_send(())
                            .expect("more than one wake-up in flight");
                    }
                }
            })
        };

        let mut last: Option<u64> = None;
        let mut received = 0u64;
        while last != Some(ITEMS - 1) {
            wake_rx
                .recv()
                .expect("producer hung up before the last item");
            let seq = mailbox.take().expect("a wake-up must always find an item");
            if let Some(prev) = last {
                assert!(seq > prev, "went backwards: {prev} -> {seq}");
            }
            last = Some(seq);
            received += 1;
        }
        producer.join().unwrap();

        let stats = mailbox.stats();
        assert_eq!(stats.published, ITEMS);
        assert_eq!(stats.taken, received);
        assert_eq!(stats.taken + stats.replaced, ITEMS);
        assert!(!stats.pending);
        assert!(wake_rx.try_recv().is_err(), "no stray wake-up may remain");
    }
}
