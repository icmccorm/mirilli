use std::{alloc::Layout, cell::UnsafeCell};

#[repr(C)]
struct Alloc {
    cache: i32,
    buffer: *mut i32,
}
impl Default for Alloc {
    fn default() -> Self {
        Self {
            cache: 0,
            buffer: std::ptr::null_mut(),
        }
    }
}

fn open(a: &mut Alloc) -> i32 { 
    let cache = &mut a.cache as *mut _;
    a.buffer = cache;
    let b = &mut *a;
    unsafe {
        open_f(b.buffer);
        b.cache
    }
}

unsafe fn open_f(a: *mut i32) {
    *a = 1;
}

fn main() {
    let mut a = Alloc::default();
    let ra = &mut a;
    open(ra);    
}