//! Owner-scoped staged preflight, ATT inspection, or explicitly enabled pairing.
mod analyze;
mod att;
mod pairing;
use anyhow::{Context, Result};
use battery_relay_fastpair_setup::{
    MODEL_ID, OWNER_HEADSET_TEXT, is_pairing_advertisement, model_public_key,
};
use bluer::{AdapterEvent, DeviceEvent, DeviceProperty, DiscoveryFilter, DiscoveryTransport, Uuid};
use futures::{StreamExt, stream::SelectAll};
use std::{collections::HashSet, time::Duration};

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    model_public_key().context("Validate published model public key")?;
    let mode = std::env::args().nth(1).unwrap_or("check".into());
    if mode == "--help" || mode == "-h" {
        println!(
            "fastpair-setup check | scan | inspect | prepare-le | decode-file CAPTURE\n\
fastpair-setup pair-existing --owner-enabled-pairing --reuse-owned-le-session\n\
Read FAST_PAIR.md first. A saved Account Key MUST be reused, not regenerated.\n\
No reset, bond deletion, firmware or Find Hub operations are implemented."
        );
        return Ok(());
    }
    if mode == "decode-file" {
        return analyze::run(&std::env::args().nth(2).context("Capture path required")?);
    }
    if mode == "check" {
        println!(
            "Public key validated for model {}. No Bluetooth access.",
            hex::encode(MODEL_ID)
        );
        println!(
            "Only a fresh, exact-model pairing advertisement from the pinned headset is accepted."
        );
        return Ok(());
    }
    anyhow::ensure!(
        mode == "scan" || mode == "inspect" || mode == "prepare-le" || mode == "pair-existing",
        "Expected check, scan, inspect, prepare-le or pair-existing"
    );
    if mode == "pair-existing" {
        anyhow::ensure!(
            std::env::args().nth(2).as_deref() == Some("--owner-enabled-pairing"),
            "Physical owner pairing-mode confirmation is required"
        );
    }
    let session = bluer::Session::new().await?;
    let adapter = session.default_adapter().await?;
    anyhow::ensure!(
        adapter.is_powered().await?,
        "Bluetooth off; nothing changed"
    );
    let target = OWNER_HEADSET_TEXT.parse()?;
    let fast_pair = Uuid::from_u128(0x0000fe2c_0000_1000_8000_00805f9b34fb);
    let mut watched = HashSet::new();
    let mut events = SelectAll::new();
    for addr in adapter.device_addresses().await? {
        if addr != target {
            continue;
        }
        let dev = adapter.device(addr)?;
        events.push(dev.events().await?.map(move |evt| (addr, evt)).boxed());
        watched.insert(addr);
    }
    adapter
        .set_discovery_filter(DiscoveryFilter {
            transport: DiscoveryTransport::Le,
            duplicate_data: true,
            ..Default::default()
        })
        .await?;
    let mut matched = false;
    {
        let discovery = adapter.discover_devices().await?;
        tokio::pin!(discovery);
        let deadline = tokio::time::sleep(Duration::from_secs(45));
        tokio::pin!(deadline);
        println!("Listening up to 45 seconds for the owner's headset in pairing mode. No writes.");
        loop {
            let payload = tokio::select! {
                _ = &mut deadline => break,
                _ = tokio::signal::ctrl_c() => break,
                event = discovery.next() => {
                    match event {
                        Some(AdapterEvent::DeviceAdded(addr)) if addr == target && watched.insert(addr) => {
                            let dev = adapter.device(addr)?;
                            events.push(dev.events().await?.map(move |evt| (addr, evt)).boxed());
                            dev.service_data().await?.and_then(|d| d.get(&fast_pair).cloned())
                        },
                        Some(_) => None,
                        None => break,
                    }
                },
                Some((_, event)) = events.next(), if !events.is_empty() => {
                    match event {
                        DeviceEvent::PropertyChanged(DeviceProperty::ServiceData(data)) =>
                            data.get(&fast_pair).cloned(),
                        _ => None,
                    }
                }
            };
            if let Some(payload) = payload
                && is_pairing_advertisement(&payload)
            {
                let dev = adapter.device(target)?;
                println!(
                    "{}",
                    serde_json::json!({
                        "event": "owner_headset_pairing_mode_observed",
                        "model_id": hex::encode(MODEL_ID),
                        "matches_pinned_identity": true,
                        "address_type": format!("{:?}", dev.address_type().await?),
                        "paired": dev.is_paired().await?,
                        "connected": dev.is_connected().await?,
                        "gatt_write_performed": false,
                        "bond_removed": false
                    })
                );
                matched = true;
                break;
            }
        }
    }
    tokio::time::sleep(Duration::from_millis(300)).await;
    println!("Discovery released. Pairing advertisement observed: {matched}.");
    if mode == "inspect" || mode == "prepare-le" {
        anyhow::ensure!(
            matched,
            "No fresh owner pairing advertisement; no connection attempted"
        );
        let device = adapter.device(target)?;
        anyhow::ensure!(
            !device.is_connected().await?,
            "Do not interrupt an existing connection"
        );
        let result = att::inspect(adapter.address().await?, target).await;
        if mode == "inspect" && device.is_connected().await.unwrap_or(false) {
            let _ = tokio::time::timeout(Duration::from_secs(5), device.disconnect()).await;
        }
        result?;
        if mode == "prepare-le" {
            tokio::time::timeout(Duration::from_secs(8), device.services()).await??;
            println!(
                "Diagnostic LE session left to BlueZ for the explicitly authorized pairing step."
            );
        }
    }
    if mode == "pair-existing" {
        anyhow::ensure!(
            matched,
            "No fresh owner model advertisement: no pairing attempted"
        );
        pairing::run(&session, &adapter).await?;
    }
    Ok(())
}
