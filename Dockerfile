FROM ubuntu:22.04.1
WORKDIR /usr/src/ffickle
COPY . .
RUN apt-get update -y && apt-get upgrade -y && apt-get install pkg-config libssl-dev openssl gcc curl make -y
# Install Rust
RUN curl https://sh.rustup.rs -sSf > /tmp/rustup-init.sh \
    && chmod +x /tmp/rustup-init.sh \
    && sh /tmp/rustup-init.sh -y \
    && rm -rf /tmp/rustup-init.sh
ENV PATH "$PATH:~/.cargo/bin"
# Update the local crate index
RUN ~/.cargo/bin/cargo search
# Install rust 1.65.0.
RUN ~/.cargo/bin/rustup install 1.65.0
RUN ~/.cargo/bin/cargo install cargo-download cargo-dylint dylint-link
RUN (cd early && ~/.cargo/bin/cargo build)
RUN (cd late && ~/.cargo/bin/cargo build)
ENV DYLINT_LIBRARY_PATH="/usr/src/ffickle/early/target/debug/:/usr/src/ffickle/late/target/debug/"
RUN mkdir /results