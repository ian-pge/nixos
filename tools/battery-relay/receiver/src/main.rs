use anyhow::{Context, Result, bail};
use battery_relay_receiver::{
    Event, RecoveryLink, RelayState, SNAPSHOT_UUID, Snapshot, link_usable,
};
use bluer::{
    Adapter, AdapterEvent, AdapterProperty, AddressType, Device, DeviceEvent, DeviceProperty,
    DiscoveryFilter, DiscoveryTransport, Uuid, gatt::remote::Characteristic,
};
use futures::StreamExt;
use std::{
    fmt,
    future::Future,
    io::{self, Write},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use tokio::{
    signal::unix::{SignalKind, signal},
    sync::{mpsc, oneshot},
};

const HELP: &str = "battery-relay-receiver [--adapter hci0] --service PHONE_SERVICE_UUID
battery-relay-receiver [--adapter hci0] --check
battery-relay-receiver [--adapter hci0] --service PHONE_SERVICE_UUID --discover

Unpaired, unencrypted BLE central. The public installation UUID selects the
phone despite rotating BLE addresses; it is NOT authentication or a secret.
No pairing agent, trust changes, power changes or audio profile commands.
--check is read-only. --discover scans for 15 seconds without connecting.
Stdout is NDJSON battery/connection events; diagnostics go to stderr.
";

const GATT_TIMEOUT: Duration = Duration::from_secs(15);

/// A broken GATT session must not be reused indefinitely. Let the supervising
/// shell start a fresh D-Bus client after the selected LE link is released.
#[derive(Debug)]
struct SessionLost(&'static str);
impl fmt::Display for SessionLost {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.0)
    }
}
impl std::error::Error for SessionLost {}

async fn bounded<T>(
    operation: &'static str,
    limit: Duration,
    future: impl Future<Output = Result<T>>,
) -> Result<T> {
    tokio::time::timeout(limit, future)
        .await
        .map_err(|_| SessionLost(operation))?
}

async fn recover_selected_link(device: &Device) -> Result<()> {
    // No name/address fallback: this Device was selected through the configured
    // service UUID in THIS session. Never reset paired/trusted/public-address
    // links (which may include audio), another device, or the adapter itself.
    let link = bounded(
        "reading recovery link state timed out",
        GATT_TIMEOUT,
        async {
            Ok(RecoveryLink {
                selected: true,
                connected: device.is_connected().await?,
                blocked: device.is_blocked().await?,
                random_address: device.address_type().await? == AddressType::LeRandom,
                paired: device.is_paired().await?,
                trusted: device.is_trusted().await?,
            })
        },
    )
    .await?;
    if !link.connected {
        return Ok(());
    }
    if !link.can_reset() {
        bail!(
            "automatic link reset refused: selected device is no longer an unpaired, untrusted private LE link"
        );
    }
    eprintln!(
        "Battery Relay: releasing the selected private LE link to rediscover its battery service."
    );
    bounded(
        "releasing the selected LE link timed out",
        GATT_TIMEOUT,
        async {
            device.disconnect().await?;
            Ok(())
        },
    )
    .await
}
#[derive(Debug, Default, PartialEq)]
struct Options {
    adapter: Option<String>,
    service: Option<Uuid>,
    check: bool,
    discover: bool,
    help: bool,
}

