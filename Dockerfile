FROM ubuntu:23.04
WORKDIR /usr/src/ffickle
COPY . .
RUN apt-get update -y && apt-get upgrade -y && apt-get install pkg-config libssl-dev openssl gcc curl clang llvm make cmake -y
RUN curl https://sh.rustup.rs -sSf > /tmp/rustup-init.sh \
    && chmod +x /tmp/rustup-init.sh \
    && sh /tmp/rustup-init.sh -y \
    && rm -rf /tmp/rustup-init.sh
ENV PATH "$PATH:~/.cargo/bin"
ENV DEFAULT_TOOLCHAIN "nightly-2023-07-14"
RUN ~/.cargo/bin/rustup install $DEFAULT_TOOLCHAIN
RUN ~/.cargo/bin/rustup default $DEFAULT_TOOLCHAIN
RUN ~/.cargo/bin/cargo search
RUN ~/.cargo/bin/cargo install cargo-download cargo-dylint dylint-link
RUN ~/.cargo/bin/rustup +$DEFAULT_TOOLCHAIN component add miri 
RUN (cd src/early && ~/.cargo/bin/cargo build)
RUN (cd src/late && ~/.cargo/bin/cargo build)
ENV DYLINT_LIBRARY_PATH="/usr/src/ffickle/src/early/target/debug/:/usr/src/ffickle/src/late/target/debug/"
ENV CC="clang --save-temps=obj"