#![feature(rustc_private)]
extern crate rustc_target;
extern crate rustc_span;
extern crate rustc_session;
use rustc_target::spec::abi::Abi as SpecAbi;
use rustc_span::Span;
use rustc_session::Session;

pub fn is_internal_abi(abi: SpecAbi) -> bool {
    matches!(
        abi,
        SpecAbi::Rust | SpecAbi::RustCall | SpecAbi::RustIntrinsic | SpecAbi::PlatformIntrinsic
    )
}


pub fn span_to_string(sp: Span, sess: &Session) -> String {
    let parse_sess = &sess.parse_sess;
    let source_map = &(*parse_sess).source_map();
    source_map.span_to_diagnostic_string(sp)
}