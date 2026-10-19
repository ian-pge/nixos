//! The small wire protocol and relay lifecycle, independent of a Bluetooth radio.

use serde::Serialize;
use std::{fmt, time::Duration};

pub const SNAPSHOT_UUID: bluer::Uuid =
    bluer::Uuid::from_u128(0xd973f2e0_b19e_4f19_9a67_6c414c65f802);
pub const PACKET_LEN: usize = 12;
pub const JS_MAX_SAFE_INTEGER: u64 = 9_007_199_254_740_991;
/// A sender sends an unchanged snapshot every minute. This also detects an app
/// disappearing while an unrelated classic Bluetooth connection stays alive.
pub const SESSION_TIMEOUT: Duration = Duration::from_secs(180);

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum DeviceKind {
    Phone,
    Fitbit,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Snapshot {
    pub device: DeviceKind,
    pub percent: Option<u8>,
    pub plugged_in: Option<bool>,
    pub charging: Option<bool>,
    pub updated_at: u64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DecodeError {
    Length,
    Version,
    Device,
    Percent,
    Flags,
    Timestamp,
}

impl fmt::Display for DecodeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "invalid battery packet: {self:?}")
    }
}

impl std::error::Error for DecodeError {}

impl Snapshot {
    pub fn decode(bytes: &[u8]) -> Result<Self, DecodeError> {
        if bytes.len() != PACKET_LEN {
            return Err(DecodeError::Length);
        }
        if bytes[0] != 1 {
            return Err(DecodeError::Version);
        }
        let device = match bytes[1] {
            1 => DeviceKind::Phone,
            2 => DeviceKind::Fitbit,
            _ => return Err(DecodeError::Device),
        };
        let percent = match bytes[2] {
            0..=100 => Some(bytes[2]),
            255 => None,
            _ => return Err(DecodeError::Percent),
        };
        let flags = bytes[3];
        // Unknown means unknown, never an implicit false or an invented value.
        if flags & 0xf0 != 0 || flags & 3 == 2 || flags & 12 == 8 {
            return Err(DecodeError::Flags);
        }
        let updated_at = u64::from_be_bytes(bytes[4..12].try_into().unwrap());
        if updated_at == 0 || updated_at > JS_MAX_SAFE_INTEGER {
            return Err(DecodeError::Timestamp);
        }
        Ok(Self {
            device,
            percent,
            plugged_in: (flags & 1 != 0).then_some(flags & 2 != 0),
            charging: (flags & 4 != 0).then_some(flags & 8 != 0),
            updated_at,
        })
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(tag = "event", rename_all = "lowercase")]
pub enum Event {
    Connection {
        connected: bool,
    },
    Battery {
        device: DeviceKind,
        percent: Option<u8>,
        #[serde(rename = "pluggedIn")]
        plugged_in: Option<bool>,
        charging: Option<bool>,
        #[serde(rename = "updatedAt")]
        updated_at: u64,
        #[serde(rename = "receivedAt")]
        received_at: u64,
    },
}

/// `connected` means an authorized app has actually sent a packet, not merely
/// that an unrelated audio profile has a Bluetooth connection to the same phone.
#[derive(Default)]
pub struct RelayState {
    last_received: Option<Duration>,
}

impl RelayState {
    pub fn is_connected(&self) -> bool {
        self.last_received.is_some()
    }

    pub fn receive(&mut self, packet: Snapshot, now: Duration, received_at: u64) -> Vec<Event> {
        let mut events = Vec::with_capacity(2);
        // Fitbit's cloud snapshot may be old. Only a phone snapshot proves the
        // Android sender is alive; a Fitbit packet cannot start/extend a session.
        if packet.device == DeviceKind::Fitbit && self.last_received.is_none() {
            return events;
        }
        if self.last_received.is_none() {
            events.push(Event::Connection { connected: true });
        }
        if packet.device == DeviceKind::Phone {
            self.last_received = Some(now);
        }
        events.push(Event::Battery {
            device: packet.device,
            percent: packet.percent,
            plugged_in: packet.plugged_in,
            charging: packet.charging,
            updated_at: packet.updated_at,
            received_at,
        });
        events
    }

    pub fn disconnect(&mut self) -> Option<Event> {
        self.last_received
            .take()
            .map(|_| Event::Connection { connected: false })
    }

    pub fn expire(&mut self, now: Duration) -> Option<Event> {
        if self
            .last_received
            .is_some_and(|last| now.saturating_sub(last) >= SESSION_TIMEOUT)
        {
            self.disconnect()
        } else {
            None
        }
    }
}

/// Local link policy only; the public service identifier is not authentication.
pub fn link_usable(connected: bool, blocked: bool) -> bool {
    connected && !blocked
}

#[cfg(test)]
mod tests {
    use super::*;

    const VECTOR: [u8; 12] = [1, 1, 73, 7, 0, 0, 1, 0x8b, 0xcf, 0xe5, 0x68, 0];

    #[test]
    fn shared_android_vector() {
        assert_eq!(
            Snapshot::decode(&VECTOR).unwrap(),
            Snapshot {
                device: DeviceKind::Phone,
                percent: Some(73),
                plugged_in: Some(true),
                charging: Some(false),
                updated_at: 1_700_000_000_000,
            }
        );
    }

    #[test]
    fn rejects_bad_lengths() {
        for length in [0, 1, 11, 13, 20, 512] {
            assert_eq!(Snapshot::decode(&vec![0; length]), Err(DecodeError::Length));
        }
    }

