//! Passive phone/Fitbit advertisements only. No GATT/discovery fallback.
use anyhow::{Context, Result, bail, ensure};
use battery_relay_receiver::{
    observer,
    phone::{self, PhoneState},
};
use bluer::Uuid;
use std::time::Duration;
const HELP: &str =
    "battery-relay-receiver --service PHONE_UUID [--adapter hci0] [--duration SECONDS] [--check]
Listens to non-connectable v2 advertisements. No scan, pairing or connection.
--check only checks BlueZ monitor support. The public UUID is not authentication.
";
#[derive(Default)]
struct Options {
    service: Option<Uuid>,
    adapter: Option<String>,
    duration: Option<Duration>,
    check: bool,
}
impl Options {
    fn parse(args: impl Iterator<Item = String>) -> Result<Self> {
        let mut o = Self::default();
        let mut args = args;
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--service" if o.service.is_none() => {
                    let uuid: Uuid = args.next().context("--service requires UUID")?.parse()?;
                    ensure!(!uuid.is_nil(), "Nil installation UUID");
                    o.service = Some(uuid);
                }
                "--adapter" if o.adapter.is_none() => {
                    let name = args.next().context("--adapter requires hciN")?;
                    ensure!(
                        name.starts_with("hci")
                            && name.len() > 3
                            && name[3..].bytes().all(|c| c.is_ascii_digit()),
                        "Invalid adapter"
                    );
                    o.adapter = Some(name);
                }
                "--duration" if o.duration.is_none() => {
                    let seconds: u64 = args
                        .next()
                        .context("--duration requires seconds")?
                        .parse()?;
                    ensure!(
                        (1..=3600).contains(&seconds),
                        "Duration must be 1..3600 seconds"
                    );
                    o.duration = Some(Duration::from_secs(seconds));
                }
                "--check" if !o.check => o.check = true,
                _ => bail!("Unknown/repeated option; use --help"),
            }
        }
        ensure!(o.check || o.service.is_some(), "--service is required");
        Ok(o)
    }
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    if std::env::args().any(|v| v == "--help" || v == "-h") {
        eprint!("{HELP}");
        return std::process::ExitCode::SUCCESS;
    }
    let o = match Options::parse(std::env::args().skip(1)) {
        Ok(o) => o,
        Err(e) => {
            eprintln!("BLE: {e:#}");
            return std::process::ExitCode::from(78);
        }
    };
    let uuid = o.service.unwrap_or(Uuid::nil());
    match observer::observe(
        observer::Options {
            adapter: o.adapter,
            duration: o.duration,
            check: o.check,
        },
        uuid,
        phone::patterns(uuid),
        PhoneState::default(),
    )
    .await
    {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("BLE passive receiver: {e:#}");
            std::process::ExitCode::FAILURE
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn strict_cli_has_no_connected_or_discovery_mode() {
        for args in [
            vec![],
            vec!["--discover"],
            vec!["--pair"],
            vec!["--service", "00000000-0000-0000-0000-000000000000"],
            vec!["--check", "--adapter", "../hci0"],
            vec!["--check", "--duration", "0"],
        ] {
            assert!(Options::parse(args.into_iter().map(String::from)).is_err());
        }
        assert!(Options::parse(["--check"].into_iter().map(String::from)).is_ok());
        assert!(
            Options::parse(
                ["--service", "e167a6ba-8246-4729-8ae6-4f1ecde39e1c"]
                    .into_iter()
                    .map(String::from)
            )
            .is_ok()
        );
    }
}
