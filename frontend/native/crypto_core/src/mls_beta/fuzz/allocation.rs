//! Per-thread allocation accounting for the fuzz harness.
//!
//! Unbounded allocation is one of the defect classes the beta MLS decoders
//! must not have, and a length-prefix-driven reservation is invisible to a
//! panic hook. The harness therefore installs a counting global allocator in
//! the test binary only: `mls_beta` is behind `beta-pq-mls` and this module is
//! behind `cfg(test)`, so no shipped artifact ever links it.
//!
//! Counters are thread-local and const-initialized, so the allocator hook
//! neither allocates nor registers a destructor and cannot recurse. Parallel
//! test threads keep independent counters, and a cross-thread free saturates
//! at zero instead of underflowing.

use std::{
    alloc::{GlobalAlloc, Layout, System},
    cell::Cell,
};

thread_local! {
    static LIVE: Cell<usize> = const { Cell::new(0) };
    static PEAK: Cell<usize> = const { Cell::new(0) };
    static LARGEST: Cell<usize> = const { Cell::new(0) };
}

struct TrackingAllocator;

impl TrackingAllocator {
    fn record(size: usize) {
        let _ = LARGEST.try_with(|largest| largest.set(largest.get().max(size)));
        let _ = LIVE.try_with(|live| {
            let now = live.get().saturating_add(size);
            live.set(now);
            let _ = PEAK.try_with(|peak| peak.set(peak.get().max(now)));
        });
    }

    fn release(size: usize) {
        let _ = LIVE.try_with(|live| live.set(live.get().saturating_sub(size)));
    }
}

// SAFETY: every method forwards to `System` unchanged and only adds
// arithmetic on thread-local counters, so this allocator's contract is
// exactly the system allocator's.
unsafe impl GlobalAlloc for TrackingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        // SAFETY: forwarded caller contract.
        let pointer = unsafe { System.alloc(layout) };
        if !pointer.is_null() {
            Self::record(layout.size());
        }
        pointer
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        // SAFETY: forwarded caller contract.
        let pointer = unsafe { System.alloc_zeroed(layout) };
        if !pointer.is_null() {
            Self::record(layout.size());
        }
        pointer
    }

    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        Self::release(layout.size());
        // SAFETY: forwarded caller contract.
        unsafe { System.dealloc(pointer, layout) }
    }

    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        // SAFETY: forwarded caller contract.
        let moved = unsafe { System.realloc(pointer, layout, new_size) };
        if !moved.is_null() {
            Self::release(layout.size());
            Self::record(new_size);
        }
        moved
    }
}

#[global_allocator]
static TRACKING_ALLOCATOR: TrackingAllocator = TrackingAllocator;

/// What one measured body allocated.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(crate) struct AllocationReport {
    /// How far live bytes rose above where they started.
    pub(crate) peak_growth: usize,
    /// The largest single request, which is what a hostile length prefix
    /// drives directly.
    pub(crate) largest_single: usize,
}

/// Runs `body`, reporting what it allocated on this thread.
pub(crate) fn measure<R>(body: impl FnOnce() -> R) -> (R, AllocationReport) {
    let base = LIVE.with(Cell::get);
    PEAK.with(|peak| peak.set(base));
    LARGEST.with(|largest| largest.set(0));
    let value = body();
    let report = AllocationReport {
        peak_growth: PEAK.with(Cell::get).saturating_sub(base),
        largest_single: LARGEST.with(Cell::get),
    };
    (value, report)
}

#[cfg(test)]
mod tests {
    use super::measure;

    #[test]
    fn measurement_sees_a_large_reservation() {
        const REQUEST: usize = 8 * 1024 * 1024;
        let (length, report) = measure(|| {
            let buffer = vec![0_u8; REQUEST];
            buffer.len()
        });
        assert_eq!(length, REQUEST);
        assert!(report.largest_single >= REQUEST, "{report:?}");
        assert!(report.peak_growth >= REQUEST, "{report:?}");
    }

    #[test]
    fn measurement_without_allocation_reports_no_growth() {
        let ((), report) = measure(|| {});
        assert_eq!(report.peak_growth, 0, "{report:?}");
    }
}
