//! V2 non-connectable service-data payload (12 bytes). No v1/GATT fallback.
use crate::{Event, FitbitLevel, PhoneLevel, observer::Source};
use anyhow::{Result, ensure};
use bluer::{Uuid, monitor::Pattern};
use std::{collections::HashMap, time::Duration};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Advertisement {
    pub phone: PhoneLevel,
    pub fitbit: Option<FitbitLevel>,
}
impl Advertisement {
    pub fn decode(bytes: &[u8]) -> Result<Self> {
        ensure!(
            bytes.len() == 12 && bytes[0] == 2,
            "Invalid advertisement length/version"
        );
        let percent = |v| match v {
            0..=100 => Ok(Some(v)),
            255 => Ok(None),
            _ => anyhow::bail!("Invalid percentage"),
        };
        let phone = percent(bytes[1])?;
        let fitbit = percent(bytes[3])?;
        let flags = bytes[2];
        ensure!(
            flags & 0xf0 == 0 && flags & 3 != 2 && flags & 12 != 8,
            "Invalid charge flags"
        );
        let phone_at = u64::from(u32::from_be_bytes(bytes[4..8].try_into()?)) * 1000;
        let fitbit_at = u64::from(u32::from_be_bytes(bytes[8..12].try_into()?)) * 1000;
        ensure!(
            phone_at != 0 && fitbit.is_some() == (fitbit_at != 0),
            "Invalid source timestamp"
        );
        Ok(Self {
            phone: PhoneLevel {
                percent: phone,
                plugged_in: (flags & 1 != 0).then_some(flags & 2 != 0),
                charging: (flags & 4 != 0).then_some(flags & 8 != 0),
                updated_at: phone_at,
            },
            fitbit: fitbit.map(|percent| FitbitLevel {
                percent,
                updated_at: fitbit_at,
            }),
        })
    }
}

pub fn patterns(uuid: Uuid) -> Vec<Pattern> {
    // AD type 0x21 contains a little-endian 128-bit UUID and the v2 payload.
    // BlueZ 5.87's software matcher strips the UUID; hardware does not.
    // Both are prefilters only: observer always selects the exact service UUID.
    let mut raw: Vec<u8> = uuid.as_bytes().iter().rev().copied().collect();
    raw.push(2);
    vec![Pattern::new(0x21, 0, &raw), Pattern::new(0x21, 0, &[2])]
}

