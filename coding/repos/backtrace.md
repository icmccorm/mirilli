
`src/symbolize/gimli/libs_libnx.rs`
* Use of `extern` to access foreign static variable, within a function.
* Use of unsafe to case from a static item to a raw ptr


`src/symbolize/gimli/libs_illumos.rs`
* INIT_MEM_ZEROED - for struct LinkMap
* FN_LOAD_STATE - for struct LinkMap
* LIBC_VOID_PTR - multistage cast for `(&mut map) as *mut *const LinkMap as *mut libc::c_void`

`/Users/icmccorm/git/ffickle/coding/repos/backtrace/src/print/fuchsia.rs`
* ALLOW_IMPROPER_CTYPES
* RECODE - mutual callback observed between external function and foreign function, where foreign function exists to iterate over external items of some form, while taking a visitor struct that is modified by an external function. Sort of RETURN_OUT_PTR, but not quite, since we're dealing with Rust memory.

