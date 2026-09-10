use anyhow::{Context, Result, bail};
use serde_json::Value;
use std::{
    env,
    io::{self, Write},
    path::PathBuf,
    process::Command,
    time::{SystemTime, UNIX_EPOCH},
};

fn fetch(url: &str) -> Result<Value> {
    let output = Command::new("curl")
        .args([
            "--fail",
            "--silent",
            "--show-error",
            "--header",
            "Accept: application/json",
            "--connect-timeout",
            "5",
            "--max-time",
            "12",
            "--max-filesize",
            "1048576",
            "--proto",
            "=https",
            url,
        ])
        .output()
        .context("unable to run curl")?;
    if !output.status.success() {
        bail!("HTTP request failed ({})", output.status);
    }
    serde_json::from_slice(&output.stdout).context("invalid weather JSON")
}

fn main() -> Result<()> {
    let arguments: Vec<_> = env::args().skip(1).collect();
    if arguments == ["--help"] || arguments == ["-h"] {
        println!(
            "Usage: quickshell-weather\nPrint cached then refreshed weather as JSON Lines. Location is estimated automatically via fwd.gr; weather comes from Open-Meteo."
        );
        return Ok(());
    }
    if !arguments.is_empty() {
        bail!("Usage: quickshell-weather [--help]");
    }
    let cache_root = env::var_os("XDG_CACHE_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".cache")))
        .context("no cache directory available")?;
    let path = cache_root.join("quickshell/weather/v2.json");
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
    let mut stdout = io::stdout().lock();
    quickshell_weather::update(&path, now, fetch, |report| {
        serde_json::to_writer(&mut stdout, &report)?;
        writeln!(stdout)?;
        stdout.flush()?;
        Ok(())
    })
}
