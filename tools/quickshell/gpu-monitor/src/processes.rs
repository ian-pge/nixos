//! NVIDIA process lists: graphics + compute, deduplicated by PID.
use anyhow::{Result, bail};
use nvml_wrapper::{
    device::Device,
    enums::device::UsedGpuMemory,
    error::NvmlError,
    struct_wrappers::device::{ProcessInfo, ProcessUtilizationSample},
};
use serde_json::{Value, json};
use std::{collections::HashMap, fs};

fn display_name(pid: u32) -> String {
    if let Some(name) = fs::read_link(format!("/proc/{pid}/exe"))
        .ok()
        .and_then(|path| {
            path.file_name()
                .map(|name| name.to_string_lossy().into_owned())
        })
    {
        return name
            .strip_prefix('.')
            .and_then(|name| name.strip_suffix("-wrapped"))
            .unwrap_or(&name)
            .to_owned();
    }
    fs::read(format!("/proc/{pid}/comm"))
        .ok()
        .map(|bytes| {
            String::from_utf8_lossy(&bytes)
                .trim()
                .chars()
                .map(|c| if c.is_control() { ' ' } else { c })
                .collect()
        })
        .unwrap_or_else(|| format!("PID {pid}"))
}

fn retry_size<T>(mut query: impl FnMut() -> Result<T, NvmlError>) -> Result<T, NvmlError> {
    // Process lists can grow between NVML's count and data calls. Retry once.
    match query() {
        Err(NvmlError::InsufficientSize(_)) => query(),
        result => result,
    }
}

fn supported<T>(result: Result<T, NvmlError>) -> Result<Option<T>, NvmlError> {
    match result {
        Ok(value) => Ok(Some(value)),
        Err(NvmlError::NotSupported | NvmlError::FunctionNotFound | NvmlError::NoPermission) => {
            Ok(None)
        }
        Err(error) => Err(error),
    }
}

pub fn read(device: &Device<'_>, since: u64) -> Result<Value> {
    let graphics = supported(retry_size(|| device.running_graphics_processes()))?;
    let compute = supported(retry_size(|| device.running_compute_processes()))?;
    if graphics.is_none() && compute.is_none() {
        bail!("GPU process lists unavailable");
    }
    let samples = match retry_size(|| device.process_utilization_stats(Some(since))) {
        // No recent sample is not a driver failure, nor proof of zero activity.
        Err(NvmlError::NotFound) => Some(Vec::new()),
        result => supported(result)?,
    };
    Ok(rank(
        graphics
            .into_iter()
            .flatten()
            .chain(compute.into_iter().flatten()),
        samples,
        since,
        display_name,
    ))
}

fn rank(
    processes: impl Iterator<Item = ProcessInfo>,
    samples: Option<Vec<ProcessUtilizationSample>>,
    since: u64,
    name: impl Fn(u32) -> String,
) -> Value {
    let by_memory = samples.is_none();
    let mut usage: HashMap<u32, (u64, u32)> = HashMap::new();
    for sample in samples.into_iter().flatten() {
        if sample.timestamp > since && sample.sm_util <= 100 {
            let latest = usage.entry(sample.pid).or_insert((0, 0));
            if sample.timestamp > latest.0 {
                *latest = (sample.timestamp, sample.sm_util);
            }
        }
    }
    let mut pids: HashMap<u32, Option<u64>> = HashMap::new();
    for process in processes {
        let bytes = match process.used_gpu_memory {
            UsedGpuMemory::Used(n) => Some(n),
            _ => None,
        };
        let memory = pids.entry(process.pid).or_default();
        // A process present in both contexts does not use its memory twice.
        *memory = (*memory).max(bytes);
    }
    let mut rows: Vec<_> = pids
        .into_iter()
        .map(|(pid, memory)| (pid, memory, usage.get(&pid).map(|(_, n)| *n)))
        .collect();
    rows.sort_by(|a, b| {
        let primary = if by_memory {
            b.1.cmp(&a.1)
        } else {
            b.2.cmp(&a.2).then(b.1.cmp(&a.1))
        };
        primary.then(a.0.cmp(&b.0))
    });
    let rows: Vec<_> = rows.into_iter().take(5).map(|(pid,memory,usage)|
        json!({"pid":pid,"name":name(pid),"usage":usage,"memoryBytes":memory})).collect();
    json!({"sort":if by_memory {"vram"} else {"gpu"},"rows":rows})
}

#[cfg(test)]
mod tests {
    use super::*;
    fn process(pid: u32, memory: u64) -> ProcessInfo {
        ProcessInfo {
            pid,
            used_gpu_memory: UsedGpuMemory::Used(memory),
            gpu_instance_id: None,
            compute_instance_id: None,
        }
    }
    fn sample(pid: u32, time: u64, usage: u32) -> ProcessUtilizationSample {
        ProcessUtilizationSample {
            pid,
            timestamp: time,
            sm_util: usage,
            mem_util: 0,
            enc_util: 0,
            dec_util: 0,
        }
    }
    #[test]
    fn merges_contexts_filters_stale_samples_and_ranks_latest_activity() {
        let report = rank(
            vec![
                process(1, 100),
                process(1, 100),
                process(2, 50),
                process(3, 5),
            ]
            .into_iter(),
            Some(vec![
                sample(1, 15, 90),
                sample(1, 19, 5),
                sample(2, 16, 25),
                sample(3, 9, 100),
                sample(99, 20, 100),
            ]),
            10,
            |pid| pid.to_string(),
        );
        assert_eq!(report["sort"], "gpu");
        assert_eq!(report["rows"].as_array().unwrap().len(), 3);
        assert_eq!(report["rows"][0]["pid"], 2);
        assert_eq!(report["rows"][1]["usage"], 5);
        assert_eq!(report["rows"][1]["memoryBytes"], 100);
        assert!(report["rows"][2]["usage"].is_null());
    }
    #[test]
    fn unsupported_utilization_explicitly_falls_back_to_vram_and_bounds_rows() {
        let report = rank(
            (1..=8).map(|pid| process(pid, pid as u64)),
            None,
            0,
            |pid| pid.to_string(),
        );
        assert_eq!(report["sort"], "vram");
        assert_eq!(report["rows"].as_array().unwrap().len(), 5);
        assert_eq!(report["rows"][0]["pid"], 8);
        assert!(report["rows"][0]["usage"].is_null());
    }
    #[test]
    fn growing_buffers_are_retried_once_not_forever() {
        let mut calls = 0;
        let value = retry_size(|| {
            calls += 1;
            if calls == 1 {
                Err(NvmlError::InsufficientSize(None))
            } else {
                Ok(7)
            }
        })
        .unwrap();
        assert_eq!((value, calls), (7, 2));
        calls = 0;
        assert!(
            retry_size::<()>(|| {
                calls += 1;
                Err(NvmlError::InsufficientSize(None))
            })
            .is_err()
        );
        assert_eq!(calls, 2);
    }
}