impl Options {
    fn parse(args: impl IntoIterator<Item = String>) -> Result<Self> {
        let mut options = Self::default();
        let mut args = args.into_iter();
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--adapter" if options.adapter.is_none() => {
                    let name = args.next().context("--adapter needs a name, e.g. hci0")?;
                    if !name.starts_with("hci")
                        || name.len() < 4
                        || !name[3..].chars().all(|c| c.is_ascii_digit())
                    {
                        bail!("invalid Bluetooth adapter name");
                    }
                    options.adapter = Some(name);
                }
                "--service" if options.service.is_none() => {
                    let value = args
                        .next()
                        .context("--service needs the UUID displayed by the phone app")?;
                    let service: Uuid = value.parse().context("invalid --service UUID")?;
                    if service.is_nil() {
                        bail!("--service cannot be the nil UUID");
                    }
                    options.service = Some(service);
                }
                "--check" if !options.check => options.check = true,
                "--discover" if !options.discover => options.discover = true,
                "--help" | "-h" => options.help = true,
                _ => bail!("unknown or repeated option {arg:?}; use --help"),
            }
        }
        if options.check && options.discover {
            bail!("--check and --discover cannot be combined");
        }
        if !options.check && !options.help && options.service.is_none() {
            bail!("--service is required; no Bluetooth connection was started");
        }
        Ok(options)
    }
}

fn epoch_ms() -> Result<u64> {
    Ok(SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("PC clock is before the Unix epoch")?
        .as_millis()
        .try_into()?)
}

fn emit(output: &mut impl Write, event: &Event) -> io::Result<()> {
    serde_json::to_writer(&mut *output, event)?;
    output.write_all(b"\n")?;
    output.flush()
}

/// Stdout can block even when its reader is alive (for example, a frozen UI).
/// Keep writes off the Bluetooth reactor and bound both queued events and the
/// time spent waiting for a consumer acknowledgement. This is a plain worker
/// thread, not Tokio's blocking pool: a stalled pipe cannot hold runtime shutdown.
struct EventOutput {
    sender: mpsc::Sender<(Event, oneshot::Sender<io::Result<()>>)>,
    timeout: Duration,
}

impl EventOutput {
    fn new(mut writer: impl Write + Send + 'static, timeout: Duration) -> io::Result<Self> {
        let (sender, mut receiver) = mpsc::channel::<(Event, oneshot::Sender<io::Result<()>>)>(4);
        std::thread::Builder::new()
            .name("battery-output".into())
            .spawn(move || {
                while let Some((event, response)) = receiver.blocking_recv() {
                    let result = emit(&mut writer, &event);
                    let failed = result.is_err();
                    let _ = response.send(result);
                    if failed {
                        break;
                    }
                }
            })?;
        Ok(Self { sender, timeout })
    }

    async fn emit(&self, event: &Event) -> io::Result<()> {
        let (response, result) = oneshot::channel();
        self.sender
            .try_send((event.clone(), response))
            .map_err(|error| {
                io::Error::other(format!("battery output queue unavailable: {error}"))
            })?;
        tokio::time::timeout(self.timeout, result)
            .await
            .map_err(|_| {
                io::Error::new(io::ErrorKind::TimedOut, "battery output consumer stalled")
            })?
            .map_err(|_| {
                io::Error::new(io::ErrorKind::BrokenPipe, "battery output worker stopped")
            })?
    }
}

/// A pipe may disappear while the phone has nothing new to send. poll(2) with
/// timeout zero detects that without generating bogus battery/heartbeat events.
fn output_closed(fd: std::os::fd::RawFd) -> bool {
    let mut descriptor = libc::pollfd {
        fd,
        events: 0,
        revents: 0,
    };
    // SAFETY: one initialized pollfd, valid for this synchronous, nonblocking call.
    unsafe {
        libc::poll(&mut descriptor, 1, 0) > 0
            && descriptor.revents & (libc::POLLERR | libc::POLLHUP | libc::POLLNVAL) != 0
    }
}

async fn approved(device: &Device) -> bool {
    let (connected, blocked) = tokio::join!(device.is_connected(), device.is_blocked());
    link_usable(connected.unwrap_or(false), blocked.unwrap_or(true))
}

async fn check(adapter: &Adapter) -> Result<()> {
    eprintln!("Adapter: {} ({})", adapter.name(), adapter.address().await?);
    eprintln!("Powered: {}", adapter.is_powered().await?);
    eprintln!("Read-only check complete; no scan, connection or setting changed.");
    Ok(())
}

