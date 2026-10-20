//! Owner-authorized, one-shot Fast Pair via the system BlueZ GATT API.
//! No automatic retries, bond deletion, default-agent changes or Find Hub calls.
use anyhow::{Context, Result, ensure};
use battery_relay_fastpair_setup::{
    Handshake, MODEL_ID, OWNER_HEADSET, OWNER_HEADSET_TEXT, account_key_path,
};
use bluer::{
    Adapter, Device, Session, Uuid,
    agent::{Agent, ReqError},
    gatt::{
        WriteOp,
        remote::{Characteristic, CharacteristicWriteRequest},
    },
};
use futures::{Stream, StreamExt};
use rand_core::{OsRng, RngCore};
use std::{
    collections::HashMap,
    fs::{File, OpenOptions},
    io::Write,
    os::unix::fs::{OpenOptionsExt, PermissionsExt},
    pin::Pin,
    sync::Arc,
    time::Duration,
};
use tokio::{sync::Mutex, time::timeout};
use zeroize::Zeroizing;

type Notifications = Pin<Box<dyn Stream<Item = Vec<u8>> + Send>>;

fn uuid(part: u16) -> Uuid {
    Uuid::from_u128(
        (u128::from(0xfe2c0000u32 | u32::from(part)) << 96) | 0x8366_4814_8eb0_01de_3210_0bea,
    )
}

async fn write(characteristic: &Characteristic, part: u16, value: &[u8]) -> Result<()> {
    let expected_len = match part {
        0x1234 => 80,
        0x1235 | 0x1236 => 16,
        _ => anyhow::bail!("Write outside the three pairing characteristics is forbidden"),
    };
    ensure!(
        characteristic.uuid().await? == uuid(part) && value.len() == expected_len,
        "Characteristic identity/length mismatch"
    );
    timeout(
        Duration::from_secs(4),
        characteristic.write_ext(
            value,
            &CharacteristicWriteRequest {
                op_type: WriteOp::Request,
                ..Default::default()
            },
        ),
    )
    .await
    .context("GATT write timeout")??;
    Ok(())
}

async fn next_notification(stream: &mut Notifications) -> Result<Vec<u8>> {
    timeout(Duration::from_secs(7), stream.next())
        .await
        .context("Fast Pair notification timeout")?
        .context("Fast Pair notification session closed")
}

async fn is_bonded(adapter: &Adapter, device: &Device) -> Result<bool> {
    use dbus::nonblock::{Proxy, stdintf::org_freedesktop_dbus::Properties};
    let (resource, connection) = dbus_tokio::connection::new_system_sync()?;
    let task = tokio::spawn(resource);
    let path = format!(
        "/org/bluez/{}/dev_{}",
        adapter.name(),
        device.address().to_string().replace(':', "_")
    );
    let proxy = Proxy::new("org.bluez", path, Duration::from_secs(2), connection);
    let value = proxy.get("org.bluez.Device1", "Bonded").await;
    task.abort();
    Ok(value?)
}

struct Exchange {
    handshake: Handshake,
    passkey: Characteristic,
    passkey_notifications: Notifications,
}

