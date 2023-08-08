FROM ubuntu:23.04
WORKDIR /usr/src/ffickle
COPY . .
RUN apt-get update -y && apt-get upgrade -y && apt-get install pkg-config libssl-dev openssl gcc curl clang clang-16 llvm make cmake git ninja-build -y
RUN curl https://sh.rustup.rs -sSf > /tmp/rustup-init.sh \
    && chmod +x /tmp/rustup-init.sh \
    && sh /tmp/rustup-init.sh -y \
    && rm -rf /tmp/rustup-init.sh
ENV PATH="$PATH:~/.cargo/bin"
RUN ~/.cargo/bin/rustup install nightly
RUN ~/.cargo/bin/rustup uninstall stable
RUN git submodule update --init ./rust
RUN (cd rust && git submodule update --init ./src/llvm-project)
RUN (cd rust && git submodule update --init ./src/inkwell)
RUN (cd rust && git submodule update --init ./src/llvm-sys)
ENV LLVM_SYS_160_PREFIX=/usr/src/rust/build/host/llvm/
RUN (cd rust && ./x.py build)
RUN (cd rust && ./x.py install)
RUN ~/.cargo/bin/rustup toolchain link miri-custom /usr/src/ffickle/rust/build/host/stage2/
RUN ~/.cargo/bin/rustup default miri-custom
RUN LLVM_SYS_160_PREFIX=${LLVM_SYS_160_PREFIX} (cd rust && ./x.py build miri)
RUN LLVM_SYS_160_PREFIX=${LLVM_SYS_160_PREFIX} (cd rust && ./x.py install miri)
RUN ~/.cargo/bin/cargo search
RUN ~/.cargo/bin/cargo install cargo-download cargo-dylint dylint-link
RUN (cd src/early && ~/.cargo/bin/cargo build)
RUN (cd src/late && ~/.cargo/bin/cargo build)
ENV DYLINT_LIBRARY_PATH="/usr/src/ffickle/src/early/target/debug/:/usr/src/ffickle/src/late/target/debug/"
ENV CC="clang --save-temps=obj"