fn discovery_filter(service: Uuid) -> DiscoveryFilter {
    DiscoveryFilter {
        transport: DiscoveryTransport::Le,
        uuids: [service].into_iter().collect(),
        duplicate_data: false,
        ..Default::default()
    }
}

async fn discover(adapter: &Adapter, service: Uuid, list_only: bool) -> Result<Option<Device>> {
    bounded(
        "setting the discovery filter timed out",
        GATT_TIMEOUT,
        async {
            adapter
                .set_discovery_filter(discovery_filter(service))
                .await?;
            Ok(())
        },
    )
    .await?;
    // BlueR first replays cached devices. An Android advertising address may
    // have rotated since that cache was populated: wait for a live update.
    let mut cached: std::collections::HashSet<_> =
        adapter.device_addresses().await?.into_iter().collect();
    let events = bounded("starting BLE discovery timed out", GATT_TIMEOUT, async {
        Ok(adapter.discover_devices_with_changes().await?)
    })
    .await?;
    tokio::pin!(events);
    let deadline = tokio::time::sleep(Duration::from_secs(15));
    tokio::pin!(deadline);
    let mut reported = std::collections::HashSet::new();
    loop {
        let event = tokio::select! {
            _ = &mut deadline => break,
            event = events.next() => match event { Some(event) => event, None => break },
        };
        let address = match event {
            AdapterEvent::DeviceAdded(address) => address,
            _ => continue,
        };
        if cached.remove(&address) {
            continue;
        }
        let device = adapter.device(address)?;
        if !device.uuids().await?.unwrap_or_default().contains(&service) {
            continue;
        }
        if !list_only {
            if device.is_blocked().await? {
                bail!("selected phone is blocked");
            }
            // Keep our discovery handle alive until Connect completes. Dropping
            // it first schedules StopDiscovery concurrently with connection setup.
            if !device.is_connected().await? {
                bounded(
                    "connecting to the advertised BLE service timed out",
                    GATT_TIMEOUT,
                    async {
                        device
                            .connect()
                            .await
                            .context("connect to the advertised BLE service")?;
                        Ok(())
                    },
                )
                .await?;
            }
            return Ok(Some(device));
        }
        if reported.insert(address) {
            eprintln!(
                "Battery Relay live BLE candidate: {address} (public identifier, not authenticated)"
            );
        }
    }
    Ok(None)
}

async fn find_characteristic(device: &Device, service_uuid: Uuid) -> Result<Characteristic> {
    for service in device.services().await? {
        if service.uuid().await? != service_uuid {
            continue;
        }
        for characteristic in service.characteristics().await? {
            if characteristic.uuid().await? != SNAPSHOT_UUID {
                continue;
            }
            let flags = characteristic.flags().await?;
            if flags.read && flags.indicate {
                return Ok(characteristic);
            }
            bail!("Battery Relay characteristic does not support read + indications");
        }
    }
    bail!("Battery Relay service absent; activate the relay on the phone")
}

async fn accept_snapshot(
    bytes: &[u8],
    device: &Device,
    state: &mut RelayState,
    epoch: Instant,
    output: &EventOutput,
) -> Result<()> {
    if !bounded("checking the battery link timed out", GATT_TIMEOUT, async {
        Ok(approved(device).await)
    })
    .await?
    {
        bail!("phone disconnected or blocked");
    }
    let packet = Snapshot::decode(bytes)?;
    for event in state.receive(packet, epoch.elapsed(), epoch_ms()?) {
        output.emit(&event).await?;
    }
    Ok(())
}

