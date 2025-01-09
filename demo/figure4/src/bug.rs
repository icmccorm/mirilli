use crate::ffi::*;

struct Compression {
    pub stream: Box<Stream>,
}

impl Compression {
    fn new() -> Self {
        let mut stream = Box::new(Stream::default());
        unsafe { init(stream.as_mut()) }
        Compression { stream }
    }

    fn mutate(&mut self) {
        self.stream.data = 0;
        unsafe { compress(self.stream.as_mut()) }
    }
}


impl Drop for Compression {
    fn drop(&mut self) {
        unsafe { 
            drop_stream(self.stream.as_mut()); 
        }   
    }
}

pub fn exec() {
    let mut comp = Compression::new();
    comp.mutate();
}
