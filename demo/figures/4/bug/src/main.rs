pub struct Compression {
    pub parent: Box<Stream>,
}

impl Compression {
    fn new() -> Self {
        let mut parent = Box::new(Stream::default());
        unsafe { init(parent.as_mut()) }
        Compression { parent }
    }

    fn mutate(&mut self) {
        self.parent.data = 0;
        Miri::tree(self.parent.as_mut() as *mut Stream as *mut u8, true);
        unsafe { mutate(self.parent.as_mut()) }
    }
}

unsafe fn init(p: *mut Stream) {
    *p.child = std::alloc::alloc(Layout::new::<State>()) as *mut State;
    (*(*p).child).parent = p;
}

unsafe fn mutate(p: *mut Stream) {
    let _x = (*(*(*p).child).parent).data;
}

#[repr(C)]
pub struct State {
    pub parent: *mut Stream,
}

#[repr(C)]
pub struct Stream {
    pub data: i32,
    pub child: *mut State,
}

impl Default for Stream {
    fn default() -> Self {
        Self {
            data: 0,
            child: std::ptr::null_mut(),
        }
    }
}
