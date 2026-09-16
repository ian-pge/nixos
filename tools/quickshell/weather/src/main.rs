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
            "Usage: quickshell-weather [--search QUERY | --location JSON]\nPrint cached then refreshed weather as JSON Lines. Default: automatic IP geolocation. --location overrides it for this request only."
        );
        return Ok(());
    }
    if let [flag, query] = arguments.as_slice() {
        if flag == "--search" {
            let result = match quickshell_weather::search_locations(query, fetch) {
                Ok(results) => serde_json::json!({"results": results, "error": null}),
                Err(error) => {
                    eprintln!("Location search failed: {error}");
                    serde_json::json!({"results": [], "error": "Recherche de ville indisponible"})
                }
            };
            println!("{result}");
            return Ok(());
        }
    }
    let cache_root = env::var_os("XDG_CACHE_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".cache")))
        .context("no cache directory available")?;
    let manual = match arguments.as_slice() {
        [] => None,
        [flag, json] if flag == "--location" => {
            let location: quickshell_weather::Location = serde_json::from_str(json)?;
            quickshell_weather::validate_location(&location)?;
            Some(location)
        }
        _ => bail!("Unknown arguments; see --help"),
    };
    // Keep local weather available offline after browsing another city's forecast.
    let path = cache_root.join(if manual.is_some() {
        "quickshell/weather/manual-v2.json"
    } else {
        "quickshell/weather/v2.json"
    });
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
    let mut stdout = io::stdout().lock();
    quickshell_weather::update_with_location(&path, now, manual.as_ref(), fetch, |report| {
        serde_json::to_writer(&mut stdout, &report)?;
        writeln!(stdout)?;
        stdout.flush()?;
        Ok(())
    })
}