async fn receive_session(
    adapter: &Adapter,
    service: Uuid,
    state: &mut RelayState,
    epoch: Instant,
    output: &EventOutput,
    selected: &mut Option<Device>,
) -> Result<()> {
    // StopNotify does not necessarily close the ACL. The phone may advertise a
    // new private address while the old link is still alive. Reuse that verified
    // service before attempting a second connection to the same physical phone.
    let device = bounded(
        "finding the selected BLE device timed out",
        Duration::from_secs(45),
        async {
            for address in adapter.device_addresses().await? {
                let candidate = adapter.device(address)?;
                if approved(&candidate).await
                    && candidate
                        .uuids()
                        .await?
                        .unwrap_or_default()
                        .contains(&service)
                {
                    return Ok(candidate);
                }
            }
            discover(adapter, service, false)
                .await?
                .context("selected phone not advertising Battery Relay")
        },
    )
    .await?;
    // Both paths selected this device by the configured UUID, never by its name.
    *selected = Some(device.clone());
    let (device_events, adapter_events) =
        bounded("watching the battery link timed out", GATT_TIMEOUT, async {
            Ok((device.events().await?, adapter.events().await?))
        })
        .await?;
    tokio::pin!(device_events, adapter_events);
    if !bounded(
        "checking the selected link timed out",
        GATT_TIMEOUT,
        async { Ok(approved(&device).await) },
    )
    .await?
    {
        bail!("phone disconnected or was blocked during connection");
    }
    let characteristic = bounded(
        "resolving the battery service timed out",
        GATT_TIMEOUT,
        find_characteristic(&device, service),
    )
    .await
    .map_err(|error| error.context(SessionLost("selected battery service is unavailable")))?;
    let values = bounded(
        "subscribing to battery indications timed out",
        GATT_TIMEOUT,
        async {
            characteristic
                .notify()
                .await
                .context("subscribe to unencrypted battery indications")
        },
    )
    .await
    .map_err(|error| error.context(SessionLost("battery subscription failed")))?;
    tokio::pin!(values);
    let initial = bounded("reading the phone battery timed out", GATT_TIMEOUT, async {
        characteristic.read().await.context("read phone battery")
    })
    .await
    .map_err(|error| error.context(SessionLost("phone battery read failed")))?;
    accept_snapshot(&initial, &device, state, epoch, output).await?;
    eprintln!("Unpaired BLE battery subscription active.");
    let mut tick = tokio::time::interval(Duration::from_secs(1));
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        tokio::select! {
            value = values.next() => {
                let value = value.ok_or(SessionLost("battery service disappeared"))?;
                accept_snapshot(&value, &device, state, epoch, output).await?;
            }
            event = device_events.next() => match event {
                None => bail!("phone disappeared"),
                Some(DeviceEvent::PropertyChanged(DeviceProperty::Connected(false)
                    | DeviceProperty::Blocked(true))) => bail!("phone disconnected or blocked"),
                Some(DeviceEvent::PropertyChanged(DeviceProperty::Uuids(uuids)))
                    if !uuids.contains(&service) =>
                        return Err(SessionLost("the connected phone lost its battery service").into()),
                _ => {}
            },
            event = adapter_events.next() => match event {
                None | Some(AdapterEvent::PropertyChanged(AdapterProperty::Powered(false))) => bail!("adapter unavailable"),
                _ => {}
            },
            _ = tick.tick() => {
                if state.expire(epoch.elapsed()).is_some() {
                    output.emit(&Event::Connection { connected: false }).await?;
                    return Err(SessionLost("phone heartbeat expired").into());
                }
            }
        }
    }
}

