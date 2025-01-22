use crate::ffi::*;

pub struct Compression {
    pub stream: *mut Stream,
}

impl Compression {
  
    fn new() -> Self {
        let stream = Box::new(Stream::default());
        let stream = Box::into_raw(stream);
        unsafe { init(stream) }
        Compression { stream }
    }

    fn mutate(&mut self) {
        unsafe {
            (*self.stream).data = 0;
            compress(self.stream)
        }
    }
}

pub fn exec() {
    let mut comp = Compression::new();
    comp.mutate();
}
