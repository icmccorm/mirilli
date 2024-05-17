FROM ubuntu:23.04 as setup

WORKDIR /usr/src/mirilli
COPY . .
RUN apt-get update -y && apt-get upgrade -y && apt-get install pkg-config libssl-dev openssl gcc curl clang llvm clang-18 llvm-18 make cmake git ninja-build cloc vim -y
RUN curl https://sh.rustup.rs -sSf > /tmp/rustup-init.sh \
    && chmod +x /tmp/rustup-init.sh \
    && sh /tmp/rustup-init.sh -y \
    && rm -rf /tmp/rustup-init.sh
ENV PATH="/root/.cargo/bin:${PATH}"
ENV NIGHTLY="nightly-2023-09-25"
ENV CC="clang-18 -g -O0 --save-temps=obj"
ENV CXX="clang++-18 -g -O0 --save-temps=obj"
RUN rustup install ${NIGHTLY}
RUN rustup default ${NIGHTLY}
RUN rustup component add miri
RUN rustup component add rust-src
RUN rustup install nightly
RUN git submodule update --init ./mirilli-rust

FROM setup as libcxx-compile
WORKDIR /usr/src/mirilli/mirilli-rust/src/llvm-project/
RUN mkdir build-libcxx
RUN cmake -G Ninja -S runtimes -B build-libcxx -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" -DCMAKE_C_COMPILER=clang-18 -DCMAKE_CXX_COMPILER=clang++-18 -DLIBCXX_ADDITIONAL_COMPILE_FLAGS="--save-temps;-fno-threadsafe-statics;--stdlib=libc++" -DLIBCXX_ENABLE_THREADS="OFF" -DLIBCXXABI_ENABLE_THREADS="OFF" -DLIBUNWIND_ENABLE_THREADS="OFF" -DLLVM_ENABLE_THREADS="OFF" -DLIBCXX_ENABLE_STATIC="ON" 
RUN ninja -C build-libcxx cxx cxxabi unwind

FROM libcxx-compile as rust-compile
WORKDIR /usr/src/mirilli/mirilli-rust
RUN git submodule update --init ./src/llvm-project
RUN git submodule update --init ./src/inkwell
RUN git submodule update --init ./src/llvm-sys
ENV LLVM_SYS_181_PREFIX=/usr/src/mirilli/mirilli-rust/build/host/llvm/
RUN LLVM_SYS_181_PREFIX=${LLVM_SYS_181_PREFIX} ./x.py build && ./x.py install
RUN rustup toolchain link mirilli /usr/src/mirilli/mirilli-rust/build/host/stage2/
RUN rustup default mirilli

FROM rust-compile as miri-compile
WORKDIR /usr/src/mirilli/mirilli-rust
RUN LLVM_SYS_181_PREFIX=${LLVM_SYS_181_PREFIX} ./x.py build miri
RUN LLVM_SYS_181_PREFIX=${LLVM_SYS_181_PREFIX} ./x.py install miri
RUN cargo miri setup

FROM miri-compile as rllvm-as-compile
WORKDIR /usr/src/mirilli/rllvm-as
RUN git submodule update --init ./inkwell
RUN git submodule update --init ./llvm-sys
RUN LLVM_SYS_181_PREFIX=${LLVM_SYS_181_PREFIX} cargo build --release
ENV PATH="/usr/src/mirilli/rllvm-as/target/release:${PATH}"
RUN ../scripts/misc/remove.sh /usr/src/mirilli/mirilli-rust/src/llvm-project/build-libcxx ../scripts/misc/exclude_libcxx.txt
RUN cd ../mirilli-rust/src/llvm-project/build-libcxx && rllvm-as /usr/src/mirilli/libcxx.bc

FROM rllvm-as-compile as final
WORKDIR /usr/src/mirilli
RUN cargo install cargo-download
