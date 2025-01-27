#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct State {
    pub parent: *mut Stream,
}

#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct Stream {
    pub data: ::std::os::raw::c_int,
    pub child: *mut State,
}

extern "C" {
    pub fn init(stream: *mut Stream);
}
extern "C" {
    pub fn compress(stream: *mut Stream);
}
extern "C" {
    pub fn drop_stream(stream: *mut Stream);
}

impl Default for Stream {
    fn default() -> Self {
        Self {
            data: 0,
            child: std::ptr::null_mut(),
        }
    }
}
