use super::*;
use serde_json::json;

#[derive(Default)]
struct FakeBackend {
    calls: Vec<String>,
    resets: usize,
    failing: bool,
    top_calls: usize,
    top_failing: bool,
}

impl Backend for FakeBackend {
    fn read(&mut self, address: &str) -> Result<Metrics> {
        self.calls.push(address.into());
        if self.failing {
            anyhow::bail!("driver unavailable");
        }
        Ok(Metrics {
            name: Some("Test NVIDIA".into()),
            usage: Some(0),
            temperature_c: Some(42),
            memory_used_bytes: Some(512 * 1024 * 1024),
            memory_total_bytes: Some(4 * 1024 * 1024 * 1024),
        })
    }
    fn reset(&mut self) {
        self.resets += 1;
    }
    fn processes(&mut self, _address: &str, _since: u64) -> Result<serde_json::Value> {
        self.top_calls += 1;
        if self.top_failing {
            anyhow::bail!("process permissions denied");
        }
        Ok(json!({"sort":"gpu","rows":[{"pid":1,"name":"test","usage":5,"memoryBytes":1024}]}))
    }
}

fn device(root: &Path, address: &str, vendor: &str, class: &str, power: &str) -> PathBuf {
    let path = root.join(address);
    fs::create_dir_all(path.join("power")).unwrap();
    fs::write(path.join("vendor"), vendor).unwrap();
    fs::write(path.join("class"), class).unwrap();
    fs::write(path.join("power/runtime_status"), power).unwrap();
    path
}

fn fixture(power: &str) -> (tempfile::TempDir, PathBuf, Sampler<FakeBackend>) {
    let temp = tempfile::tempdir().unwrap();
    let gpu = device(temp.path(), "0000:01:00.0", "0x10de", "0x030000", power);
    let sampler = Sampler::new(temp.path().into(), FakeBackend::default());
    (temp, gpu, sampler)
}

#[test]
fn cold_sleep_and_power_transitions_never_query_nvml() {
    let (_temp, gpu, mut sampler) = fixture("suspended\n");
    for (index, state) in ["suspended", "suspending", "resuming"]
        .into_iter()
        .enumerate()
    {
        fs::write(gpu.join("power/runtime_status"), state).unwrap();
        let report =
            serde_json::to_value(sampler.sample(Duration::from_secs(index as u64))).unwrap();
        assert_eq!(report["text"], "Off");
        assert_eq!(report["gpu"]["poweredOn"], false);
        for field in [
            "usage",
            "temperatureC",
            "memoryUsedBytes",
            "memoryTotalBytes",
        ] {
            assert!(report["gpu"][field].is_null());
        }
    }
    assert!(sampler.backend.calls.is_empty());
}

#[test]
fn unreadable_or_unknown_power_state_never_assumes_active() {
    let (_temp, gpu, mut sampler) = fixture("unknown");
    for state in ["unknown", "unsupported", "", "not-active"] {
        fs::write(gpu.join("power/runtime_status"), state).unwrap();
        let report = sampler.sample(Duration::ZERO);
        assert_eq!(report.text, "--");
        assert!(report.gpu.is_none());
    }
    fs::remove_file(gpu.join("power/runtime_status")).unwrap();
    assert!(sampler.sample(Duration::ZERO).gpu.is_none());
    assert!(sampler.backend.calls.is_empty());
}

#[test]
fn live_schema_bytes_zero_and_text_are_compatible() {
    let (_temp, _gpu, mut sampler) = fixture("active\n");
    let report = serde_json::to_value(sampler.sample(Duration::ZERO)).unwrap();
    assert_eq!(
        report,
        json!({"text":"0%|13%", "gpu": {
            "name":"Test NVIDIA", "poweredOn":true, "usage":0, "temperatureC":42,
            "memoryUsedBytes":536870912_u64, "memoryTotalBytes":4294967296_u64
        }})
    );
    assert_eq!(sampler.backend.calls, ["0000:01:00.0"]);
}

#[test]
fn sleep_keeps_only_the_name_and_wake_resumes_sampling() {
    let (_temp, gpu, mut sampler) = fixture("active");
    sampler.sample(Duration::ZERO);
    fs::write(gpu.join("power/runtime_status"), "suspended").unwrap();
    let sleep = sampler.sample(Duration::from_secs(1));
    let details = sleep.gpu.unwrap();
    assert_eq!(details.metrics.name.as_deref(), Some("Test NVIDIA"));
    assert!(details.metrics.usage.is_none());
    assert!(details.metrics.memory_used_bytes.is_none());
    assert_eq!(sampler.backend.calls.len(), 1);
    fs::write(gpu.join("power/runtime_status"), "active").unwrap();
    assert!(
        sampler
            .sample(Duration::from_secs(2))
            .gpu
            .unwrap()
            .powered_on
    );
    assert_eq!(sampler.backend.calls.len(), 2);
}

