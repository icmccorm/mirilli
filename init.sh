#!/bin/bash
if ! [ $(id -u) = 0 ]; then
   echo "The script need to be run as root." >&2
   exit 1
fi
if [ $SUDO_USER ]; then
    REAL_USER=$SUDO_USER
else
    REAL_USER=$(whoami)
fi
apt-get update -y
apt-get upgrade -y 
apt-get install pkg-config libssl-dev grep openssl gcc curl clang llvm make -y

sudo -u $REAL_USER echo 'export PATH="$PATH:~/.cargo/bin"' >> ~/.bashrc
sudo -u $REAL_USER echo 'export DEFAULT_TOOLCHAIN="nightly-2023-04-06"' >> ~/.bashrc
sudo -u $REAL_USER echo 'export DYLINT_LIBRARY_PATH="$PWD/src/early/target/debug/:$PWD/src/late/target/debug/"' >> ~/.bashrc
sudo -u $REAL_USER source ~/.bashrc
sudo -u $REAL_USER curl https://sh.rustup.rs -sSf > /tmp/rustup-init.sh && chmod +x /tmp/rustup-init.sh && sh /tmp/rustup-init.sh -y && rm -rf /tmp/rustup-init.sh
sudo -u $REAL_USER source "$HOME/.cargo/env"
sudo -u $REAL_USER cargo search
sudo -u $REAL_USER cargo install cargo-download cargo-dylint dylint-link
sudo -u $REAL_USER rustup install $DEFAULT_TOOLCHAIN
sudo -u $REAL_USER rustup default $DEFAULT_TOOLCHAIN
sudo -u $REAL_USER (cd src/early && ~/.cargo/bin/cargo build)
sudo -u $REAL_USER (cd src/late && ~/.cargo/bin/cargo build)