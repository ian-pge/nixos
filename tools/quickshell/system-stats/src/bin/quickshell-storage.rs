use anyhow::{Context, Result, bail};
use quickshell_system_stats::storage::{Options, collect, write_report};
use std::path::PathBuf;

fn options(args: impl Iterator<Item = String>) -> Result<Options> {
    let mut args = args;
    let mut home = None;
    let mut output = None;
    let mut root = None;
    while let Some(flag) = args.next() {
        let slot = match flag.as_str() {
            "--home" => &mut home,
            "--output" => &mut output,
            "--root" => &mut root,
            _ => bail!("Expected --home PATH --output PATH [--root PATH]"),
        };
        if slot.is_some() {
            bail!("Repeated argument");
        }
        *slot = Some(PathBuf::from(
            args.next().context("Missing argument value")?,
        ));
    }
    let options = Options {
        home: home.context("Missing --home")?,
        output: output.context("Missing --output")?,
        root: root.unwrap_or_else(|| PathBuf::from("/")),
    };
    options.validate()?;
    Ok(options)
}

fn main() -> Result<()> {
    let options = options(std::env::args().skip(1))?;
    let report = collect(&options)?;
    write_report(&options.output, &report)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_missing_duplicate_unknown_and_relative_arguments() {
        for args in [
            vec![],
            vec!["--home"],
            vec!["--home", "/home/user", "--home", "/root"],
            vec!["--unknown", "/"],
            vec!["--home", "relative", "--output", "/tmp/report.json"],
            vec![
                "--home",
                "/home/user",
                "--output",
                "/tmp/../etc/report.json",
            ],
        ] {
            assert!(options(args.into_iter().map(str::to_owned)).is_err());
        }
    }
}