async fn run(options: Options) -> Result<()> {
    let (session, adapter) = bounded(
        "opening the Bluetooth client timed out",
        GATT_TIMEOUT,
        async {
            let session = bluer::Session::new().await?;
            let adapter = match options.adapter.as_deref() {
                Some(name) => session.adapter(name)?,
                None => session.default_adapter().await?,
            };
            Ok((session, adapter))
        },
    )
    .await?;
    if options.check {
        return check(&adapter).await;
    }
    if !bounded("checking adapter power timed out", GATT_TIMEOUT, async {
        Ok(adapter.is_powered().await?)
    })
    .await?
    {
        bail!("enable Bluetooth before starting");
    }
    if options.discover {
        discover(
            &adapter,
            options.service.context("--service is required")?,
            true,
        )
        .await?;
        return Ok(());
    }
    let service = options.service.context("--service is required")?;
    let output = EventOutput::new(io::stdout(), Duration::from_secs(2))?;
    output.emit(&Event::Connection { connected: false }).await?;
    let mut state = RelayState::default();
    let epoch = Instant::now();
    let mut interrupt = signal(SignalKind::interrupt())?;
    let mut terminate = signal(SignalKind::terminate())?;
    let mut output_tick = tokio::time::interval(Duration::from_secs(1));
    let work = async {
        let mut retry = 1;
        loop {
            let mut selected = None;
            let result =
                receive_session(&adapter, service, &mut state, epoch, &output, &mut selected).await;
            let had_session = state.is_connected();
            if let Some(event) = state.disconnect() {
                output.emit(&event).await?;
            }
            if let Err(error) = result {
                if error.downcast_ref::<io::Error>().is_some() {
                    return Err(error);
                }
                eprintln!("Battery Relay: {error:#}");
                if error.downcast_ref::<SessionLost>().is_some() {
                    if let Some(device) = selected
                        && let Err(recovery) = recover_selected_link(&device).await
                    {
                        eprintln!("Battery Relay: {recovery:#}");
                    }
                    // A fresh process also releases stale BlueR notification
                    // sessions. Quickshell owns the bounded restart delay.
                    return Err(error);
                }
            }
            if !bounded("checking adapter power timed out", GATT_TIMEOUT, async {
                Ok(adapter.is_powered().await?)
            })
            .await?
            {
                bail!("Bluetooth switched off");
            }
            if had_session {
                retry = 1;
            }
            tokio::time::sleep(Duration::from_secs(retry)).await;
            retry = (retry * 2).min(60);
        }
    };
    let result: Result<()> = {
        tokio::pin!(work);
        loop {
            tokio::select! {
                result = &mut work => break result,
                _ = interrupt.recv() => break Ok(()),
                _ = terminate.recv() => break Ok(()),
                _ = output_tick.tick() => if output_closed(libc::STDOUT_FILENO) { break Ok(()); }
            }
        }
    };
    if let Some(event) = state.disconnect() {
        let _ = output.emit(&event).await;
    }
    // StopNotify and our own discovery session are released on drop. Never
    // reset a healthy link on normal shutdown. Link recovery above is separate
    // and restricted to the selected private, unpaired LE device.
    tokio::time::sleep(Duration::from_millis(250)).await;
    drop(session);
    result
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    let options = match Options::parse(std::env::args().skip(1)) {
        Ok(options) => options,
        Err(error) => {
            eprintln!("{error:#}");
            return std::process::ExitCode::from(2);
        }
    };
    if options.help {
        eprint!("{HELP}");
        return std::process::ExitCode::SUCCESS;
    }
    match run(options).await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error)
            if error
                .downcast_ref::<io::Error>()
                .is_some_and(|e| e.kind() == io::ErrorKind::BrokenPipe) =>
        {
            std::process::ExitCode::SUCCESS
        }
        Err(error) => {
            eprintln!("Battery Relay: {error:#}");
            std::process::ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn options(args: &[&str]) -> Result<Options> {
        Options::parse(args.iter().map(|arg| (*arg).to_owned()))
    }

    #[test]
    fn connection_requires_explicit_public_service_not_pairing() {
        assert!(options(&[]).is_err());
        assert!(options(&["--service", "00000000-0000-0000-0000-000000000000"]).is_err());
        assert!(options(&["--service", "invalid"]).is_err());
        assert!(options(&["--check"]).is_ok());
        assert!(options(&["--discover"]).is_err());
        assert!(options(&["--check", "--discover"]).is_err());
        assert!(options(&["--service", "3dc63892-9fc3-4fd9-a665-3fe0b42fd876"]).is_ok());
        assert!(options(&["--check", "--adapter", "../hci0"]).is_err());
    }

    #[test]
    fn discovery_is_le_only_and_scoped_to_the_selected_installation() {
        let service = Uuid::from_u128(0x3dc63892_9fc3_4fd9_a665_3fe0b42fd876);
        let filter = discovery_filter(service);
        assert_eq!(filter.transport, DiscoveryTransport::Le);
        assert_eq!(filter.uuids, [service].into_iter().collect());
        assert!(!filter.duplicate_data);
    }

    #[test]
    fn idle_output_closure_is_detected_without_writing_a_packet() {
        use std::os::{fd::AsRawFd, unix::net::UnixStream};
        let (writer, reader) = UnixStream::pair().unwrap();
        assert!(!output_closed(writer.as_raw_fd()));
        drop(reader);
        assert!(output_closed(writer.as_raw_fd()));
    }

    #[test]
    fn each_output_event_is_a_complete_json_line() {
        let mut output = Vec::new();
        emit(&mut output, &Event::Connection { connected: false }).unwrap();
        assert_eq!(output, b"{\"event\":\"connection\",\"connected\":false}\n");
    }

    #[tokio::test]
    async fn hung_gatt_operation_is_cancelled_and_requires_a_fresh_session() {
        use std::sync::{
            Arc,
            atomic::{AtomicBool, Ordering},
        };
        struct Cancelled(Arc<AtomicBool>);
        impl Drop for Cancelled {
            fn drop(&mut self) {
                self.0.store(true, Ordering::SeqCst);
            }
        }
        let cancelled = Arc::new(AtomicBool::new(false));
        let guard = Cancelled(cancelled.clone());
        let result: Result<()> = bounded(
            "test subscription timed out",
            Duration::from_millis(10),
            async move {
                let _guard = guard;
                std::future::pending().await
            },
        )
        .await;
        assert!(result.unwrap_err().downcast_ref::<SessionLost>().is_some());
        assert!(cancelled.load(Ordering::SeqCst));
    }

    #[tokio::test]
    async fn operation_deadlines_preserve_success_and_real_errors() {
        assert_eq!(
            bounded("unused", Duration::from_secs(1), async { Ok(42) })
                .await
                .unwrap(),
            42
        );
        let error = bounded::<()>("unused", Duration::from_secs(1), async {
            Err(io::Error::from(io::ErrorKind::BrokenPipe).into())
        })
        .await
        .unwrap_err();
        assert_eq!(
            error.downcast_ref::<io::Error>().unwrap().kind(),
            io::ErrorKind::BrokenPipe
        );
        assert!(error.downcast_ref::<SessionLost>().is_none());
    }

    #[tokio::test]
    async fn stalled_output_is_bounded_and_does_not_block_the_reactor() {
        struct Stalled(std::sync::mpsc::Receiver<()>);
        impl Write for Stalled {
            fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
                let _ = self.0.recv();
                Ok(bytes.len())
            }
            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }
        let (release, gate) = std::sync::mpsc::channel();
        let output = EventOutput::new(Stalled(gate), Duration::from_millis(20)).unwrap();
        let result = output.emit(&Event::Connection { connected: false }).await;
        // Closing the test gate releases all writes before the worker exits.
        drop(release);
        assert_eq!(result.unwrap_err().kind(), io::ErrorKind::TimedOut);
    }

    #[test]
    fn closed_consumer_is_an_error_not_a_panic() {
        struct Closed;
        impl Write for Closed {
            fn write(&mut self, _: &[u8]) -> io::Result<usize> {
                Err(io::Error::from(io::ErrorKind::BrokenPipe))
            }
            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }
        assert_eq!(
            emit(&mut Closed, &Event::Connection { connected: false })
                .unwrap_err()
                .kind(),
            io::ErrorKind::BrokenPipe,
        );
    }
}
