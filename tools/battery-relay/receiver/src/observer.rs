//! Shared passive observation for phone/Fitbit and earbuds. No active scan.
use crate::{
    Event,
    clock::boot_time,
    output::{EventOutput, output_closed},
    passive,
};
use anyhow::{Context, Result, ensure};
use bluer::{
    Uuid,
    monitor::{MonitorEvent, Pattern},
};
use dbus::{
    arg::{ArgType, PropMap, RefArg, prop_cast},
    message::MatchRule,
    nonblock::{Proxy, stdintf::org_freedesktop_dbus::Properties},
};
use futures::StreamExt;
use std::{
    collections::HashMap,
    io,
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

pub const REFRESH_AFTER: Duration = Duration::from_secs(30);
#[derive(Default)]
pub struct Options {
    pub adapter: Option<String>,
    pub duration: Option<Duration>,
    pub check: bool,
}
pub trait Source {
    fn found(
        &mut self,
        path: String,
        data: Option<&[u8]>,
        heard: Duration,
        observed: u64,
    ) -> Result<()>;
    fn update(&mut self, path: &str, data: Option<&[u8]>, heard: Duration, observed: u64);
    fn lost(&mut self, path: &str);
    fn event(&self, received_at: u64) -> Event;
}
fn wall_ms() -> Result<u64> {
    Ok(SystemTime::now()
        .duration_since(UNIX_EPOCH)?
        .as_millis()
        .try_into()?)
}
fn unvariant(value: &dyn RefArg) -> Option<&dyn RefArg> {
    if value.arg_type() == ArgType::Variant {
        value.as_iter()?.next()
    } else {
        Some(value)
    }
}
fn service_bytes(properties: &PropMap, service: Uuid) -> Option<Vec<u8>> {
    let data = properties.get("ServiceData")?;
    let mut entries = data.0.as_iter()?;
    while let (Some(key), Some(value)) = (entries.next(), entries.next()) {
        if key.as_str() != Some(service.to_string().as_str()) {
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
    Reading(String, Vec<u8>, Duration, u64),
    DeviceRemoved(String),
    Unavailable(&'static str),
}
fn unavailable(send: &mpsc::Sender<RadioEvent>, overflow: &AtomicBool, reason: &'static str) {
    // A full data queue must not swallow an adapter-off/daemon-loss event.
    if send.try_send(RadioEvent::Unavailable(reason)).is_err() {
        overflow.store(true, Ordering::Relaxed);
    }
}
fn forward(
    path: String,
    properties: &PropMap,
    service: Uuid,
    send: &mpsc::Sender<RadioEvent>,
    overflow: &AtomicBool,
) {
    let Some(data) = service_bytes(properties, service) else {
        return;
    };
    if let (Ok(now), Ok(wall)) = (boot_time(), wall_ms())
        && send
            .try_send(RadioEvent::Reading(path, data, now, wall))
            .is_err()
    {
        overflow.store(true, Ordering::Relaxed);
    }
}

const MONITOR_TIMEOUT: Duration = Duration::from_secs(15);

async fn check_monitor_support(
    connection: &Arc<dbus::nonblock::SyncConnection>,
    adapter: &str,
) -> Result<()> {
    let proxy = Proxy::new(
        "org.bluez",
        format!("/org/bluez/{adapter}"),
        Duration::from_secs(3),
        connection.clone(),
    );
    let types: Vec<String> = proxy.get(passive::MANAGER, "SupportedMonitorTypes").await
        .context("Passive advertisement monitoring unavailable: enable hardware.bluetooth.settings.General.Experimental = true and activate/restart BlueZ. No active scan fallback")?;
    ensure!(
        types.iter().any(|t| t == "or_patterns"),
        "BlueZ does not support passive or-pattern monitoring"
    );
    Ok(())
}

pub async fn observe(
    options: Options,
    service: Uuid,
    patterns: Vec<Pattern>,
    mut state: impl Source,
) -> Result<()> {
    let session = tokio::time::timeout(MONITOR_TIMEOUT, bluer::Session::new())
        .await
        .context("Opening BlueZ timed out")??;
    let adapter = match options.adapter {
        Some(ref name) => session.adapter(name)?,
        None => session.default_adapter().await?,
    };
    ensure!(
        tokio::time::timeout(Duration::from_secs(3), adapter.is_powered())
            .await
            .context("Adapter check timed out")??,
        "Bluetooth is off"
    );
    let prefix = format!("/org/bluez/{}/dev_", adapter.name());
    let (resource, connection) = dbus_tokio::connection::new_system_sync()?;
    let resource_task = tokio::spawn(resource);
    struct Abort<T>(tokio::task::JoinHandle<T>);
    impl<T> Drop for Abort<T> {
        fn drop(&mut self) {
            self.0.abort();
        }
    }
    let mut resource = Abort(resource_task);
    let overflow = Arc::new(AtomicBool::new(false));
    let (send, mut receive) = mpsc::channel(32);
    let (send1, overflow1, prefix1) = (send.clone(), overflow.clone(), prefix.clone());
    // Subscribe before monitor registration. Cached device properties alone
    // cannot establish presence: the source requires our live DeviceFound.
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
                    forward(
                        message.path().unwrap().to_string(),
                        &properties,
                        service,
                        &send1,
                        &overflow1,
                    );
                } else if interface == "org.bluez.Adapter1"
                    && prop_cast::<bool>(&properties, "Powered") == Some(&false)
                {
                    unavailable(&send1, &overflow1, "Bluetooth switched off");
                }
                true
            },
        );
    let (send2, overflow2) = (send.clone(), overflow.clone());
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
                    forward(path.to_string(), properties, service, &send2, &overflow2);
                }
                true
            },
        );
    let (send3, overflow3) = (send.clone(), overflow.clone());
    let adapter_path = format!("/org/bluez/{}", adapter.name());
    let device_prefix = format!("{adapter_path}/dev_");
    let removed = connection
        .add_match(
            MatchRule::new_signal("org.freedesktop.DBus.ObjectManager", "InterfacesRemoved")
                .with_sender("org.bluez"),
        )
        .await?
        .cb(
            move |_, (path, interfaces): (dbus::Path<'static>, Vec<String>)| {
                if path.as_ref() == adapter_path
                    && interfaces.iter().any(|i| i == "org.bluez.Adapter1")
                {
                    unavailable(&send3, &overflow3, "Bluetooth adapter removed");
                } else if path.starts_with(&device_prefix)
                    && interfaces.iter().any(|i| i == "org.bluez.Device1")
                    && send3
                        .try_send(RadioEvent::DeviceRemoved(path.to_string()))
                        .is_err()
                {
                    overflow3.store(true, Ordering::Relaxed);
                }
                true
            },
        );
    let (send4, overflow4) = (send, overflow.clone());
    let owner = connection
        .add_match(
            MatchRule::new_signal("org.freedesktop.DBus", "NameOwnerChanged")
                .with_sender("org.freedesktop.DBus"),
        )
        .await?
        .cb(move |_, (name, old, new): (String, String, String)| {
            if name == "org.bluez" && old != new {
                unavailable(
                    &send4,
                    &overflow4,
                    "Bluetooth daemon changed; new session required",
                );
            }
            true
        });
    let output = EventOutput::new(io::stdout(), Duration::from_secs(2))?;
    let mut unavailable_event = state.event(0);
    output.emit(&state.event(wall_ms()?)).await?;
    check_monitor_support(&connection, adapter.name()).await?;
    if options.check {
        eprintln!("Passive monitoring supported; no monitor, discovery or connection started.");
        return Ok(());
    }
    let manager = tokio::time::timeout(MONITOR_TIMEOUT, adapter.monitor())
        .await
        .context("Passive monitor registration timed out")??;
    let mut monitor = tokio::time::timeout(
        MONITOR_TIMEOUT,
        manager.register(passive::monitor(patterns)),
    )
    .await
    .context("Passive monitor activation timed out")??;
    eprintln!("Passive advertisement monitor active; no discovery or connection.");
    let mut shown = state.event(0);
    let mut last_emit = Duration::ZERO;
    let mut stop = signal(SignalKind::terminate())?;
    let mut interrupt = signal(SignalKind::interrupt())?;
    let mut tick = tokio::time::interval(Duration::from_secs(1));
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let duration = options.duration.unwrap_or(Duration::MAX);
    let start = boot_time()?;
    let mut last_health = start;
    let mut last_loop = start;
    let work: Result<()> = {
        loop {
            tokio::select! {
                _=stop.recv()=>break Ok(()),
                _=interrupt.recv()=>break Ok(()),
                _=&mut resource.0=>break Err(anyhow::anyhow!("Bluetooth signal connection lost")),
                event=receive.recv()=>match event {
                    Some(RadioEvent::Reading(path,reading,heard,wall))=>{
                        state.update(&path,Some(&reading),heard,wall);
                    },
                    Some(RadioEvent::Unavailable(reason))=>break Err(anyhow::anyhow!(reason)),
                    Some(RadioEvent::DeviceRemoved(path))=>{ state.lost(&path); },
                    None=>break Err(anyhow::anyhow!("Battery signal stream closed")),
                },
                event=monitor.next()=>match event {
                    Some(MonitorEvent::DeviceFound(device)) if device.adapter == adapter.name()=>{
                        let path = format!("/org/bluez/{}/dev_{}", adapter.name(), device.device.to_string().replace(':', "_"));
                        let heard = boot_time()?;
                        let observed = wall_ms()?;
                        // DeviceFound is a live pattern match. Only then read
                        // the corresponding content; never enumerate old cache
                        // entries or poll them to invent observations.
                        let remote = adapter.device(device.device)?;
                        // A rotating address can disappear before this read.
                        // Do not withdraw unrelated case/bud sources because of
                        // that race. Bus/monitor loss has its own fatal path.
                        let data = tokio::time::timeout(Duration::from_secs(3), remote.service_data()).await
                            .ok().and_then(Result::ok).flatten();
                        let reading = data.as_ref().and_then(|v| v.get(&service));
                        state.found(path, reading.map(Vec::as_slice), heard, observed)?;
                    },
                    Some(MonitorEvent::DeviceLost(device)) if device.adapter == adapter.name()=>{
                        state.lost(&format!("/org/bluez/{}/dev_{}", adapter.name(), device.device.to_string().replace(':', "_")));
                    },
                    None=>break Err(anyhow::anyhow!("Passive monitor released; a new session is required")),
                    _=>{}
                },
                _=tick.tick()=>{
                    if output_closed(libc::STDOUT_FILENO) {break Ok(());}
                    if overflow.load(Ordering::Relaxed) {break Err(anyhow::anyhow!("Battery event queue overflow"));}
                    if boot_time()?.saturating_sub(start)>=duration {break Ok(());}
                    if boot_time()?.saturating_sub(last_health)>=REFRESH_AFTER {
                        let powered = tokio::time::timeout(Duration::from_secs(3), adapter.is_powered()).await
                            .context("Passive monitor health check timed out")??;
                        ensure!(powered, "Bluetooth switched off");
                        last_health = boot_time()?;
                    }
                }
            }
            let now = boot_time()?;
            if passive::observation_loop_expired(last_loop, now) {
                break Err(anyhow::anyhow!(
                    "Passive observation paused/suspended; reacquiring live presence"
                ));
            }
            last_loop = now;
            let report = state.event(wall_ms()?);
            if !shown.same_values(&report) || now.saturating_sub(last_emit) >= REFRESH_AFTER {
                output.emit(&report).await?;
                shown = report;
                last_emit = now;
            }
        }
    };
    drop(monitor);
    drop(manager);
    match &mut unavailable_event {
        Event::Relay { received_at, .. } | Event::Earbuds { received_at, .. } => {
            *received_at = wall_ms()?
        }
    }
    let _ = output.emit(&unavailable_event).await;
    let _ = connection.remove_match(properties.token()).await;
    let _ = connection.remove_match(added.token()).await;
    let _ = connection.remove_match(removed.token()).await;
    let _ = connection.remove_match(owner.token()).await;
    tokio::time::sleep(Duration::from_millis(250)).await;
    work
}

#[cfg(test)]
mod tests {
    use super::*;
    use dbus::arg::Variant;
    #[test]
    fn a_full_queue_cannot_hide_adapter_loss() {
        let (send, _receive) = mpsc::channel(1);
        let overflow = AtomicBool::new(false);
        unavailable(&send, &overflow, "off");
        assert!(!overflow.load(Ordering::Relaxed));
        unavailable(&send, &overflow, "removed");
        assert!(overflow.load(Ordering::Relaxed));
    }
    #[test]
    fn service_data_requires_exact_uuid_and_bounded_bytes() {
        let uuid = Uuid::from_u128(0xe167a6ba_8246_4729_8ae6_4f1ecde39e1c);
        let data: HashMap<String, Variant<Vec<u8>>> =
            [(uuid.to_string(), Variant(vec![2, 73, 7]))].into();
        let p: PropMap = [(
            "ServiceData".into(),
            Variant(Box::new(data) as Box<dyn RefArg>),
        )]
        .into();
        assert_eq!(service_bytes(&p, uuid), Some(vec![2, 73, 7]));
        assert_eq!(service_bytes(&p, Uuid::nil()), None);
        assert_eq!(service_bytes(&PropMap::new(), uuid), None);
    }
}
