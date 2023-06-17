#!/bin/bash
echo 'export PATH="$PATH:~/.cargo/bin"' >> ~/.bashrc
echo 'export DEFAULT_TOOLCHAIN="nightly-2023-04-06"' >> ~/.bashrc
echo 'export DYLINT_LIBRARY_PATH="$PWD/src/early/target/debug/:$PWD/src/late/target/debug/"' >> ~/.bashrc
source ~/.bashrc
curl https://sh.rustup.rs -sSf > /tmp/rustup-init.sh && chmod +x /tmp/rustup-init.sh && sh /tmp/rustup-init.sh -y && rm -rf /tmp/rustup-init.sh
source "$HOME/.cargo/env"
cargo search
cargo install cargo-download cargo-dylint dylint-link
rustup install $DEFAULT_TOOLCHAIN
rustup default $DEFAULT_TOOLCHAIN
(cd src/early && ~/.cargo/bin/cargo build)
(cd src/late && ~/.cargo/bin/cargo build)