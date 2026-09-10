fn main() {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    if args.len() != 2 || !args.iter().all(|p| std::path::Path::new(p).exists()) {
        eprintln!("usage: quickshell-update-diff OLD_SYSTEM NEW_SYSTEM (both paths must exist)");
        std::process::exit(2);
    }
    quickshell_update::main_result(|runner| {
        quickshell_update::output(&quickshell_update::diff::build(
            std::path::Path::new(&args[0]),
            std::path::Path::new(&args[1]),
            runner,
        )?)
    });
}
