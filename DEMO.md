Follow these instructions to replicate one of the aliasing violations we detected in our study.

1. Execute the following command to download the version of the library bzip2 where we located a Tree Borrows violation.
```
./scripts/misc/cargo-download bzip2 0.4.4 && cd extracted
```
This will enter into a new directory containing the contents of the library. 

2. Execute the following command
```
MIRIFLAGS='-Zmiri-llvm-read-uninit -Zmiri-tree-borrows' cargo miri test -- bufread::tests::bug_61
```

3. Confirm that you see the following result:
```
---- Foreign Error Trace ----

@ %250 = load i32, ptr %249, align 8, !dbg !379

.../decompress.c:197:178
.../bzlib.c:842:20
src/mem.rs:232:19: 232:62
-----------------------------

error: Undefined Behavior: read access through <100475> is forbidden
    |
    = note: read access through <100475> is forbidden
    = note: (no span available)
    = help: this indicates a potential bug in the program: it performed an invalid operation, but the Tree Borrows rules it violated are still experimental
    = help: the accessed tag <100475> has state Disabled which forbids this child read access
help: the accessed tag <100475> was created here, in the initial state Reserved
   --> src/mem.rs:215:50
    |
215 |             assert_eq!(ffi::BZ2_bzDecompressInit(&mut *raw, 0, small as c_int), 0);
    |                                                  ^^^^^^^^^
help: the accessed tag <100475> later transitioned to Disabled due to a foreign write access at offsets [0x8..0xc]
   --> src/mem.rs:228:9
    |
228 |         self.inner.raw.avail_in = input.len().min(c_uint::MAX as usize) as c_uint;
    |         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    = help: this transition corresponds to a loss of read and write permissions
```