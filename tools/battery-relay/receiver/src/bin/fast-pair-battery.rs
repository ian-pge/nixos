//! Connection-free Fast Pair battery reader, using the shared passive observer.
use anyhow::{Context, Result, bail, ensure};
use battery_relay_receiver::{
    Event,
    fast_pair::AccountKey,
    observer::{self, Source},
    passive::{self, PassiveState},
};
use std::{path::PathBuf, time::Duration};
const HELP: &str = "fast-pair-battery --key-file /absolute/private/account-key [--adapter hci0] [--duration SECONDS] [--check]
Reads encrypted Fast Pair BATT advertisements only. No phone, GATT connection,
active discovery, pairing, audio profile, key creation or Find Hub operation.
Requires BlueZ AdvertisementMonitor (Experimental=true); there is no scan fallback.
--check validates the private key only and does not register a monitor.
Key file: 16 raw bytes, owner-only permissions, outside Git and the Nix store.
";

#[derive(Default, Debug, PartialEq)]
struct Options {
    key: PathBuf,
    adapter: Option<String>,
    duration: Option<Duration>,
    check: bool,
}
impl Options {
    fn parse(args: impl Iterator<Item = String>) -> Result<Self> {
        let mut args = args;
        let mut options = Self::default();
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--key-file" if options.key.as_os_str().is_empty() => {
                    options.key = args.next().context("--key-file requires a path")?.into()
                }
                "--adapter" if options.adapter.is_none() => {
                    let name = args.next().context("--adapter requires hciN")?;
                    ensure!(
                        name.starts_with("hci")
                            && name.len() > 3
                            && name[3..].bytes().all(|c| c.is_ascii_digit()),
                        "Invalid adapter"
                    );
                    options.adapter = Some(name);
                }
                "--duration" if options.duration.is_none() => {
                    let seconds: u64 = args
                        .next()
                        .context("--duration requires seconds")?
                        .parse()?;
                    ensure!(
                        (1..=3600).contains(&seconds),
                        "Duration must be 1..3600 seconds"
                    );
                    options.duration = Some(Duration::from_secs(seconds));
                }
                "--check" if !options.check => options.check = true,
                _ => bail!("Unknown or repeated option; use --help"),
            }
        }
        ensure!(
            !options.key.as_os_str().is_empty(),
            "--key-file is required; no scan started"
        );
        Ok(options)
    }
}

struct Earbuds {
    key: AccountKey,
    state: PassiveState,
}
impl Source for Earbuds {
    fn found(
        &mut self,
        path: String,
        data: Option<&[u8]>,
        heard: Duration,
        observed: u64,
    ) -> Result<()> {
        self.state
            .found(path, data.and_then(|v| self.key.decode(v)), heard, observed)
    }
    fn update(&mut self, path: &str, data: Option<&[u8]>, heard: Duration, observed: u64) {
        self.state
            .update(path, data.and_then(|v| self.key.decode(v)), heard, observed);
    }
    fn lost(&mut self, path: &str) {
        self.state.lost(path);
    }
    fn event(&self, received_at: u64) -> Event {
        self.state.levels().event(received_at)
    }
}
async fn run(options: Options, key: AccountKey) -> Result<()> {
    observer::observe(
        observer::Options {
            adapter: options.adapter,
            duration: options.duration,
            check: false,
        },
        bluer::Uuid::from_u128(0x0000fe2c_0000_1000_8000_00805f9b34fb),
        passive::specification().patterns.unwrap(),
        Earbuds {
            key,
            state: PassiveState::default(),
        },
    )
    .await
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    if std::env::args().any(|arg| arg == "--help" || arg == "-h") {
        eprint!("{HELP}");
        return std::process::ExitCode::SUCCESS;
    }
    let options = match Options::parse(std::env::args().skip(1)) {
        Ok(v) => v,
        Err(error) => {
            eprintln!("Fast Pair battery: {error:#}");
            return std::process::ExitCode::from(78);
        }
    };
    let key = match AccountKey::load(&options.key) {
        Ok(v) => v,
        Err(error) => {
            eprintln!("Fast Pair battery: {error:#}");
            return std::process::ExitCode::from(78);
        }
    };
    if options.check {
        eprintln!("Private Fast Pair key file valid; no scan or connection.");
        return std::process::ExitCode::SUCCESS;
    }
    match run(options, key).await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("Fast Pair battery: {error:#}");
            std::process::ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn secrets_are_files_not_cli_values_and_no_pairing_mode_exists() {
        assert!(
            Options::parse(
                ["--key-file", "/private/key", "--duration", "20"]
                    .map(String::from)
                    .into_iter()
            )
            .is_ok()
        );
        for args in [
            vec![],
            vec!["--pair"],
            vec!["--key-file", "/key", "--duration", "0"],
            vec!["--key-file", "/key", "--adapter", "../hci0"],
        ] {
            assert!(Options::parse(args.into_iter().map(String::from)).is_err());
        }
    }
}