    #[test]
    fn rejects_unknown_versions_and_devices() {
        for version in [0, 2, 255] {
            let mut bytes = VECTOR;
            bytes[0] = version;
            assert_eq!(Snapshot::decode(&bytes), Err(DecodeError::Version));
        }
        for kind in [0, 3, 255] {
            let mut bytes = VECTOR;
            bytes[1] = kind;
            assert_eq!(Snapshot::decode(&bytes), Err(DecodeError::Device));
        }
        let mut bytes = VECTOR;
        bytes[1] = 2;
        assert_eq!(Snapshot::decode(&bytes).unwrap().device, DeviceKind::Fitbit);
    }

    #[test]
    fn percentage_is_known_zero_through_one_hundred_or_unknown() {
        for value in 0..=255 {
            let mut bytes = VECTOR;
            bytes[2] = value;
            match value {
                0..=100 => assert_eq!(Snapshot::decode(&bytes).unwrap().percent, Some(value)),
                255 => assert_eq!(Snapshot::decode(&bytes).unwrap().percent, None),
                _ => assert_eq!(Snapshot::decode(&bytes), Err(DecodeError::Percent)),
            }
        }
    }

    #[test]
    fn every_flag_combination_is_validated() {
        for flags in 0..=255 {
            let mut bytes = VECTOR;
            bytes[3] = flags;
            let valid = [0, 1, 3, 4, 5, 7, 12, 13, 15].contains(&flags);
            assert_eq!(Snapshot::decode(&bytes).is_ok(), valid, "flags={flags}");
        }
        let mut bytes = VECTOR;
        bytes[3] = 0;
        let packet = Snapshot::decode(&bytes).unwrap();
        assert_eq!(packet.plugged_in, None);
        assert_eq!(packet.charging, None);
    }

    #[test]
    fn timestamp_is_positive_and_javascript_safe() {
        for timestamp in [0, JS_MAX_SAFE_INTEGER + 1, u64::MAX] {
            let mut bytes = VECTOR;
            bytes[4..].copy_from_slice(&timestamp.to_be_bytes());
            assert_eq!(Snapshot::decode(&bytes), Err(DecodeError::Timestamp));
        }
        for timestamp in [1, JS_MAX_SAFE_INTEGER] {
            let mut bytes = VECTOR;
            bytes[4..].copy_from_slice(&timestamp.to_be_bytes());
            assert_eq!(Snapshot::decode(&bytes).unwrap().updated_at, timestamp);
        }
    }

    #[test]
    fn ndjson_contract_preserves_unknown_and_source_timestamp() {
        let mut packet = Snapshot::decode(&VECTOR).unwrap();
        packet.percent = None;
        packet.charging = None;
        let events = RelayState::default().receive(packet, Duration::ZERO, 1_700_000_001_234);
        assert_eq!(
            serde_json::to_value(&events[0]).unwrap(),
            serde_json::json!({
                "event": "connection", "connected": true,
            })
        );
        assert_eq!(
            serde_json::to_value(&events[1]).unwrap(),
            serde_json::json!({
                "event": "battery", "device": "phone", "percent": null,
                "pluggedIn": true, "charging": null,
                "updatedAt": 1_700_000_000_000_u64, "receivedAt": 1_700_000_001_234_u64,
            })
        );
    }

    #[test]
    fn disconnect_and_reconnect_do_not_keep_a_stale_session() {
        let mut state = RelayState::default();
        let packet = Snapshot::decode(&VECTOR).unwrap();
        assert_eq!(state.disconnect(), None);
        assert_eq!(state.receive(packet, Duration::ZERO, 1).len(), 2);
        assert_eq!(state.receive(packet, Duration::from_secs(1), 2).len(), 1);
        assert_eq!(
            state.disconnect(),
            Some(Event::Connection { connected: false })
        );
        assert_eq!(state.disconnect(), None);
        assert_eq!(state.receive(packet, Duration::from_secs(2), 3).len(), 2);
    }

    #[test]
    fn heartbeat_refreshes_liveness_and_inactive_app_expires() {
        let mut state = RelayState::default();
        let packet = Snapshot::decode(&VECTOR).unwrap();
        state.receive(packet, Duration::ZERO, 1);
        assert_eq!(state.expire(Duration::from_secs(179)), None);
        state.receive(packet, Duration::from_secs(179), 2);
        assert_eq!(state.expire(Duration::from_secs(358)), None);
        assert_eq!(
            state.expire(Duration::from_secs(359)),
            Some(Event::Connection { connected: false })
        );
        assert_eq!(state.expire(Duration::from_secs(500)), None);
        assert_eq!(state.receive(packet, Duration::from_secs(600), 3).len(), 2);
    }

    #[test]
    fn fitbit_cannot_start_or_extend_phone_liveness() {
        let mut state = RelayState::default();
        let phone = Snapshot::decode(&VECTOR).unwrap();
        let fitbit = Snapshot {
            device: DeviceKind::Fitbit,
            ..phone
        };
        assert!(state.receive(fitbit, Duration::ZERO, 1).is_empty());
        state.receive(phone, Duration::ZERO, 1);
        assert_eq!(state.receive(fitbit, Duration::from_secs(179), 2).len(), 1);
        assert_eq!(
            state.expire(Duration::from_secs(180)),
            Some(Event::Connection { connected: false })
        );
        assert!(!state.is_connected());
    }

    #[test]
    fn unpaired_links_are_allowed_but_disconnected_or_blocked_links_are_not() {
        assert!(link_usable(true, false));
        assert!(!link_usable(false, false));
        assert!(!link_usable(true, true));
        assert!(!link_usable(false, true));
    }
}