async fn attempt(session: &Session, adapter: &Adapter, device: &Device) -> Result<()> {
    let key_path = account_key_path()?;
    ensure!(
        !key_path.exists(),
        "An earlier PC key exists: refuse to create/write another"
    );
    let parent = key_path.parent().context("Key path has no parent")?;
    ensure!(
        parent.metadata()?.permissions().mode() & 0o077 == 0,
        "Key directory must be owner-only"
    );
    ensure!(
        device.is_connected().await?,
        "An owner-confirmed LE session is required"
    );
    let services = timeout(Duration::from_secs(8), device.services())
        .await
        .context("BlueZ service discovery timeout")??;
    let mut chars = HashMap::new();
    for service in services {
        if service.uuid().await? == Uuid::from_u128(0x0000fe2c_0000_1000_8000_00805f9b34fb) {
            for characteristic in service.characteristics().await? {
                chars.insert(characteristic.uuid().await?, characteristic);
            }
        }
    }
    let model = chars
        .get(&uuid(0x1233))
        .context("No GFPS model characteristic")?;
    ensure!(model.read().await? == MODEL_ID, "Unexpected model");
    let kbp = chars
        .get(&uuid(0x1234))
        .context("No key-based pairing characteristic")?;
    let passkey = chars
        .get(&uuid(0x1235))
        .context("No passkey characteristic")?;
    let account = chars
        .get(&uuid(0x1236))
        .context("No account-key characteristic")?;
    ensure!(
        kbp.mtu().await? >= 83,
        "MTU too small: no long-write fallback"
    );
    ensure!(
        kbp.flags().await?.write
            && kbp.flags().await?.notify
            && passkey.flags().await?.write
            && passkey.flags().await?.notify
            && account.flags().await?.write,
        "GFPS permissions mismatch"
    );
    let mut kbp_notifications: Notifications = kbp.notify().await?.boxed();
    let passkey_notifications = passkey.notify().await?.boxed();
    println!("System-managed GATT model, MTU and notification sessions verified.");
    let exchange = Arc::new(Mutex::new(Exchange {
        handshake: Handshake::new()?,
        passkey: passkey.clone(),
        passkey_notifications,
    }));
    let agent_exchange = exchange.clone();
    let expected_adapter = adapter.name().to_owned();
    let expected_address = device.address();
    let _agent = session
        .register_agent(Agent {
            request_default: false,
            request_confirmation: Some(Box::new(move |request| {
                let exchange = agent_exchange.clone();
                let allowed =
                    request.adapter == expected_adapter && request.device == expected_address;
                Box::pin(async move {
                    if !allowed {
                        return Err(ReqError::Rejected);
                    }
                    let verified: Result<()> = async {
                        let mut state = exchange.lock().await;
                        let payload = state.handshake.passkey_request(request.passkey)?;
                        write(&state.passkey, 0x1235, &payload).await?;
                        let response = next_notification(&mut state.passkey_notifications).await?;
                        state.handshake.accept_passkey(&response, request.passkey)?;
                        println!("Encrypted numeric comparison verified for the owner's headset.");
                        Ok(())
                    }
                    .await;
                    if let Err(error) = verified {
                        eprintln!("Numeric comparison rejected: {error:#}");
                        return Err(ReqError::Rejected);
                    }
                    Ok(())
                })
            })),
            ..Default::default()
        })
        .await?;
    {
        let mut state = exchange.lock().await;
        let request = state.handshake.request_le(OWNER_HEADSET);
        println!("Sending one key-based pairing request; no persistent key written yet.");
        write(kbp, 0x1234, &request).await?;
        let response = next_notification(&mut kbp_notifications).await?;
        state.handshake.accept_le_response(&response)?;
        println!("Encrypted response verifies the pinned identity and single-primary LE bonding.");
    }
    timeout(Duration::from_secs(20), device.pair())
        .await
        .context("Bluetooth pairing timeout")?
        .context("BlueZ pairing did not complete; no bond was removed")?;
    ensure!(
        device.is_paired().await? && is_bonded(adapter, device).await?,
        "Bond not established"
    );
    let mut state = exchange.lock().await;
    let mut account_key = Zeroizing::new([0u8; 16]);
    OsRng.fill_bytes(&mut *account_key);
    account_key[0] = 4;
    let encrypted = state.handshake.encrypt_account_key(&account_key, true)?;
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&key_path)?;
    file.write_all(&*account_key)?;
    file.sync_all()?;
    File::open(parent)?.sync_all()?;
    println!("New PC key saved privately. Attempting exactly one Account Key write.");
    write(account, 0x1236, &encrypted).await.context(
        "Account Key write unconfirmed: preserve saved key; never generate another automatically",
    )?;
    println!("Account Key write acknowledged. BATT decryption still requires validation.");
    Ok(())
}

pub async fn run(session: &Session, adapter: &Adapter) -> Result<()> {
    let device = adapter.device(OWNER_HEADSET_TEXT.parse()?)?;
    ensure!(
        std::env::args().nth(3).as_deref() == Some("--reuse-owned-le-session"),
        "The caller must confirm this is the diagnostic LE session, not a user's audio session"
    );
    let result = tokio::select! {
        result = attempt(session,adapter,&device) => result,
        _ = tokio::signal::ctrl_c() => Err(anyhow::anyhow!("Pairing canceled")),
    };
    tokio::time::sleep(Duration::from_millis(300)).await;
    if device.is_connected().await.unwrap_or(false) {
        match timeout(Duration::from_secs(5), device.disconnect()).await {
            Ok(Ok(())) => {}
            Ok(Err(error)) => eprintln!("Cleanup disconnect failed: {error}"),
            Err(error) => eprintln!("Cleanup disconnect timeout: {error}"),
        }
    }
    result
}
