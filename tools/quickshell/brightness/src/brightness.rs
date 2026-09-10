use crate::{now, process::Runner};
use anyhow::{Context, Result, ensure};
use serde_json::{Value, json};
use std::{fs, os::unix::fs::FileTypeExt, process::Command};

fn steps(text: &str) -> Result<Vec<i64>> {
    let value: Value = serde_json::from_str(text)?;
    let values = match value {
        Value::Array(values) => values,
        value => vec![value],
    };
    values
        .into_iter()
        .map(|v| {
            v.as_i64()
                .or_else(|| {
                    v.as_f64()
                        .filter(|n| n.fract() == 0.0 && n.abs() < i64::MAX as f64)
                        .map(|n| n as i64)
                })
                .context("brightness steps must be integers")
        })
        .collect()
}

fn apply_steps(current: u64, maximum: u64, steps: &[i64]) -> u64 {
    steps.iter().fold(current, |value, &delta| {
        // Integer arithmetic preserves jq's round-away-from-zero ties, including
        // negative steps. i128 also prevents overflow for extreme input values.
        let scaled = i128::from(delta) * i128::from(maximum);
        let rounded = (scaled.abs() + 50) / 100 * scaled.signum();
        (i128::from(value) + rounded).clamp(0, i128::from(maximum)) as u64
    })
}

fn detect_bus(text: &str, monitor: &str, model: &str, serial: &str) -> Result<u64> {
    let mut valid = false;
    let mut bus = None;
    let mut connector = "";
    let mut matches = Vec::new();
    for line in text.lines() {
        if line.starts_with("Display ") {
            valid = true;
            bus = None;
            connector = "";
        } else if line.starts_with("Invalid display") {
            valid = false;
        }
        if let Some((_, value)) = line.split_once("I2C bus:") {
            bus = value
                .trim()
                .strip_prefix("/dev/i2c-")
                .and_then(|s| s.parse::<u64>().ok());
        }
        if let Some((_, value)) = line.split_once("DRM connector:") {
            connector = value.trim();
        }
        if let Some((_, value)) = line.split_once("Monitor:") {
            let identity = value.trim().split_once(':').map(|(_, rest)| rest);
            let correct_connector = connector
                .strip_prefix("card")
                .and_then(|s| s.split_once('-'))
                .is_some_and(|(card, name)| {
                    !card.is_empty() && card.bytes().all(|b| b.is_ascii_digit()) && name == monitor
                });
            if valid && correct_connector && identity == Some(format!("{model}:{serial}").as_str())
            {
                matches.push(bus.context("DDC display has no valid I2C bus")?);
            }
        }
    }
    ensure!(
        matches.len() == 1,
        "Cannot uniquely resolve DDC bus for {monitor}"
    );
    Ok(matches[0])
}

fn vcp(text: &str) -> Result<(u64, u64)> {
    let fields: Vec<_> = text.split_whitespace().collect();
    ensure!(
        fields.len() >= 5 && fields[..3] == ["VCP", "10", "C"],
        "Cannot read brightness: {text}"
    );
    let current = fields[3].parse()?;
    let maximum = fields[4].parse()?;
    ensure!(
        maximum > 0 && current <= maximum,
        "Invalid brightness range: {text}"
    );
    Ok((current, maximum))
}

fn cached_values(previous: &Value, timestamp: u64) -> Option<(u64, u64)> {
    let checked = previous["checkedAt"].as_u64()?;
    let current = previous["current"].as_u64()?;
    let maximum = previous["maximum"].as_u64()?;
    (checked <= timestamp && timestamp - checked <= 2 && maximum > 0 && current <= maximum)
        .then_some((current, maximum))
}

fn internal_percent(text: &str) -> Result<u64> {
    let value: u64 = text
        .trim()
        .split(',')
        .nth(3)
        .and_then(|s| s.strip_suffix('%'))
        .context("Invalid brightnessctl response")?
        .parse()?;
    ensure!(value <= 100, "Invalid backlight percentage");
    Ok(value)
}

fn cache_matches(previous: &Value, monitor: &str, model: &str, serial: &str) -> bool {
    previous["monitor"] == monitor && previous["model"] == model && previous["serial"] == serial
}

