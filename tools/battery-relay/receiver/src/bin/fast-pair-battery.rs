//! Read-only, connection-free BATT receiver. One process per shell, independent
//! of the phone relay. NEVER pairs/connects/writes attributes or changes power.
use anyhow::{Context, Result, bail, ensure};
use battery_relay_receiver::{
    fast_pair::{AccountKey, Levels, REFRESH_AFTER, Reading, SERVICE, State},
    output::{EventOutput, output_closed},
};
use bluer::{AdapterEvent, AdapterProperty, DiscoveryFilter, DiscoveryTransport};
use dbus::{
    arg::{ArgType, PropMap, RefArg, prop_cast},
    message::MatchRule,
};
use futures::StreamExt;
use std::{
    collections::HashMap,
    io,
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tokio::{
    signal::unix::{SignalKind, signal},
    sync::mpsc,
};

const HELP: &str = "fast-pair-battery --key-file /absolute/private/account-key [--adapter hci0] [--duration SECONDS] [--check]
Reads encrypted Fast Pair BATT advertisements only. No phone, GATT connection,
pairing, audio profile, key creation or Find Hub operation. --check does not scan.
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

fn wall_ms() -> Result<u64> {
    Ok(SystemTime::now()
        .duration_since(UNIX_EPOCH)?
        .as_millis()
        .try_into()?)
}
/// CLOCK_BOOTTIME, unlike Instant/CLOCK_MONOTONIC, includes suspend.
fn boot_time() -> Result<Duration> {
    let mut value = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    // SAFETY: one valid timespec and a supported Linux clock.
    ensure!(
        unsafe { libc::clock_gettime(libc::CLOCK_BOOTTIME, &mut value) } == 0,
        "Cannot read suspend-aware clock"
    );
    Ok(Duration::new(
        value.tv_sec.try_into()?,
        value.tv_nsec.try_into()?,
    ))
}

fn unvariant(value: &dyn RefArg) -> Option<&dyn RefArg> {
    if value.arg_type() == ArgType::Variant {
        value.as_iter()?.next()
    } else {
        Some(value)
    }
}
fn fast_pair_bytes(properties: &PropMap) -> Option<Vec<u8>> {
    let data = properties.get("ServiceData")?;
    let mut entries = data.0.as_iter()?;
    while let (Some(key), Some(value)) = (entries.next(), entries.next()) {
        if key.as_str() != Some(SERVICE) {
            continue;
        }
        let mut bytes = Vec::new();
        for byte in unvariant(value)?.as_iter()? {
            bytes.push(u8::try_from(byte.as_u64()?).ok()?);
            if bytes.len() > 255 {
                return None;
            }
        }
        return Some(bytes);
    }
    None
}

enum RadioEvent {
    Reading(Reading, Duration, u64),
    Off,
}
fn forward(
    properties: &PropMap,
    key: &AccountKey,
    send: &mpsc::Sender<RadioEvent>,
    overflow: &AtomicBool,
) {
    let Some(data) = fast_pair_bytes(properties) else {
        return;
    };
    let Some(reading) = key.decode(&data) else {
        return;
    };
    if let (Ok(now), Ok(wall)) = (boot_time(), wall_ms())
        && send
            .try_send(RadioEvent::Reading(reading, now, wall))
            .is_err()
    {
        overflow.store(true, Ordering::Relaxed);
    }
}

fn same_values(a: Levels, b: Levels) -> bool {
    a.case == b.case && a.left == b.left && a.right == b.right
}

async fn run(options: Options, key: AccountKey) -> Result<()> {
    let session = bluer::Session::new().await?;
    let adapter = match options.adapter {
        Some(ref name) => session.adapter(name)?,
        None => session.default_adapter().await?,
    };
    ensure!(adapter.is_powered().await?, "Bluetooth is off");
    let prefix = format!("/org/bluez/{}/dev_", adapter.name());
    let (resource, connection) = dbus_tokio::connection::new_system_sync()?;
    let resource_task = tokio::spawn(resource);
    struct Abort<T>(tokio::task::JoinHandle<T>);
    impl<T> Drop for Abort<T> {
        fn drop(&mut self) {
            self.0.abort();
        }
    }
    let _resource = Abort(resource_task);
    let key = Arc::new(key);
    let overflow = Arc::new(AtomicBool::new(false));
    let (send, mut receive) = mpsc::channel(32);
    let (key1, send1, overflow1, prefix1) =
        (key.clone(), send.clone(), overflow.clone(), prefix.clone());
    // Subscribe BEFORE discovery. No GetManagedObjects cache is presented as a
    // fresh reading; only live ServiceData/InterfacesAdded signals are accepted.
    let properties = connection
        .add_match(
            MatchRule::new_signal("org.freedesktop.DBus.Properties", "PropertiesChanged")
                .with_sender("org.bluez")
                .with_namespaced_path(format!("/org/bluez/{}", adapter.name())),
        )
        .await?
        .cb(
            move |message, (interface, properties, _): (String, PropMap, Vec<String>)| {
                if interface == "org.bluez.Device1"
                    && message
                        .path()
                        .is_some_and(|path| path.starts_with(&prefix1))
                {
                    forward(&properties, &key1, &send1, &overflow1);
                } else if interface == "org.bluez.Adapter1"
                    && prop_cast::<bool>(&properties, "Powered") == Some(&false)
                {
                    let _ = send1.try_send(RadioEvent::Off);
                }
                true
            },
        );
    let (key2, send2, overflow2) = (key.clone(), send.clone(), overflow.clone());
    let added = connection
        .add_match(
            MatchRule::new_signal("org.freedesktop.DBus.ObjectManager", "InterfacesAdded")
                .with_sender("org.bluez"),
        )
        .await?
        .cb(
            move |_, (path, interfaces): (dbus::Path<'static>, HashMap<String, PropMap>)| {
                if path.starts_with(&prefix)
                    && let Some(properties) = interfaces.get("org.bluez.Device1")
                {
                    forward(properties, &key2, &send2, &overflow2);
                }
                true
            },
        );
    let output = EventOutput::new(io::stdout(), Duration::from_secs(2))?;
    output.emit(&Levels::default().event(wall_ms()?)).await?;
    adapter
        .set_discovery_filter(DiscoveryFilter {
            transport: DiscoveryTransport::Le,
            duplicate_data: true,
            ..Default::default()
        })
        .await?;
    let mut state = State::default();
    let mut shown = Levels::default();
    let mut last_emit = Duration::ZERO;
    let mut stop = signal(SignalKind::terminate())?;
    let mut interrupt = signal(SignalKind::interrupt())?;
    let mut tick = tokio::time::interval(Duration::from_secs(1));
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let duration = options.duration.unwrap_or(Duration::MAX);
    let start = boot_time()?;
    let work: Result<()> = {
        let discovery = adapter.discover_devices().await?;
        tokio::pin!(discovery);
        eprintln!(
            "Fast Pair battery: read-only LE discovery active; waiting for our account-key match."
        );
        loop {
            let mut fresh_packet = false;
            tokio::select! {
                _=stop.recv()=>break Ok(()),
                _=interrupt.recv()=>break Ok(()),
                event=receive.recv()=>match event {
                    Some(RadioEvent::Reading(reading,heard,wall))=>{
                        state.receive(reading,heard,wall); fresh_packet=true;
                    },
                    Some(RadioEvent::Off)=>break Err(anyhow::anyhow!("Bluetooth switched off")),
                    None=>break Err(anyhow::anyhow!("Battery signal stream closed")),
                },
                event=discovery.next()=>match event {
                    None|Some(AdapterEvent::PropertyChanged(AdapterProperty::Powered(false)))=>
                        break Err(anyhow::anyhow!("Bluetooth discovery stopped")),
                    _=>{}
                },
                _=tick.tick()=>{
                    if output_closed(libc::STDOUT_FILENO) {break Ok(());}
                    if overflow.load(Ordering::Relaxed) {break Err(anyhow::anyhow!("Battery event queue overflow"));}
                    if boot_time()?.saturating_sub(start)>=duration {break Ok(());}
                }
            }
            let now = boot_time()?;
            let levels = state.levels(now);
            if !same_values(shown, levels)
                || (fresh_packet && now.saturating_sub(last_emit) >= REFRESH_AFTER)
            {
                output.emit(&levels.event(wall_ms()?)).await?;
                shown = levels;
                last_emit = now;
            }
        }
    };
    let _ = output.emit(&Levels::default().event(wall_ms()?)).await;
    let _ = connection.remove_match(properties.token()).await;
    let _ = connection.remove_match(added.token()).await;
    tokio::time::sleep(Duration::from_millis(250)).await;
    work
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
    use dbus::arg::Variant;
    #[test]
    fn service_data_is_extracted_without_reading_other_device_properties() {
        let data: HashMap<String, Variant<Vec<u8>>> =
            [(SERVICE.into(), Variant(vec![0x10, 0x1a, 1, 2, 3, 4]))].into();
        let properties: PropMap = [(
            "ServiceData".into(),
            Variant(Box::new(data) as Box<dyn RefArg>),
        )]
        .into();
        assert_eq!(
            fast_pair_bytes(&properties),
            Some(vec![0x10, 0x1a, 1, 2, 3, 4])
        );
        assert_eq!(fast_pair_bytes(&PropMap::new()), None);
    }
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
