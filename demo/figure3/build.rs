extern crate cc;
fn main() {
    cc::Build::new().flag("-O0").file("src/main.c").compile("libfigure3.a");
}
