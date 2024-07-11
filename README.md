# A Study of Undefined Behavior Across Foreign Function Boundaries in Rust Libraries

This repository is the replication package for the publication ``A Study of Undefined Behavior Across Foreign Function Boundaries in Rust Libraries''. 
It contains the implementation of MiriLLI, which is an extension to Miri that allows it to execute foreign functions by interpreting LLVM bitcode. We use [LLI](https://llvm.org/docs/CommandGuide/lli.html): an LLVM interpreter included within the LLVM toolchain. 

## Setup
Our Dockerfile builds an image with our custom Rust toolchain set as the global default with MiriLLI installed. You can build it using the following command:
```
docker build . -t [name]
``` 
To launch our image with a shell, execute the following command:
```
docker run -it [name] /bin/bash
```
Otherwise, if you are building from source, ensure all submodules are initialized using:
```
git submodule update --init 
```
Then, enter the `mirilli-rust` submodule and [follow the steps](https://rustc-dev-guide.rust-lang.org/building/how-to-build-and-run.html) from the Rust project for building the Rust toolchain and Miri from source. 

To build our dataset, follow the instructions in [DATASET.md](https://github.com/icmccorm/mirilli/blob/main/DATASET.md).

##  Configuration
To be able to call foreign functions, MiriLLI needs access to the LLVM bitcode of the foreign library. Clang will produce LLVM bitcode files during compilation if you pass the flag `--save-temps=obj`. In our Docker image, we override the global C and C++ compilers to use these flags by default: This ensures that bitcode files will be produced and stored in the `target` directory when building a crate that statically links against C or C++ code. Alternatively, you can compile a foreign library separately, assemble its files into a single module with [llvm-as](https://llvm.org/docs/CommandGuide/llvm-as.html) and place it in the directory where you invoke Miri. MiriLLI recursively searches for all bitcode files in the directory where it is invoked, so running it is the same as running an unmodified version of Miri (e.g. `cargo miri test`).

We implemented several configuration flags that change the behavior of MiriLLI. Each of these can be provided through the `MIRIFLAGS` environment variable. By default, LLVM is allowed to read uninitialized and unaligned memory.

* `-Zmiri-extern-bc-file=[filename.bc]` searches for the indicated LLVM bitcode file and uses it as the single source of foreign function definitions. Any other bitcode files present in the root directory will be ignored.

* `-Zmiri-llvm-memory-zeroed` zero-initializes all static, stack, and heap memory in LLVM. 

* `-Zmiri-llvm-enable-alignment-check-all` checks all memory accesses in LLVM for alignment.

* `-Zmiri-llvm-enable-alignment-check-rust` checks only memory accesses to Rust-allocated memory for alignment in LLVM.

## Implementation
We rely on forks of the following crates to implement our integration with LLI:
* [llvm-sys](https://crates.io/crates/llvm-sys)
* [inkwell](https://github.com/icmccorm/inkwell)