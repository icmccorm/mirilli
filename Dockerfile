FROM ubuntu:23.04 as setup

WORKDIR /usr/src/ffickle
COPY . .
RUN apt-get update -y && apt-get upgrade -y && apt-get install pkg-config libssl-dev openssl gcc curl clang-16 llvm-16 make cmake git ninja-build vim -y
RUN curl https://sh.rustup.rs -sSf > /tmp/rustup-init.sh \
    && chmod +x /tmp/rustup-init.sh \
    && sh /tmp/rustup-init.sh -y \
    && rm -rf /tmp/rustup-init.sh
ENV PATH="/root/.cargo/bin:${PATH}"
ENV NIGHTLY="nightly-2023-09-07"
RUN rustup install ${NIGHTLY}
RUN rustup default ${NIGHTLY}
RUN rustup install nightly
RUN git submodule update --init ./rust

FROM setup as rust-compile
WORKDIR /usr/src/ffickle/rust
RUN git submodule update --init ./src/llvm-project
RUN git submodule update --init ./src/inkwell
RUN git submodule update --init ./src/llvm-sys
ENV LLVM_SYS_170_PREFIX=/usr/src/ffickle/rust/build/host/llvm/
RUN LLVM_SYS_170_PREFIX=${LLVM_SYS_170_PREFIX} ./x.py build && ./x.py install
RUN rustup toolchain link miri-custom /usr/src/ffickle/rust/build/host/stage2/
RUN rustup default miri-custom

FROM rust-compile as miri-compile
WORKDIR /usr/src/ffickle/rust
RUN LLVM_SYS_170_PREFIX=${LLVM_SYS_170_PREFIX} ./x.py build miri && ./x.py install miri
RUN cargo miri setup

FROM miri-compile as ffickle-compile
WORKDIR /usr/src/ffickle/
RUN cargo search
RUN cargo install cargo-download cargo-dylint dylint-link
RUN (rm -rf src/early/target/)
RUN (rm -rf src/late/target/)
RUN (cd src/early && cargo build)
RUN (cd src/late && cargo build)
ENV DYLINT_LIBRARY_PATH="/usr/src/ffickle/src/early/target/debug/:/usr/src/ffickle/src/late/target/debug/"
ENV CC="clang -g -O0 --save-temps=obj"
