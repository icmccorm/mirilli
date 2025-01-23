extern crate cc;
fn main() {
    cc::Build::new().flag("-O0").flag("-Wno-unused-variable").file("src/main.c").compile("libfigure4.a");
}
