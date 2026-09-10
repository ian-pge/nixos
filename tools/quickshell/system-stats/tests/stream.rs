use serde_json::Value;
use std::{
    io::{BufRead, BufReader},
    process::{Command, Stdio},
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

#[test]
fn emits_json_lines_and_stops_when_reader_closes() {
    let mut child = Command::new(env!("CARGO_BIN_EXE_quickshell-system-stats"))
        .stdout(Stdio::piped())
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
                panic!("missing telemetry: {error}");
            });
        let value: Value = serde_json::from_str(&line).unwrap();
        assert!(
            ["cpu", "memory", "disk", "brightness"]
                .iter()
                .all(|key| value[key].as_u64().is_some_and(|n| n <= 100)),
            "invalid telemetry: {value}"
        );
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
            panic!("telemetry survived a closed pipe");
        }
        thread::sleep(Duration::from_millis(25));
    }
}
