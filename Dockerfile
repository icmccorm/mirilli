FROM rocker/verse:4.3.1 AS setup
WORKDIR /usr/src/mirilli
COPY . .
RUN apt-get update -y && apt-get upgrade -y && apt-get install $(cat pkglist) -y
RUN curl -O https://apt.llvm.org/llvm.sh
RUN chmod +x llvm.sh
RUN ./llvm.sh 18 all
RUN curl https://sh.rustup.rs -sSf > /tmp/rustup-init.sh \
    && chmod +x /tmp/rustup-init.sh \
    && sh /tmp/rustup-init.sh -y \
    && rm -rf /tmp/rustup-init.sh
ENV PATH="/root/.cargo/bin:${PATH}"
ENV NIGHTLY="nightly-2023-09-25"
ENV CC="clang-18 -g -O0 --save-temps=obj"
ENV CXX="clang++-18 -g -O0 --save-temps=obj"
ENV PATH="/usr/src/mirilli/rllvm-as/target/release:${PATH}"
ENV LLVM_SYS_181_PREFIX="/usr/src/mirilli/mirilli-rust/build/host/llvm/"
RUN rustup install ${NIGHTLY}
RUN rustup default ${NIGHTLY}
RUN rustup component add miri
RUN rustup component add rust-src
RUN rustup install nightly
RUN git submodule update --init ./mirilli-rust
RUN git submodule update --init ./rllvm-as

FROM setup AS setup-renv
RUN R -e "install.packages('renv', repos = c(CRAN = 'https://cloud.r-project.org'))"
RUN R -e "renv::restore()"

FROM setup-renv as rust-compile
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

FROM miri-compile as rllvm-compile
WORKDIR /usr/src/mirilli/rllvm-as
RUN git submodule update --init ./inkwell
RUN git submodule update --init ./llvm-sys
RUN LLVM_SYS_181_PREFIX=${LLVM_SYS_181_PREFIX} cargo build --release

FROM rllvm-compile as final
WORKDIR /usr/src/mirilli
RUN cargo install cargo-download