#[test]
fn errors_are_rate_limited_and_recover_without_process_restart() {
    let (_temp, gpu, mut sampler) = fixture("active");
    sampler.backend.failing = true;
    assert!(sampler.sample(Duration::ZERO).gpu.is_none());
    sampler.backend.failing = false;
    assert!(sampler.sample(Duration::from_secs(29)).gpu.is_none());
    assert_eq!(sampler.backend.calls.len(), 1);
    fs::write(gpu.join("power/runtime_status"), "suspended").unwrap();
    assert_eq!(sampler.sample(Duration::from_secs(29)).text, "Off");
    fs::write(gpu.join("power/runtime_status"), "active").unwrap();
    assert!(sampler.sample(Duration::from_secs(30)).error.is_none());
    assert_eq!(sampler.backend.calls.len(), 2);
}

#[test]
fn discovery_filters_audio_other_vendors_and_is_deterministic() {
    let temp = tempfile::tempdir().unwrap();
    device(temp.path(), "0000:00:02.0", "0x8086", "0x030000", "active");
    device(temp.path(), "0000:01:00.1", "0x10de", "0x040300", "active");
    assert_eq!(discover(temp.path()).unwrap(), None);
    device(temp.path(), "0000:03:00.0", "0x10de", "0x030200", "active");
    device(temp.path(), "0000:02:00.0", "0x10de", "0x030000", "active");
    assert_eq!(
        discover(temp.path()).unwrap().as_deref(),
        Some("0000:02:00.0")
    );
}

#[test]
fn unplug_replug_resets_identity_and_backend() {
    let (_temp, gpu, mut sampler) = fixture("active");
    sampler.sample(Duration::ZERO);
    assert_eq!(sampler.backend.resets, 1);
    fs::write(gpu.join("vendor"), "0xffff").unwrap();
    assert!(sampler.sample(Duration::from_secs(1)).gpu.is_none());
    assert!(sampler.name.is_none());
    fs::write(gpu.join("vendor"), "0x10de").unwrap();
    sampler.sample(Duration::from_secs(2));
    assert_eq!(sampler.backend.resets, 3);
    assert_eq!(sampler.backend.calls.len(), 2);
}

#[test]
fn absent_pci_root_does_not_call_backend() {
    let temp = tempfile::tempdir().unwrap();
    let mut sampler = Sampler::new(temp.path().join("missing"), FakeBackend::default());
    assert!(sampler.sample(Duration::ZERO).gpu.is_none());
    assert!(sampler.backend.calls.is_empty());
}

#[test]
fn unknown_values_do_not_turn_into_zero_and_large_values_do_not_overflow() {
    assert_eq!(Report::active(Metrics::default()).text, "--");
    assert_eq!(
        Report::active(Metrics {
            usage: Some(0),
            ..Default::default()
        })
        .text,
        "0%"
    );
    assert_eq!(
        Report::active(Metrics {
            memory_used_bytes: Some(0),
            memory_total_bytes: Some(100),
            ..Default::default()
        })
        .text,
        "--|0%"
    );
    assert_eq!(
        Report::active(Metrics {
            memory_used_bytes: Some(u64::MAX),
            memory_total_bytes: Some(u64::MAX),
            ..Default::default()
        })
        .text,
        "--|100%"
    );
}

#[test]
fn top_queries_are_optional_throttled_and_never_run_in_sleep() {
    let (_temp, gpu, mut sampler) = fixture("suspended");
    let sleeping = sampler.sample_with_top(Duration::ZERO, 1);
    assert_eq!(sleeping.top.unwrap()["state"], "sleeping");
    assert_eq!(sampler.backend.top_calls, 0);
    assert!(sampler.backend.calls.is_empty());
    fs::write(gpu.join("power/runtime_status"), "active").unwrap();
    assert!(
        sampler
            .sample_with_top(Duration::from_secs(1), 1)
            .top
            .is_none()
    );
    let active = sampler.sample_with_top(Duration::from_secs(2), 1);
    assert_eq!(active.top.unwrap()["generation"], 1);
    assert_eq!(sampler.backend.top_calls, 1);
    assert!(
        sampler
            .sample_with_top(Duration::from_secs(3), 0)
            .top
            .is_none()
    );
    assert!(
        sampler
            .sample_with_top(Duration::from_secs(9), 0)
            .top
            .is_none()
    );
    assert_eq!(sampler.backend.top_calls, 1);
    assert_eq!(
        sampler
            .sample_with_top(Duration::from_secs(10), 2)
            .top
            .unwrap()["generation"],
        2
    );
    assert_eq!(sampler.backend.top_calls, 2);
    fs::write(gpu.join("power/runtime_status"), "unknown").unwrap();
    assert!(
        sampler
            .sample_with_top(Duration::from_secs(12), 2)
            .gpu
            .is_none()
    );
    assert_eq!(sampler.backend.top_calls, 2);
}

#[test]
fn top_failure_does_not_invalidate_global_metrics() {
    let (_temp, _gpu, mut sampler) = fixture("active");
    sampler.backend.top_failing = true;
    let report = sampler.sample_with_top(Duration::ZERO, 1);
    assert!(report.gpu.unwrap().powered_on);
    assert!(report.error.is_none());
    assert!(report.top.unwrap()["error"].is_string());
    sampler.backend.failing = true;
    let report = sampler.sample_with_top(Duration::from_secs(2), 1);
    assert!(report.gpu.is_none());
    assert_eq!(sampler.backend.top_calls, 1);
}