pub fn run(args: &[String], runner: &Runner) -> Result<Value> {
    ensure!(
        !args.is_empty() && args.len() <= 3,
        "usage: quickshell-brightness CONNECTOR [STEPS_JSON] [PREVIOUS_JSON]"
    );
    let monitor = &args[0];
    let steps = steps(args.get(1).map_or("0", String::as_str))?;
    let mut previous: Value = serde_json::from_str(args.get(2).map_or("null", String::as_str))?;
    let changing = steps.iter().any(|&n| n != 0);
    let monitors: Value =
        serde_json::from_str(&runner.capture(Command::new("hyprctl").args(["-j", "monitors"]))?)?;
    let monitors = monitors
        .as_array()
        .context("Invalid Hyprland monitor list")?;
    let target = monitors
        .iter()
        .find(|m| m["name"] == *monitor)
        .context("Monitor is not connected")?;
    if ["eDP-", "LVDS-", "DSI-"]
        .iter()
        .any(|prefix| monitor.starts_with(prefix))
    {
        let mut value =
            internal_percent(&runner.capture(Command::new("brightnessctl").args([
                "--class",
                "backlight",
                "--machine-readable",
            ]))?)?;
        if changing {
            let next = apply_steps(value, 100, &steps);
            value = internal_percent(&runner.capture(Command::new("brightnessctl").args([
                "--class",
                "backlight",
                "--machine-readable",
                "set",
                &format!("{next}%"),
            ]))?)?;
        }
        return Ok(json!({"monitor":monitor,"brightness":value}));
    }
    let model = target["model"]
        .as_str()
        .filter(|s| !s.is_empty())
        .context("DDC model is missing")?;
    let serial = target["serial"]
        .as_str()
        .filter(|s| !s.is_empty())
        .context("DDC serial is missing")?;
    ensure!(
        monitors
            .iter()
            .filter(|m| m["model"] == model && m["serial"] == serial)
            .count()
            == 1,
        "Ambiguous DDC monitor identity"
    );
    let cached_bus = previous["bus"].as_u64().filter(|bus| {
        cache_matches(&previous, monitor, model, serial)
            && fs::metadata(format!("/dev/i2c-{bus}")).is_ok_and(|m| m.file_type().is_char_device())
    });
    let bus = match cached_bus {
        Some(bus) => bus,
        None => {
            previous = Value::Null;
            detect_bus(
                &runner.capture(Command::new("ddcutil").args(["--brief", "detect"]))?,
                monitor,
                model,
                serial,
            )?
        }
    };
    let command = || {
        let mut cmd = Command::new("ddcutil");
        cmd.args([
            "--bus",
            &bus.to_string(),
            "--skip-ddc-checks",
            "--mccs",
            "2.1",
        ]);
        cmd
    };
    let (mut current, maximum) = match changing.then(|| cached_values(&previous, now())).flatten() {
        Some(values) => values,
        None => vcp(&runner.capture(command().args(["--brief", "getvcp", "10"]))?)?,
    };
    if changing {
        let next = apply_steps(current, maximum, &steps);
        if next != current {
            // Keep ddcutil's write verification: no --noverify shortcut.
            runner.capture(command().args(["setvcp", "10", &next.to_string()]))?;
        }
        current = next;
    }
    let percent = (u128::from(current) * 100 + u128::from(maximum) / 2) / u128::from(maximum);
    Ok(
        json!({"monitor":monitor,"model":model,"serial":serial,"bus":bus,"current":current,
        "maximum":maximum,"brightness":percent as u64,"checkedAt":now()}),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn step_validation() {
        assert_eq!(steps("5").unwrap(), vec![5]);
        assert_eq!(steps("[5,-2,0.0]").unwrap(), vec![5, -2, 0]);
        assert!(steps("[]").unwrap().is_empty());
        for input in ["null", "true", "1.5", "[1,\"2\"]", "{}"] {
            assert!(steps(input).is_err());
        }
    }
    #[test]
    fn bursts_clamp_each_step_and_round_ties() {
        assert_eq!(apply_steps(98, 100, &[5, -5]), 95);
        assert_eq!(apply_steps(2, 100, &[-5, 5]), 5);
        assert_eq!(apply_steps(20, 50, &[1]), 21);
        assert_eq!(apply_steps(20, 50, &[-1]), 19);
        assert_eq!(apply_steps(20, 50, &[1, -1]), 20);
        assert_eq!(apply_steps(0, u64::MAX, &[i64::MAX]), u64::MAX);
        assert_eq!(apply_steps(50, 100, &[i64::MIN]), 0);
    }
    #[test]
    fn detection_requires_connector_identity_and_unique_bus() {
        let text = "Display 1\n   I2C bus: /dev/i2c-5\n   DRM connector: card0-DP-1\n   Monitor: DEL:U2720Q:ABC\n";
        assert_eq!(detect_bus(text, "DP-1", "U2720Q", "ABC").unwrap(), 5);
        for (connector, model, serial) in [
            ("DP-2", "U2720Q", "ABC"),
            ("DP-1", "Other", "ABC"),
            ("DP-1", "U2720Q", "DEF"),
        ] {
            assert!(detect_bus(text, connector, model, serial).is_err());
        }
        assert!(detect_bus(&text.repeat(2), "DP-1", "U2720Q", "ABC").is_err());
        assert!(
            detect_bus(
                &text.replace("Display 1", "Invalid display"),
                "DP-1",
                "U2720Q",
                "ABC"
            )
            .is_err()
        );
    }
    #[test]
    fn readings_and_cache() {
        assert_eq!(vcp("VCP 10 C 25 100").unwrap(), (25, 100));
        for text in [
            "VCP 10 ERR",
            "VCP 12 C 1 100",
            "VCP 10 C 1 0",
            "VCP 10 C 101 100",
        ] {
            assert!(vcp(text).is_err());
        }
        let previous = json!({"monitor":"DP-1","model":"X","serial":"Y","current":25,"maximum":100,"checkedAt":10});
        assert_eq!(cached_values(&previous, 12), Some((25, 100)));
        assert_eq!(cached_values(&previous, 13), None);
        assert_eq!(cached_values(&previous, 9), None);
        assert!(cache_matches(&previous, "DP-1", "X", "Y"));
        assert!(!cache_matches(&previous, "DP-2", "X", "Y"));
        assert_eq!(
            internal_percent("intel_backlight,backlight,20,45%,100\n").unwrap(),
            45
        );
    }
}
