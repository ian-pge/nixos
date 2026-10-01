use serde_json::Value;
use std::{
    fs,
    process::Command,
    time::{SystemTime, UNIX_EPOCH},
};

#[test]
fn binary_publishes_a_complete_report_without_private_names() {
    let fixture = tempfile::tempdir().unwrap();
    let root = fixture.path().join("root");
    let cache = root.join("home/test/.cache");
    fs::create_dir_all(&cache).unwrap();
    fs::write(cache.join("private-test-filename"), vec![1_u8; 8192]).unwrap();
    let output = fixture.path().join("report.json");
    let start = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64;
    let status = Command::new(env!("CARGO_BIN_EXE_quickshell-storage"))
        .arg("--home")
        .arg("/home/test")
        .arg("--root")
        .arg(&root)
        .arg("--output")
        .arg(&output)
        .status()
        .unwrap();
    assert!(status.success());
    let text = fs::read_to_string(output).unwrap();
    assert!(!text.contains("private-test-filename"));
    let report: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(report["schemaVersion"], 1);
    assert!(report["measuredAt"].as_u64().unwrap() >= start);
    assert!(report["disk"]["totalBytes"].as_u64().unwrap() > 0);
    assert_eq!(report["estimated"], true);
    assert_eq!(report["errors"]["count"], 0);
    let categories = report["categories"].as_array().unwrap();
    assert_eq!(categories.len(), 6);
    let applications = categories
        .iter()
        .find(|category| category["id"] == "applications")
        .unwrap();
    assert!(applications["cacheBytes"].as_u64().unwrap() >= 8192);
    assert_eq!(applications["partial"], false);
}
