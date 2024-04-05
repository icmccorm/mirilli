# A Study of Undefined Behavior Across Foreign Function Boundaries in Rust Libraries

This repository is the replication package for the publication ``A Study of Undefined Behavior Across Foreign Function Boundaries in Rust Libraries''. 
It contains the implementation of MiriLLI, which is an extension to Miri that allows it to execute foreign functions by interpreting LLVM bitcode. We use [LLI](https://llvm.org/docs/CommandGuide/lli.html): an LLVM interpreter included within the LLVM toolchain. 

If you have Docker, you can build an image with `docker build .` that has our custom Rust toolchain set as the global default with MiriLLI installed. Alternatively, you can clone the [rust](https://github.com/icmccorm/mirilli-rust) submodule and [follow the steps](https://rustc-dev-guide.rust-lang.org/building/how-to-build-and-run.html) for building the Rust toolchain and Miri from source. 

##  Configuration

To be able to call foreign functions, MiriLLI needs access to the LLVM bitcode of the foreign library. Clang will produce LLVM bitcode files during compilation if you pass the flag `--save-temps=obj`. In our Docker image, we override the global C and C++ compilers to use these flags by default: This ensures that bitcode files will be produced and stored in the `target` directory when building a crate that statically links against C or C++ code. Alternatively, you can compile a foreign library separately, assemble its files into a single module with [llvm-as](https://llvm.org/docs/CommandGuide/llvm-as.html) and place it in the directory where you invoke Miri. MiriLLI recursively searches for all bitcode files in the directory where it is invoked, so running it is the same as running an unmodified version of Miri (e.g. `cargo miri test`).

we implemented several configuration flags that change the behavior of MiriLLI. Each of these can be provided through the `MIRIFLAGS` environment variable.

* `-Zmiri-extern-bc-file=[filename.bc]` searches for the indicated LLVM bitcode file and uses it as the single source of foreign function definitions. Any other bitcode files present in the root directory will be ignored.

* `-Zmiri-llvm-read-uninit` allows reading uninitialized memory in LLVM

* `-Zmiri-llvm-zero-all` zero-initializes all static, stack, and heap memory in LLVM. 

* `-Zmiri-llvm-disable-alignment-check` disables alignment checking in LLVM.

* `-Zmiri-llvm-alignment-check-rust-only` disables alignment checking in LLVM unless the memory being accessed has been allocated by Rust.

## Implementation
We rely on the following additional dependencies to implement our integration with LLI:
* [llvm-sys](https://crates.io/crates/llvm-sys)
* [inkwell](https://crates.io/crates/inkwell)

## Coauthors
* [Joshua Sunshine](https://www.cs.cmu.edu/~jssunshi/)
* [Jonathan Aldrich](https://www.cs.cmu.edu/~aldrich/)

## Contributors
* [Tomas Dougan](https://github.com/taurreco)