#[derive(Clone, Copy)]
struct Observation {
    value: Advertisement,
    heard: Duration,
    observed: u64,
}
#[derive(Default)]
pub struct PhoneState {
    sources: HashMap<String, Option<Observation>>,
}
impl Source for PhoneState {
    fn found(
        &mut self,
        path: String,
        data: Option<&[u8]>,
        heard: Duration,
        observed: u64,
    ) -> Result<()> {
        ensure!(
            self.sources.contains_key(&path) || self.sources.len() < 128,
            "Too many monitored devices"
        );
        self.sources.entry(path.clone()).or_insert(None);
        self.update(&path, data, heard, observed);
        Ok(())
    }
    fn update(&mut self, path: &str, data: Option<&[u8]>, heard: Duration, observed: u64) {
        let Some(slot) = self.sources.get_mut(path) else {
            return;
        };
        if slot.is_some_and(|old| old.heard > heard) {
            return;
        }
        let Some(data) = data else {
            return;
        };
        // An invalid payload for our UUID is not a valid battery, not even 0%.
        *slot = Advertisement::decode(data).ok().map(|value| Observation {
            value,
            heard,
            observed,
        });
    }
    fn lost(&mut self, path: &str) {
        self.sources.remove(path);
    }
    fn event(&self, received_at: u64) -> Event {
        let reading = self.sources.values().flatten().max_by_key(|o| o.heard);
        Event::Relay {
            mode: "passive",
            available: reading.is_some(),
            phone: reading.map(|o| o.value.phone),
            fitbit: reading.and_then(|o| o.value.fitbit),
            observed_at: reading.map(|o| o.observed),
            received_at,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    const VECTOR: [u8; 12] = [2, 73, 7, 42, 0x65, 0x53, 0xf1, 0, 0x65, 0x53, 0xed, 0x7c];
    #[test]
    fn android_shared_vector_and_original_dates() {
        let value = Advertisement::decode(&VECTOR).unwrap();
        assert_eq!(
            value.phone,
            PhoneLevel {
                percent: Some(73),
                plugged_in: Some(true),
                charging: Some(false),
                updated_at: 1_700_000_000_000
            }
        );
        assert_eq!(
            value.fitbit.unwrap(),
            FitbitLevel {
                percent: 42,
                updated_at: 1_699_999_100_000
            }
        );
        assert!(2 + 16 + VECTOR.len() <= 31);
    }
    #[test]
    fn no_old_protocol_or_bad_lengths() {
        for n in [0, 1, 11, 13, 31, 512] {
            assert!(Advertisement::decode(&vec![2; n]).is_err());
        }
        for version in [0, 1, 3, 255] {
            let mut b = VECTOR;
            b[0] = version;
            assert!(Advertisement::decode(&b).is_err());
        }
    }
    #[test]
    fn exhaustive_percentages_flags_and_unknowns() {
        for v in 0..=255 {
            let mut b = VECTOR;
            b[1] = v;
            assert_eq!(Advertisement::decode(&b).is_ok(), v <= 100 || v == 255);
        }
        for v in 0..=255 {
            let mut b = VECTOR;
            b[3] = v;
            assert_eq!(Advertisement::decode(&b).is_ok(), v <= 100);
        }
        for f in 0..=255 {
            let mut b = VECTOR;
            b[2] = f;
            assert_eq!(
                Advertisement::decode(&b).is_ok(),
                f & 0xf0 == 0 && f & 3 != 2 && f & 12 != 8
            );
        }
        let mut b = VECTOR;
        b[1] = 255;
        b[2] = 0;
        b[3] = 255;
        b[8..].fill(0);
        let value = Advertisement::decode(&b).unwrap();
        assert_eq!(value.phone.percent, None);
        assert_eq!(value.phone.plugged_in, None);
        assert_eq!(value.fitbit, None);
        b[4..8].fill(0);
        assert!(Advertisement::decode(&b).is_err());
    }
    #[test]
    fn both_filter_layouts_use_service_data_128() {
        let uuid = Uuid::parse_str("e167a6ba-8246-4729-8ae6-4f1ecde39e1c").unwrap();
        let filters = patterns(uuid);
        assert_eq!(
            filters[0],
            Pattern::new(
                0x21,
                0,
                &[
                    0x1c, 0x9e, 0xe3, 0xcd, 0x1e, 0x4f, 0xe6, 0x8a, 0x29, 0x47, 0x46, 0x82, 0xba,
                    0xa6, 0x67, 0xe1, 2
                ]
            )
        );
        assert_eq!(filters[1], Pattern::new(0x21, 0, &[2]));
    }
    #[test]
    fn cache_cannot_establish_presence_and_unchanged_content_does_not_expire() {
        let mut s = PhoneState::default();
        s.update("p", Some(&VECTOR), Duration::ZERO, 1000);
        assert!(matches!(
            s.event(1000),
            Event::Relay {
                available: false,
                ..
            }
        ));
        s.found("p".into(), Some(&VECTOR), Duration::ZERO, 1000)
            .unwrap();
        for t in [1000, 180_000, 3_600_000] {
            let Event::Relay {
                available,
                phone,
                fitbit,
                observed_at,
                received_at,
                ..
            } = s.event(t)
            else {
                panic!()
            };
            assert!(available);
            assert_eq!(observed_at, Some(1000));
            assert_eq!(received_at, t);
            assert_eq!(phone.unwrap().updated_at, 1_700_000_000_000);
            assert_eq!(fitbit.unwrap().updated_at, 1_699_999_100_000);
        }
        s.lost("p");
        assert!(matches!(
            s.event(4_000_000),
            Event::Relay {
                available: false,
                phone: None,
                fitbit: None,
                ..
            }
        ));
    }
    #[test]
    fn rotation_stale_updates_and_fitbit_withdrawal_are_atomic() {
        let mut s = PhoneState::default();
        s.found("old".into(), Some(&VECTOR), Duration::ZERO, 1000)
            .unwrap();
        let mut next = VECTOR;
        next[1] = 74;
        next[3] = 255;
        next[8..].fill(0);
        s.found("new".into(), Some(&next), Duration::from_secs(2), 3000)
            .unwrap();
        s.update("new", Some(&VECTOR), Duration::from_secs(1), 2000);
        s.lost("old");
        let Event::Relay { phone, fitbit, .. } = s.event(4000) else {
            panic!()
        };
        assert_eq!(phone.unwrap().percent, Some(74));
        assert_eq!(fitbit, None);
        s.update("new", Some(&[2]), Duration::from_secs(3), 4000);
        assert!(matches!(
            s.event(5000),
            Event::Relay {
                available: false,
                ..
            }
        ));
    }
}
