//! Scoped native Linux ATT client. No root, HCI raw socket, profile connection,
//! adapter changes or bond operations. This module is now read-only; live
//! pairing uses the managed BlueZ GATT API in pairing.rs.
use anyhow::{Context, Result, bail, ensure};
use bluer::{
    Address, AddressType, Uuid,
    l2cap::{SeqPacket, Socket, SocketAddr},
};
use std::time::Duration;
use tokio::time::timeout;

pub struct Att {
    socket: SeqPacket,
}

#[derive(Clone, Debug)]
pub struct Characteristic {
    pub declaration: u16,
    pub handle: u16,
    pub properties: u8,
    pub uuid: Uuid,
}

/// ATT is bidirectional: the headset may discover this diagnostic client's
/// (empty) attribute server while we await a response. Return the standard
/// attribute-not-found / write-not-permitted response, never treating an
/// incoming request as our own response. No PC data/services are exported.
fn peer_request_reply(packet: &[u8]) -> Option<Vec<u8>> {
    let opcode = *packet.first()?;
    if opcode == 2 && packet.len() == 3 {
        return Some(vec![3, 185, 0]);
    }
    let error = match opcode {
        0x04 | 0x06 | 0x08 | 0x10 if packet.len() >= 5 => 0x0a,
        0x0a | 0x0c | 0x0e if packet.len() >= 3 => 0x01,
        0x12 | 0x16 if packet.len() >= 3 => 0x03,
        0x18 if packet.len() == 2 => return Some(vec![1, opcode, 0, 0, 3]),
        // ATT commands do not receive a response; an empty reply means ignore.
        0x52 | 0xd2 => return Some(vec![]),
        _ => return None,
    };
    Some(vec![1, opcode, packet[1], packet[2], error])
}

impl Att {
    pub async fn connect(local: Address, remote: Address) -> Result<Self> {
        let socket = Socket::<SeqPacket>::new_seq_packet().context("Create ATT socket")?;
        socket
            .bind(SocketAddr {
                addr: local,
                addr_type: AddressType::LePublic,
                psm: 0,
                cid: 4,
            })
            .context("Bind ATT socket to local adapter")?;
        let socket = timeout(
            Duration::from_secs(12),
            socket.connect(SocketAddr {
                addr: remote,
                addr_type: AddressType::LePublic,
                psm: 0,
                cid: 4,
            }),
        )
        .await
        .context("LE ATT connection timed out")?
        .context("Establish native LE ATT channel")?;
        Ok(Self { socket })
    }

    pub async fn request(&self, request: &[u8], response_type: u8) -> Result<Vec<u8>> {
        ensure!(
            !request.is_empty() && matches!(request[0], 0x04 | 0x06 | 0x08 | 0x0a),
            "Only read-only ATT discovery is allowed"
        );
        self.socket.send(request).await?;
        timeout(Duration::from_secs(4), async {
            loop {
                let mut response = vec![0; 65535];
                let len = self.socket.recv(&mut response).await?;
                ensure!(len > 0, "ATT disconnected");
                response.truncate(len);
                if let Some(reply) = peer_request_reply(&response) {
                    if !reply.is_empty() {
                        self.socket.send(&reply).await?;
                    }
                    continue;
                }
                match response[0] {
                    0x1d => {
                        self.socket.send(&[0x1e]).await?;
                    }
                    0x1b => {}
                    0x01 if len == 5 && response[1] == request[0] => return Ok(response),
                    code if code == response_type => return Ok(response),
                    code => bail!("Unexpected ATT response opcode {code:#x}"),
                }
            }
        })
        .await
        .context("ATT read timed out")?
    }

    pub async fn fast_pair_service(&self) -> Result<(u16, u16)> {
        let response = self
            .request(&[0x06, 1, 0, 0xff, 0xff, 0, 0x28, 0x2c, 0xfe], 0x07)
            .await?;
        ensure!(
            response[0] == 7 && response.len() == 5,
            "No unique Fast Pair service"
        );
        Ok((
            u16::from_le_bytes([response[1], response[2]]),
            u16::from_le_bytes([response[3], response[4]]),
        ))
    }

