use quickshell_chrome_tabs::{Paths, failure, process::Runner, response};
use std::{
    io::{self, Write},
    os::unix::process::CommandExt,
    process::Command,
};

fn main() {
    let args: Vec<_> = std::env::args().skip(1).collect();
    let valid = matches!(args.first().map(String::as_str), Some("list" | "status"))
        && args.len() == 1
        || matches!(args.first().map(String::as_str), Some("activate" | "close"))
            && args.len() == 2
            && !args[1].is_empty();
    if !valid {
        eprintln!("usage: quickshell-chrome-tabs {{list|activate|close|status}} [tab-id]");
        std::process::exit(2);
    }
    if args[0] == "status" {
        let error = Command::new("tabctl").arg("status").exec();
        eprintln!("Unable to start tabctl: {error}");
        std::process::exit(1);
    }
    let runner = Runner::new().unwrap_or_else(|e| {
        eprintln!("{e}");
        std::process::exit(1);
    });
    let result = Paths::from_env().and_then(|paths| response(&args, &paths, &runner));
    if let Some(signal) = runner.signal() {
        std::process::exit(128 + signal);
    }
    let value = result.unwrap_or_else(|e| failure(&format!("{e:#}"), args[0] == "list"));
    if let Err(e) = writeln!(io::stdout().lock(), "{value}")
        && e.kind() != io::ErrorKind::BrokenPipe
    {
        eprintln!("{e}");
        std::process::exit(1);
    }
}
