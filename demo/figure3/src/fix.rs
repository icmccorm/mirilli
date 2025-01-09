use std::cell::UnsafeCell;
use crate::ffi;

struct Alloc {
    cache: UnsafeCell<i32>,
    buffer: *mut i32,
}

impl Default for Alloc {
    fn default() -> Self {
        Self {
            cache: 0.into(),
            buffer: std::ptr::null_mut(),
        }
    }
}

fn open(a: &mut Alloc) -> i32 { 
    let cache = a.cache.get();
    a.buffer = cache;
    let b = &mut *a;
    unsafe {
        ffi::open_f(b.buffer);
        *b.cache.get()
    }
}

pub fn exec() {
    let mut a = Alloc::default();
    let _ = open(&mut a);
}
