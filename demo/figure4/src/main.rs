
mod bug;
mod fix;
mod ffi;

fn usage() -> ! {
    println!("Usage: figure3 <bug|fix>");
    std::process::exit(1);
}
fn main() {
    let args = std::env::args().collect::<Vec<String>>();
    if args.len() != 2 {
        usage();
    }
    match args[1].as_str() {
        "bug" => bug::exec(),
        "fix" => fix::exec(),
        _ => usage(),
    }
}
