//! State supplied by BlueZ's passive advertisement monitor. DeviceFound/Lost
//! own presence; a content timestamp is never advanced by a reporting timer.
use crate::fast_pair::{Levels, Reading};
use anyhow::{Result, ensure};
use bluer::monitor::{Monitor, Pattern, RssiSamplingPeriod};
use std::{collections::HashMap, time::Duration};

pub const MANAGER: &str = "org.bluez.AdvertisementMonitorManager1";
// Keep the previous three-minute presence window for spaced-out case reports
// and advertising-address rotation. This never changes the content timestamp.
pub const LOST_AFTER: Duration = Duration::from_secs(180);
const MAX_TRACKED: usize = 128;

pub fn observation_loop_expired(previous: Duration, now: Duration) -> bool {
    now.saturating_sub(previous) >= LOST_AFTER
}

pub fn specification() -> Monitor {
    monitor(vec![
        // Hardware matches the raw AD value (UUID + version). BlueZ 5.87's
        // software match_service() instead matches the payload after removing
        // the UUID. Keep this prefilter deliberately coarse for both layouts;
        // the receiver ALWAYS selects FE2C and checks the Account Key afterward.
        Pattern::new(0x16, 0, &[0x2c, 0xfe, 0x10]),
        Pattern::new(0x16, 0, &[0x10]),
    ])
}

pub fn monitor(patterns: Vec<Pattern>) -> Monitor {
    Monitor {
        patterns: Some(patterns),
        rssi_high_threshold: Some(-127),
        rssi_low_threshold: Some(-127),
        rssi_high_timeout: Some(Duration::from_secs(1)),
        rssi_low_timeout: Some(LOST_AFTER),
        rssi_sampling_period: Some(RssiSamplingPeriod::All),
        ..Default::default()
    }
}

#[derive(Clone, Copy)]
struct Observation {
    reading: Reading,
    heard: Duration,
    observed: u64,
}

#[derive(Default)]
pub struct PassiveState {
    sources: HashMap<String, Option<Observation>>,
}

impl PassiveState {
    pub fn found(
        &mut self,
        path: String,
        reading: Option<Reading>,
        heard: Duration,
        observed: u64,
    ) -> Result<()> {
        ensure!(
            self.sources.contains_key(&path) || self.sources.len() < MAX_TRACKED,
            "Too many passive monitor devices"
        );
        self.sources.entry(path.clone()).or_insert(None);
        self.update(&path, reading, heard, observed);
        Ok(())
    }

    pub fn update(&mut self, path: &str, reading: Option<Reading>, heard: Duration, observed: u64) {
        let Some(slot) = self.sources.get_mut(path) else {
            return;
        };
        // An unrelated/non-battery frame is not a battery withdrawal. A valid
        // key-matched all-unknown reading can withdraw values; DeviceLost owns
        // presence loss. In particular, do not erase a value on a read race.
        let Some(reading) = reading else {
            return;
        };
        if slot.is_some_and(|old| old.heard > heard) {
            return;
        }
        *slot = Some(Observation {
            reading,
            heard,
            observed,
        });
    }

    pub fn lost(&mut self, path: &str) {
        self.sources.remove(path);
    }

