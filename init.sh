
apt-get update -y && apt-get upgrade -y && apt-get install pkg-config libssl-dev openssl gcc curl clang llvm make -y
# add the above exports to bashrc
echo "export PATH=\"$PATH:~/.cargo/bin\"\n" >> ~/.bashrc
echo "export DEFAULT_TOOLCHAIN=\"nightly-2023-04-06\"\n" >> ~/.bashrc
echo "export DYLINT_LIBRARY_PATH=\"$PWD/src/early/target/debug/:$PWD/src/late/target/debug/\"\n" >> ~/.bashrc
source ~/.bashrc
curl https://sh.rustup.rs -sSf > /tmp/rustup-init.sh && chmod +x /tmp/rustup-init.sh && sh /tmp/rustup-init.sh -y && rm -rf /tmp/rustup-init.sh
~/.cargo/bin/cargo search
~/.cargo/bin/cargo install cargo-download cargo-dylint dylint-link
~/.cargo/bin/rustup install $DEFAULT_TOOLCHAIN
~/.cargo/bin/rustup default $DEFAULT_TOOLCHAIN
(cd src/early && ~/.cargo/bin/cargo build)
(cd src/late && ~/.cargo/bin/cargo build)