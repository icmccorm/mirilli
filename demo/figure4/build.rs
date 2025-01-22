extern crate cc;
use std::path::PathBuf;
use std::env;
fn main() {
    println!("cargo:rustc-link-search=./src/");
    cc::Build::new().flag("-O0").file("src/main.c").compile("libfigure4.a");
}
