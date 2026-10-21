//! Battery advertisements and their UI events. No connected BLE transport.
use serde::Serialize;

pub mod clock;
pub mod fast_pair;
pub mod observer;
pub mod output;
pub mod passive;
pub mod phone;

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(tag = "event", rename_all = "lowercase")]
pub enum Event {
    Relay {
        mode: &'static str,
        available: bool,
        phone: Option<PhoneLevel>,
        fitbit: Option<FitbitLevel>,
        #[serde(rename = "observedAt")]
        observed_at: Option<u64>,
        #[serde(rename = "receivedAt")]
        received_at: u64,
    },
    Earbuds {
        mode: &'static str,
        available: bool,
        case: EarbudLevel,
        left: EarbudLevel,
        right: EarbudLevel,
        #[serde(rename = "observedAt")]
        observed_at: Option<u64>,
        #[serde(rename = "receivedAt")]
        received_at: u64,
    },
}
impl Event {
    /// Observation/report timestamps alone are not a battery change.
    pub fn same_values(&self, other: &Self) -> bool {
        match (self, other) {
            (
                Self::Relay {
                    available: a,
                    phone: p,
                    fitbit: f,
                    ..
                },
                Self::Relay {
                    available: b,
                    phone: q,
                    fitbit: g,
                    ..
                },
            ) => a == b && p == q && f == g,
            (
                Self::Earbuds {
                    available: a,
                    case: c,
                    left: l,
                    right: r,
                    ..
                },
                Self::Earbuds {
                    available: b,
                    case: d,
                    left: m,
                    right: s,
                    ..
                },
            ) => a == b && c == d && l == m && r == s,
            _ => false,
        }
    }
}
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize)]
pub struct EarbudLevel {
    pub percent: Option<u8>,
    pub charging: Option<bool>,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
pub struct PhoneLevel {
    pub percent: Option<u8>,
    #[serde(rename = "pluggedIn")]
    pub plugged_in: Option<bool>,
    pub charging: Option<bool>,
    #[serde(rename = "updatedAt")]
    pub updated_at: u64,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
pub struct FitbitLevel {
    pub percent: u8,
    #[serde(rename = "updatedAt")]
    pub updated_at: u64,
}
