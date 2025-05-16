use core::alloc::{GlobalAlloc, Layout};
use core::ptr::null_mut;
use core::sync::atomic::{AtomicUsize, Ordering};

pub struct BumpAllocator {
    heap_start: usize,
    heap_end: usize,
    next: AtomicUsize,
}

impl BumpAllocator {
    pub const fn new(heap_start: usize, heap_end: usize) -> Self {
        Self {
            heap_start,
            heap_end,
            next: AtomicUsize::new(heap_start),
        }
    }

    pub unsafe fn init(&self) {
        self.next.store(self.heap_start, Ordering::SeqCst);
    }
}

unsafe impl GlobalAlloc for BumpAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let current = self.next.load(Ordering::SeqCst);
        let alloc_start = (current + layout.align() - 1) & !(layout.align() - 1);
        let alloc_end = alloc_start.checked_add(layout.size()).unwrap();

        if alloc_end > self.heap_end {
            return null_mut(); // Out of memory
        }

        self.next.store(alloc_end, Ordering::SeqCst);
        alloc_start as *mut u8
    }

    unsafe fn dealloc(&self, _ptr: *mut u8, _layout: Layout) {}
}
