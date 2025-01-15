# MiriLLI - Usage
Here, we describe how to install and use MiriLLI. We also provide a guide to the extensions that we made to the Rust compiler, which will be useful if you want to extend or update this tool.

## Installation
We recommend using MiriLLI by building our Docker image. With Docker installed, execute the following command to build our image:
```
docker build . -t mirilli
```
Then, to launch a shell within the image, execute:
```
docker run mirilli -it /bin/bash
```
Alternatively, you can build MiriLLI from source. The Rust Compiler Development Guide provides [comprehensive documentation](https://rustc-dev-guide.rust-lang.org/building/how-to-build-and-run.html) on how to build the Rust compiler. 

You can also follow these steps. From the root folder of this repository, execute:
```
git submodule update --init mirilli-rust
cd mirilli-rust 
./x.py build
rustup toolchain link mirilli ./build/host/stage2
```
You can switch to the , switch to the `mirilli` toolchain using:
```
rustup default mirilli
```
This will include `miri`, which can be setup using
```
cargo miri setup
```
## Extensions
Aside from additional FFI support, MiriLLI is near-identical to an unmodified version of Miri. If you have never used Miri before, please review its original README file before using MiriLLI.
This can be found within our fork of the Rust compiler in the directory `src/tools/miri`. Alternatively, you can consult [the latest version](https://github.com/rust-lang/miri) of the README upstream.

MiriLLI needs access to the LLVM bitcode of foreign libraries to be able to call foreign functions. Clang will produce LLVM bitcode files during compilation if you pass the flag `--save-temps=obj`. In our Docker image, we override the global C and C++ compilers to use these flags by default. This ensures that bitcode files will be produced and stored in the target directory when building a crate that statically links against C or C++ code. Alternatively, you can compile a foreign library separately, assemble its files into a single module with `llvm-as` and place it in the directory where you invoke Miri. MiriLLI recursively searches for all bitcode files in the directory where it is invoked, so running it is the same as running an unmodified version of Miri (e.g. `cargo miri test`).

We implemented several configuration flags that change the behavior of MiriLLI. Each of these can be provided through the `MIRIFLAGS` environment variable. By default, LLVM is allowed to read uninitialized and unaligned memory.

* `-Zmiri-extern-bc-file=[filename.bc]` -  searches for the indicated LLVM bitcode file and uses it as the single source of foreign function definitions. Any other bitcode files present in the root directory will be ignored.

* `-Zmiri-llvm-memory-zeroed` - zero-initializes all static, stack, and heap memory in LLVM.

* `-Zmiri-llvm-enable-alignment-check-all` - checks all memory accesses in LLVM for alignment.

* `-Zmiri-llvm-enable-alignment-check-rust` - checks only memory accesses to Rust-allocated memory for alignment in LLVM.

## Implementation

As a prerequisite for this section, please review Section III of our paper, which provides a high-level overview of our architecture. The implementation of MiriLLI involved three key areas of the Rust toolchain. The first area was in Miri itself———we needed to implement a value conversion layer to convert arguments of type GenericValue 