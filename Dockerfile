FROM rocker/verse:4.3.1 AS setup
WORKDIR /usr/src/mirilli

COPY . .
RUN apt-get update -y && apt-get upgrade -y && apt-get install $(cat pkglist) -y
RUN curl -O https://apt.llvm.org/llvm.sh
RUN chmod +x llvm.sh
RUN ./llvm.sh 16 all
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
ENV DATASET="./dataset"
RUN rustup install nightly
RUN rustup install ${NIGHTLY}
RUN rustup default ${NIGHTLY}
RUN cargo install cargo-download
RUN rustup component add miri
RUN rustup component add rust-src
RUN git submodule update --init ./rust
RUN git submodule update --init ./rllvm-as

FROM setup AS setup-dylint
RUN cargo install cargo-dylint@2.6.0 dylint-link@2.6.0 --locked
RUN (cd src/early && cargo build)
RUN (cd src/late && cargo build)

FROM setup-dylint AS setup-renv
RUN R -e "install.packages('renv', repos = c(CRAN = 'https://cloud.r-project.org'))"
RUN R -e "renv::restore()"

FROM setup-renv AS rust-compile
WORKDIR /usr/src/mirilli/rust
RUN git submodule update --init ./src/llvm-project
RUN git submodule update --init ./src/inkwell
RUN git submodule update --init ./src/llvm-sys
RUN mkdir /usr/src/mirilli/rust-install
ENV LLVM_SYS_181_PREFIX=/usr/src/mirilli/rust/build/host/llvm/
RUN LLVM_SYS_181_PREFIX=${LLVM_SYS_181_PREFIX} ./x.py install --config config.toml
RUN rustup toolchain link mirilli /usr/src/mirilli/rust-install
RUN rustup default mirilli
RUN cargo miri setup

FROM miri-compile AS rllvm-compile
WORKDIR /usr/src/mirilli/rllvm-as
RUN git submodule update --init ./inkwell
RUN git submodule update --init ./llvm-sys
RUN LLVM_SYS_181_PREFIX=${LLVM_SYS_181_PREFIX} cargo build --release

FROM rllvm-compile AS final
WORKDIR /usr/src/mirilli/
RUN rm -rf ./rust
RUN rm -rf .git
RUN rm -rf /usr/src/mirilli/rllvm-as/inkwell
RUN rm -rf /usr/src/mirilli/rllvm-as/llvm-sys