    pub fn levels(&self) -> Levels {
        let observations: Vec<_> = self.sources.values().flatten().copied().collect();
        let case = observations
            .iter()
            .filter(|o| o.reading.case_advertisement)
            .max_by_key(|o| o.heard)
            .map(|o| o.reading.case)
            .unwrap_or_default();
        let ear = |part: fn(Reading) -> crate::EarbudLevel| {
            observations
                .iter()
                .filter(|o| part(o.reading).percent.is_some())
                .max_by_key(|o| o.heard)
                .map(|o| part(o.reading))
                .unwrap_or_default()
        };
        Levels {
            case,
            left: ear(|r| r.left),
            right: ear(|r| r.right),
            observed_at: observations.iter().map(|o| o.observed).max(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn reading(case: Option<u8>, left: u8, right: u8) -> Reading {
        let level = |percent| crate::EarbudLevel {
            percent,
            charging: percent.map(|_| false),
        };
        Reading {
            case: level(case),
            left: level(Some(left)),
            right: level(Some(right)),
            case_advertisement: case.is_some(),
        }
    }
    #[test]
    fn monitor_is_selective_and_requests_continuous_reports_without_discovery() {
        let monitor = specification();
        assert_eq!(
            monitor.patterns.unwrap(),
            [
                Pattern::new(0x16, 0, &[0x2c, 0xfe, 0x10]),
                Pattern::new(0x16, 0, &[0x10])
            ]
        );
        assert_eq!(monitor.rssi_sampling_period, Some(RssiSamplingPeriod::All));
        assert_eq!(monitor.rssi_low_timeout, Some(Duration::from_secs(180)));
    }
    #[test]
    fn a_suspended_observer_must_reacquire_presence_before_reporting_again() {
        assert!(!observation_loop_expired(
            Duration::from_secs(100),
            Duration::from_secs(279)
        ));
        assert!(observation_loop_expired(
            Duration::from_secs(100),
            Duration::from_secs(280)
        ));
        assert!(observation_loop_expired(
            Duration::from_secs(100),
            Duration::from_secs(3700)
        ));
    }
    #[test]
    fn cached_properties_cannot_establish_presence() {
        let mut state = PassiveState::default();
        state.update(
            "case",
            Some(reading(Some(85), 100, 100)),
            Duration::ZERO,
            1000,
        );
        assert!(!state.levels().available());
        state
            .found("other-owner".into(), None, Duration::ZERO, 1000)
            .unwrap();
        assert!(!state.levels().available());
    }
    #[test]
    fn reporter_heartbeats_never_retimestamp_unchanged_observations() {
        let mut state = PassiveState::default();
        state
            .found(
                "case".into(),
                Some(reading(Some(85), 100, 100)),
                Duration::ZERO,
                1000,
            )
            .unwrap();
        for now in [31_000, 181_000, 3_601_000] {
            let crate::Event::Earbuds {
                observed_at,
                received_at,
                available,
                ..
            } = state.levels().event(now)
            else {
                panic!()
            };
            assert_eq!(observed_at, Some(1000));
            assert_eq!(received_at, now);
            assert!(available);
        }
        state.lost("case");
        assert!(!state.levels().available());
    }
    #[test]
    fn losing_case_does_not_lose_buds_or_use_a_bud_as_case() {
        let mut state = PassiveState::default();
        state
            .found(
                "case".into(),
                Some(reading(Some(85), 100, 100)),
                Duration::ZERO,
                1000,
            )
            .unwrap();
        state
            .found(
                "buds".into(),
                Some(reading(None, 19, 80)),
                Duration::from_secs(10),
                11000,
            )
            .unwrap();
        assert_eq!(state.levels().left.percent, Some(19));
        state.lost("case");
        assert_eq!(state.levels().case.percent, None);
        assert_eq!(state.levels().left.percent, Some(19));
        state.lost("buds");
        assert!(!state.levels().available());
    }
    #[test]
    fn late_updates_and_old_address_loss_do_not_erase_new_readings() {
        let mut state = PassiveState::default();
        state
            .found(
                "old".into(),
                Some(reading(Some(85), 100, 100)),
                Duration::ZERO,
                1000,
            )
            .unwrap();
        state
            .found(
                "new".into(),
                Some(reading(Some(84), 100, 100)),
                Duration::from_secs(10),
                11000,
            )
            .unwrap();
        state.lost("old");
        state.update(
            "old",
            Some(reading(Some(85), 100, 100)),
            Duration::from_secs(11),
            12000,
        );
        state.update(
            "new",
            Some(reading(Some(90), 100, 100)),
            Duration::from_secs(9),
            10000,
        );
        assert_eq!(state.levels().case.percent, Some(84));
        state.update("new", None, Duration::from_secs(12), 13000);
        assert_eq!(state.levels().case.percent, Some(84));
        assert_eq!(state.levels().observed_at, Some(11000));
        state.lost("new");
        assert!(!state.levels().available());
    }
    #[test]
    fn source_tracking_is_bounded() {
        let mut state = PassiveState::default();
        for i in 0..MAX_TRACKED {
            state
                .found(i.to_string(), None, Duration::ZERO, 1000)
                .unwrap();
        }
        assert!(
            state
                .found("overflow".into(), None, Duration::ZERO, 1000)
                .is_err()
        );
        state.lost("0");
        assert!(
            state
                .found("replacement".into(), None, Duration::ZERO, 1000)
                .is_ok()
        );
    }
}
