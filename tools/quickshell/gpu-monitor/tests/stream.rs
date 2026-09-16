use serde_json::Value;
use std::{
    fs,
    io::{BufRead, BufReader},
    process::{Command, Stdio},
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

#[test]
fn streams_without_a_driver_and_exits_when_reader_closes() {
    // An empty fake PCI tree guarantees no NVML access, even on a GPU host.
    let temp = tempfile::tempdir().unwrap();
    let mut child = Command::new(env!("CARGO_BIN_EXE_quickshell-gpu-monitor"))
        .args(["--sysfs-root"])
        .arg(temp.path())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let stdout = child.stdout.take().unwrap();
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || {
        let mut reader = BufReader::new(stdout);
        for _ in 0..2 {
            let mut line = String::new();
            reader.read_line(&mut line).unwrap();
            tx.send(line).unwrap();
        }
    });
    for _ in 0..2 {
        let line = rx
            .recv_timeout(Duration::from_secs(5))
            .unwrap_or_else(|error| {
                let _ = child.kill();
                let _ = child.wait();
                panic!("Missing telemetry: {error}");
            });
        let report: Value = serde_json::from_str(&line).unwrap();
        assert_eq!(report["text"], "--");
        assert!(report["gpu"].is_null());
        assert!(report["error"].is_string());
    }
    let start = Instant::now();
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            assert!(status.success());
            break;
        }
        if start.elapsed() > Duration::from_secs(5) {
            let _ = child.kill();
            let _ = child.wait();
            panic!("Collector survived a closed pipe");
        }
        thread::sleep(Duration::from_millis(25));
    }
}

#[test]
fn cold_sleep_single_sample_is_valid_without_driver_or_config() {
    let temp = tempfile::tempdir().unwrap();
    let device = temp.path().join("0000:01:00.0");
    fs::create_dir_all(device.join("power")).unwrap();
    fs::write(device.join("vendor"), "0x10de").unwrap();
    fs::write(device.join("class"), "0x030000").unwrap();
    fs::write(device.join("power/runtime_status"), "suspended").unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_quickshell-gpu-monitor"))
        .args(["--once", "--sysfs-root"])
        .arg(temp.path())
        .output()
        .unwrap();
    assert!(output.status.success());
    assert!(output.stderr.is_empty());
    let report: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["text"], "Off");
    assert_eq!(report["gpu"]["poweredOn"], false);
    assert!(report["gpu"]["usage"].is_null());
}

#[test]
fn invalid_arguments_fail_without_starting_telemetry() {
    for args in [&["--sysfs-root"][..], &["--unknown"][..]] {
        let result = Command::new(env!("CARGO_BIN_EXE_quickshell-gpu-monitor"))
            .args(args)
            .output()
            .unwrap();
        assert!(!result.status.success());
        assert!(result.stdout.is_empty());
    }
}
