//! Optional panel details. Missing sensors must not interrupt the core stream.
use anyhow::{Context, Result, ensure};
use serde_json::{Value, json};
use std::{collections::HashMap, fs, path::Path};

pub struct Memory {
    pub used: u64,
    pub total: u64,
    pub swap_used: Option<u64>,
    pub swap_total: Option<u64>,
}

pub fn memory(text: &str) -> Result<Memory> {
    let mut values = HashMap::new();
    for line in text.lines() {
        let Some((key, rest)) = line.split_once(':') else {
            continue;
        };
        if !matches!(key, "MemTotal" | "MemAvailable" | "SwapTotal" | "SwapFree") {
            continue;
        }
        let mut fields = rest.split_whitespace();
        let value = fields
            .next()
            .context("Missing memory value")?
            .parse::<u64>()?;
        ensure!(fields.next() == Some("kB"), "Unexpected memory unit");
        values.insert(
            key,
            value.checked_mul(1024).context("Memory value overflow")?,
        );
    }
    let total = *values.get("MemTotal").context("MemTotal is missing")?;
    let available = *values
        .get("MemAvailable")
        .context("MemAvailable is missing")?;
    ensure!(total > 0, "MemTotal is zero");
    Ok(Memory {
        used: total.saturating_sub(available),
        total,
        swap_used: values
            .get("SwapTotal")
            .zip(values.get("SwapFree"))
            .map(|(total, free)| total.saturating_sub(*free)),
        swap_total: values.get("SwapTotal").copied(),
    })
}

fn cpu_info(text: &str) -> (Option<String>, Option<f64>) {
    let mut name = None;
    let mut frequencies = Vec::new();
    for line in text.lines() {
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        match key.trim() {
            "model name" if name.is_none() => name = Some(value.trim().to_string()),
            "cpu MHz" => {
                if let Ok(mhz) = value.trim().parse::<f64>()
                    && mhz.is_finite()
                    && mhz > 0.0
                    && mhz < 20_000.0
                {
                    frequencies.push(mhz);
                }
            }
            _ => (),
        }
    }
    let frequency = (!frequencies.is_empty())
        .then(|| frequencies.iter().sum::<f64>() / frequencies.len() as f64);
    (name.filter(|name| !name.is_empty()), frequency)
}

// Prefer package/Tdie sensors; never accidentally report an NVMe or GPU sensor.
pub fn cpu_temperature(hwmon: &Path) -> Option<f64> {
    let mut package = Vec::new();
    let mut fallback = Vec::new();
    for directory in fs::read_dir(hwmon)
        .ok()?
        .flatten()
        .map(|entry| entry.path())
    {
        let driver = fs::read_to_string(directory.join("name")).unwrap_or_default();
        if !matches!(
            driver.trim(),
            "coretemp" | "k10temp" | "zenpower" | "cpu_thermal"
        ) {
            continue;
        }
        let Ok(entries) = fs::read_dir(&directory) else {
            continue;
        };
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            let Some(index) = name
                .strip_prefix("temp")
                .and_then(|s| s.strip_suffix("_input"))
            else {
                continue;
            };
            if index.is_empty() || !index.bytes().all(|c| c.is_ascii_digit()) {
                continue;
            }
            let temperature = fs::read_to_string(entry.path())
                .ok()
                .and_then(|text| text.trim().parse::<f64>().ok())
                .map(|value| value / 1000.0);
            let Some(temperature) =
                temperature.filter(|value| value.is_finite() && (0.0..=150.0).contains(value))
            else {
                continue;
            };
            let label = fs::read_to_string(directory.join(format!("temp{index}_label")))
                .unwrap_or_default();
            if label.trim().starts_with("Package id") || label.trim() == "Tdie" {
                package.push(temperature);
            } else {
                fallback.push(temperature);
            }
        }
    }
    let readings = if package.is_empty() {
        fallback
    } else {
        package
    };
    readings.into_iter().reduce(f64::max)
}

pub fn snapshot(proc: &Path, hwmon: &Path, memory: &Memory) -> Value {
    let (name, frequency) = cpu_info(&fs::read_to_string(proc.join("cpuinfo")).unwrap_or_default());
    json!({
        "cpuName": name,
        "cpuFrequencyMHz": frequency,
        "cpuTemperatureC": cpu_temperature(hwmon),
        "memoryUsedBytes": memory.used,
        "memoryTotalBytes": memory.total,
        "swapUsedBytes": memory.swap_used,
        "swapTotalBytes": memory.swap_total,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn memory_uses_available_not_free_and_reports_swap() {
        let result = memory("MemTotal: 1000 kB\nMemFree: 50 kB\nMemAvailable: 400 kB\nSwapTotal: 500 kB\nSwapFree: 450 kB").unwrap();
        assert_eq!((result.used, result.total), (600 * 1024, 1000 * 1024));
        assert_eq!(
            (result.swap_used, result.swap_total),
            (Some(50 * 1024), Some(500 * 1024))
        );
        let result = memory("MemTotal: 1000 kB\nMemAvailable: 1100 kB").unwrap();
        assert_eq!(result.used, 0);
        assert!(result.swap_used.is_none());
        for text in [
            "MemTotal: 0 kB\nMemAvailable: 0 kB",
            "MemTotal: 10 kB",
            "MemTotal: 10 MB\nMemAvailable: 2 kB",
            "MemTotal: 18446744073709551615 kB\nMemAvailable: 0 kB",
        ] {
            assert!(memory(text).is_err());
        }
    }

    #[test]
    fn frequency_is_the_mean_of_available_logical_cpus() {
        let (name, frequency) = cpu_info(
            "model name : Test CPU\ncpu MHz : 1200\ncpu MHz : 3600\ncpu MHz : NaN\ncpu MHz : -1",
        );
        assert_eq!(name.as_deref(), Some("Test CPU"));
        assert_eq!(frequency, Some(2400.0));
        assert_eq!(cpu_info(""), (None, None));
    }

    #[test]
    fn temperature_prefers_cpu_package_and_recovers_from_missing_sensor() {
        let temp = tempfile::tempdir().unwrap();
        for (name, driver, label, value) in [
            ("hwmon0", "nvme", "Composite", "99000"),
            ("hwmon1", "coretemp", "Core 0", "75000"),
            ("hwmon2", "coretemp", "Package id 0", "63000"),
        ] {
            let sensor = temp.path().join(name);
            fs::create_dir(&sensor).unwrap();
            fs::write(sensor.join("name"), driver).unwrap();
            fs::write(sensor.join("temp1_label"), label).unwrap();
            fs::write(sensor.join("temp1_input"), value).unwrap();
        }
        assert_eq!(cpu_temperature(temp.path()), Some(63.0));
        fs::write(temp.path().join("hwmon2/temp1_input"), "NaN").unwrap();
        assert_eq!(cpu_temperature(temp.path()), Some(75.0));
        assert_eq!(cpu_temperature(&temp.path().join("missing")), None);
    }
}