    pub async fn characteristics(&self, first: u16, last: u16) -> Result<Vec<Characteristic>> {
        let mut current = first;
        let mut result = Vec::new();
        for _ in 0..32 {
            let mut request = vec![8];
            request.extend(current.to_le_bytes());
            request.extend(last.to_le_bytes());
            request.extend([3, 0x28]);
            let response = self.request(&request, 9).await?;
            if response[0] == 1 {
                ensure!(
                    response[4] == 10,
                    "GATT characteristic discovery error {}",
                    response[4]
                );
                return Ok(result);
            }
            ensure!(response.len() >= 2, "Truncated ATT response");
            let length = usize::from(response[1]);
            ensure!(
                matches!(length, 7 | 21) && (response.len() - 2).is_multiple_of(length),
                "Invalid characteristic declaration"
            );
            for item in response[2..].chunks(length) {
                let declaration = u16::from_le_bytes([item[0], item[1]]);
                let handle = u16::from_le_bytes([item[3], item[4]]);
                ensure!(
                    declaration >= current && handle > declaration && handle <= last,
                    "Invalid characteristic handles"
                );
                let uuid = if length == 21 {
                    let mut bytes: [u8; 16] = item[5..].try_into()?;
                    bytes.reverse();
                    Uuid::from_bytes(bytes)
                } else {
                    Uuid::from_u128(
                        (u128::from(u16::from_le_bytes([item[5], item[6]])) << 96)
                            | 0x0000_1000_8000_0080_5f9b_34fb,
                    )
                };
                result.push(Characteristic {
                    declaration,
                    handle,
                    properties: item[2],
                    uuid,
                });
                current = handle.saturating_add(1);
            }
            if current > last {
                return Ok(result);
            }
        }
        bail!("Bounded characteristic-discovery limit reached")
    }

    pub async fn read(&self, handle: u16) -> Result<Vec<u8>> {
        let mut request = vec![0x0a];
        request.extend(handle.to_le_bytes());
        let response = self.request(&request, 0x0b).await?;
        ensure!(response[0] == 0x0b, "GATT read rejected");
        Ok(response[1..].to_vec())
    }
}

pub async fn inspect(local: Address, target: Address) -> Result<()> {
    let att = Att::connect(local, target).await?;
    println!("Dedicated LE ATT connection established; no audio profiles requested.");
    let (first, last) = att.fast_pair_service().await?;
    println!("Fast Pair service found: {first:#06x}..{last:#06x}");
    let characteristics = att.characteristics(first, last).await?;
    for characteristic in &characteristics {
        println!(
            "{}",
            serde_json::json!({
                "uuid": characteristic.uuid.to_string(), "handle": characteristic.handle,
                "declaration": characteristic.declaration, "properties": characteristic.properties,
            })
        );
    }
    let model = characteristics
        .iter()
        .find(|c| c.uuid == Uuid::from_u128(0xfe2c1233_8366_4814_8eb0_01de32100bea))
        .context("Model ID characteristic absent; stop")?;
    let model_id = att.read(model.handle).await?;
    ensure!(
        model_id == battery_relay_fastpair_setup::MODEL_ID,
        "GATT model does not match published key"
    );
    println!("GATT Model ID matches the expected model. No attribute or key written.");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::peer_request_reply;

    #[test]
    fn incoming_read_request_is_answered_not_mistaken_for_response() {
        assert_eq!(
            peer_request_reply(&[8, 1, 0, 255, 255, 0, 0x28]),
            Some(vec![1, 8, 1, 0, 10])
        );
        assert_eq!(
            peer_request_reply(&[0x10, 1, 0, 255, 255, 0, 0x28]),
            Some(vec![1, 0x10, 1, 0, 10])
        );
        assert_eq!(
            peer_request_reply(&[0x0a, 1, 0]),
            Some(vec![1, 0x0a, 1, 0, 1])
        );
    }

    #[test]
    fn peer_cannot_write_any_local_attribute() {
        assert_eq!(
            peer_request_reply(&[0x12, 1, 0, 0xaa]),
            Some(vec![1, 0x12, 1, 0, 3])
        );
        assert_eq!(peer_request_reply(&[0x52, 1, 0, 0xaa]), Some(vec![]));
    }

    #[test]
    fn actual_responses_and_notifications_remain_client_messages() {
        for packet in [
            vec![0x13],
            vec![9, 7, 1, 0, 2, 2, 0, 0, 0x28],
            vec![0x1b, 4, 0x0c, 1, 2, 3],
            vec![1, 0x12, 4, 0x0c, 5],
        ] {
            assert_eq!(peer_request_reply(&packet), None);
        }
    }
}
