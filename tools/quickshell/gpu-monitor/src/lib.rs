//! Read-only NVIDIA telemetry. No commands, config files, or GPU power writes.
mod nvidia;
mod processes;

use anyhow::{Context, Result};
pub use nvidia::Nvidia;
use serde::Serialize;
use std::{
    fs,
    path::{Path, PathBuf},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

pub const PCI_ROOT: &str = "/sys/bus/pci/devices";
const RETRY_DELAY: Duration = Duration::from_secs(30);

#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Metrics {
    pub name: Option<String>,
    pub usage: Option<u32>,
    pub temperature_c: Option<u32>,
    pub memory_used_bytes: Option<u64>,
    pub memory_total_bytes: Option<u64>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Gpu {
    pub powered_on: bool,
    #[serde(flatten)]
    pub metrics: Metrics,
}

#[derive(Debug, Serialize)]
pub struct Report {
    pub text: String,
    pub gpu: Option<Gpu>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub top: Option<serde_json::Value>,
}

impl Report {
    fn unavailable(error: impl ToString) -> Self {
        Self {
            text: "--".into(),
            gpu: None,
            error: Some(error.to_string()),
            top: None,
        }
    }

    fn sleeping(name: Option<String>) -> Self {
        Self {
            text: "Off".into(),
            gpu: Some(Gpu {
                powered_on: false,
                metrics: Metrics {
                    name,
                    ..Default::default()
                },
            }),
            error: None,
            top: None,
        }
    }

    fn active(metrics: Metrics) -> Self {
        let usage = metrics
            .usage
            .map_or_else(|| "--".into(), |n| format!("{n}%"));
        let memory = metrics
            .memory_used_bytes
            .zip(metrics.memory_total_bytes)
            .filter(|(used, total)| *total > 0 && used <= total)
            .map(|(used, total)| {
                (u128::from(used) * 100 + u128::from(total) / 2) / u128::from(total)
            });
        let text = memory.map_or(usage.clone(), |n| format!("{usage}|{n}%"));
        Self {
            text,
            gpu: Some(Gpu {
                powered_on: true,
                metrics,
            }),
            error: None,
            top: None,
        }
    }
}

/// Implementations are called only when the selected PCI GPU reports `active`.
pub trait Backend {
    fn read(&mut self, pci_address: &str) -> Result<Metrics>;
    fn reset(&mut self) {}
    fn processes(&mut self, _pci_address: &str, _since: u64) -> Result<serde_json::Value> {
        anyhow::bail!("GPU process lists unavailable")
    }
}

fn hex_file(path: &Path) -> Option<u32> {
    let text = fs::read_to_string(path).ok()?;
    u32::from_str_radix(text.trim().trim_start_matches("0x"), 16).ok()
}

fn discover(root: &Path) -> Result<Option<String>> {
    let mut candidates = fs::read_dir(root)
        .with_context(|| format!("Cannot inspect PCI devices in {}", root.display()))?
        .filter_map(|entry| entry.ok())
        .filter(|entry| {
            hex_file(&entry.path().join("vendor")) == Some(0x10de)
                && hex_file(&entry.path().join("class")).is_some_and(|class| class >> 16 == 0x03)
        })
        .filter_map(|entry| entry.file_name().into_string().ok())
        .collect::<Vec<_>>();
    candidates.sort();
    Ok(candidates.into_iter().next())
}

pub struct Sampler<B> {
    root: PathBuf,
    backend: B,
    selected: Option<String>,
    name: Option<String>,
    retry_at: Duration,
    last_error: Option<String>,
    top_generation: u64,
    top_next: Duration,
    top_since: u64,
}

impl<B: Backend> Sampler<B> {
    pub fn new(root: PathBuf, backend: B) -> Self {
        Self {
            root,
            backend,
            selected: None,
            name: None,
            retry_at: Duration::ZERO,
            last_error: None,
            top_generation: 0,
            top_next: Duration::ZERO,
            top_since: 0,
        }
    }

    pub fn sample_with_top(&mut self, elapsed: Duration, generation: u64) -> Report {
        let mut report = self.sample(elapsed);
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_micros() as u64;
        if generation != self.top_generation {
            self.top_generation = generation;
            self.top_next = Duration::ZERO;
            self.top_since = now.saturating_sub(2_000_000);
        }
        if generation == 0 || elapsed < self.top_next {
            return report;
        }
        self.top_next = elapsed + Duration::from_secs(2);
        // The global sample performed the same power/driver checks. Check power
        // once more immediately before the optional process queries.
        let mut top = match (&report.gpu, self.selected.as_ref()) {
            (Some(gpu), Some(address))
                if gpu.powered_on
                    && fs::read_to_string(self.root.join(address).join("power/runtime_status"))
                        .is_ok_and(|state| state.trim() == "active") =>
            {
                match self
                    .backend
                    .processes(address, self.top_since.max(now.saturating_sub(4_000_000)))
                {
                    Ok(top) => top,
                    Err(error) => serde_json::json!({"error":format!("{error:#}")}),
                }
            }
            (Some(gpu), _) if !gpu.powered_on => serde_json::json!({"state":"sleeping"}),
            _ => serde_json::json!({"error":"GPU unavailable"}),
        };
        self.top_since = now;
        top["generation"] = generation.into();
        report.top = Some(top);
        report
    }

    pub fn sample(&mut self, elapsed: Duration) -> Report {
        // Cheap sysfs discovery also catches hotplug and driver/card replacement.
        let address = match discover(&self.root) {
            Ok(address) => address,
            Err(error) => return Report::unavailable(error),
        };
        if self.selected != address {
            self.backend.reset();
            self.selected = address;
            self.name = None;
            self.retry_at = Duration::ZERO;
            self.last_error = None;
        }
        let Some(address) = self.selected.as_ref() else {
            return Report::unavailable("No NVIDIA display device found");
        };
        // Check BEFORE initializing NVML as well as before every sample. Never
        // assume the device is awake if power state is unreadable or unknown.
        let power = fs::read_to_string(self.root.join(address).join("power/runtime_status"));
        match power.as_deref().map(str::trim) {
            Ok("suspended" | "suspending" | "resuming") => {
                return Report::sleeping(self.name.clone());
            }
            Ok("active") => (),
            _ => return Report::unavailable("GPU runtime power state unavailable"),
        }
        if elapsed < self.retry_at {
            return Report::unavailable(
                self.last_error
                    .as_deref()
                    .unwrap_or("GPU temporarily unavailable"),
            );
        }
        match self.backend.read(address) {
            Ok(mut metrics) => {
                if metrics.name.is_some() {
                    self.name.clone_from(&metrics.name);
                } else {
                    metrics.name.clone_from(&self.name);
                }
                self.last_error = None;
                Report::active(metrics)
            }
            Err(error) => {
                self.retry_at = elapsed + RETRY_DELAY;
                self.last_error = Some(format!("GPU telemetry unavailable: {error:#}"));
                Report::unavailable(self.last_error.as_deref().unwrap())
            }
        }
    }
}

#[cfg(test)]
mod tests;
