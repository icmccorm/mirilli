# syntax=docker/dockerfile:1.7-labs
FROM rocker/verse:4.3.1 AS base
WORKDIR /usr/src/mirilli
COPY --exclude=rust --exclude=.git . .
RUN apt-get update -y && apt-get upgrade -y && apt-get install $(cat pkglist) -y
RUN curl -O https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && ./llvm.sh 16 all && rm ./llvm.sh
RUN curl https://sh.rustup.rs -sSf > /tmp/rustup-init.sh \
    && chmod +x /tmp/rustup-init.sh \
    && sh /tmp/rustup-init.sh -y \
    && rm -rf /tmp/rustup-init.sh
ENV PATH="/root/.cargo/bin:${PATH}"
ENV NIGHTLY="nightly-2023-09-25"
ENV CC="clang-16 -g -O0 --save-temps=obj"
ENV CXX="clang++-16 -g -O0 --save-temps=obj"
ENV PATH="/usr/src/mirilli/rllvm-as/target/release:${PATH}"
ENV LLVM_SYS_181_PREFIX="/usr/src/mirilli/rust/build/host/llvm/"
ENV DATASET="/usr/src/mirilli/dataset"
RUN rustup install nightly
RUN rustup install ${NIGHTLY}
RUN rustup default ${NIGHTLY}
RUN cargo install cargo-download
RUN rustup component add miri
RUN rustup component add rust-src
RUN R -e "install.packages('renv', repos = c(CRAN = 'https://cloud.r-project.org'))"
RUN R -e "renv::restore()"
RUN cargo install cargo-dylint@2.6.0 dylint-link@2.6.0 --locked
RUN (cd src/early && cargo build)
RUN (cd src/late && cargo build)

FROM base as rust_compile
WORKDIR /usr/src/mirilli
COPY . .
ENV LLVM_SYS_181_PREFIX="/usr/src/mirilli/rust/build/host/llvm/"
RUN git submodule update --init rust rllvm-as 
RUN mkdir rust-install
RUN (cd rust \
    && git submodule update --init src/llvm-project src/inkwell src/llvm-sys \
    && LLVM_SYS_181_PREFIX=${LLVM_SYS_181_PREFIX} ./x.py install --config src/bootstrap/defaults/config.dist.toml --set install.prefix=/usr/src/mirilli/rust-install)
ENV LLVM_SYS_181_PREFIX="/usr/src/mirilli/rust/build/host/llvm/"
RUN git submodule update --init rust rllvm-as
RUN (cd ./rllvm-as \
    && git submodule update --init llvm-sys inkwell \
    && LLVM_SYS_181_PREFIX=${LLVM_SYS_181_PREFIX} cargo build --release)

FROM base AS with_rust
WORKDIR /usr/src/mirilli/
COPY --from=rust_compile /usr/src/mirilli/rust-install rust-install
RUN rm -rf rllvm-as
COPY --from=rust_compile /usr/src/mirilli/rllvm-as/ rllvm-as
RUN rustup toolchain link mirilli ./rust-install
RUN rustup default mirilli
RUN cargo miri setup
