//! Monitor tests use fake commands and never access the real hardware.
use serde_json::{Value, json};
use std::{
    env, fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output, Stdio},
};
const BRIGHTNESS: &str = env!("CARGO_BIN_EXE_quickshell-brightness");

struct Fixture {
    temp: tempfile::TempDir,
}
impl Fixture {
    fn new() -> Self {
        let this = Self {
            temp: tempfile::tempdir().unwrap(),
        };
        fs::create_dir(this.path("bin")).unwrap();
        this.json(
            "monitors.json",
            &json!([{"name":"DP-1","model":"U2720Q","serial":"ABC"}, {"name":"eDP-1"}]),
        );
        for name in ["hyprctl", "ddcutil", "brightnessctl"] {
            let shell = env::var("QS_TEST_SHELL").unwrap_or_else(|_| "/bin/sh".into());
            fs::write(
                this.path(&format!("bin/{name}")),
                format!("#!{shell}\n{MOCK}"),
            )
            .unwrap();
            fs::set_permissions(
                this.path(&format!("bin/{name}")),
                fs::Permissions::from_mode(0o755),
            )
            .unwrap();
        }
        this
    }
    fn path(&self, path: &str) -> PathBuf {
        self.temp.path().join(path)
    }
    fn json(&self, path: &str, value: &Value) {
        fs::write(self.path(path), value.to_string()).unwrap();
    }
    fn log(&self) -> String {
        fs::read_to_string(self.path("commands")).unwrap_or_default()
    }
    fn command(&self, binary: &str) -> Command {
        let mut cmd = Command::new(binary);
        cmd.env(
            "PATH",
            format!(
                "{}:{}",
                self.path("bin").display(),
                env::var("PATH").unwrap()
            ),
        )
        .env("FAKE_ROOT", self.temp.path())
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
        cmd
    }
}
fn success(output: Output) -> Value {
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).unwrap()
}
const MOCK: &str = r#"
set -eu
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$FAKE_ROOT/commands"
case "$name" in
  hyprctl) cat "$FAKE_ROOT/monitors.json" ;;
  brightnessctl)
    if [ "$#" = 5 ]; then printf 'panel,backlight,50,%s,100\n' "$5"
    else printf 'panel,backlight,98,98%%,100\n'; fi ;;
  ddcutil)
    case "$*" in
      '--brief detect')
        printf 'Display 1\n I2C bus: /dev/i2c-991234\n DRM connector: card0-DP-1\n Monitor: DEL:U2720Q:ABC\n' ;;
      *'getvcp 10') printf 'VCP 10 C 98 100\n' ;;
      *'setvcp 10'*) [ "${FAKE_DDC_FAIL:-0}" != 1 ] ;;
      *) exit 2 ;;
    esac ;;
  *) exit 99 ;;
esac
"#;

#[test]
fn brightness_external_burst_and_stale_cache() {
    let f = Fixture::new();
    // Missing bus must invalidate even a fresh, otherwise plausible cache.
    let previous = json!({"monitor":"DP-1","model":"U2720Q","serial":"ABC","bus":991234,
        "current":5,"maximum":100,"checkedAt":quickshell_brightness::now()});
    let out = success(
        f.command(BRIGHTNESS)
            .args(["DP-1", "[5,-5]", &previous.to_string()])
            .output()
            .unwrap(),
    );
    assert_eq!(out["brightness"], 95);
    assert_eq!(out["monitor"], "DP-1");
    let log = f.log();
    assert!(log.contains("--brief detect"));
    assert!(log.contains("getvcp 10"));
    assert_eq!(
        log.lines().filter(|s| s.contains("setvcp 10 95")).count(),
        1
    );
    assert!(!log.contains("noverify"));
}

#[test]
fn brightness_internal_and_ambiguous_display() {
    let f = Fixture::new();
    assert_eq!(
        success(
            f.command(BRIGHTNESS)
                .args(["eDP-1", "[5,-5]"])
                .output()
                .unwrap()
        )["brightness"],
        95
    );
    assert!(!f.log().contains("ddcutil"));
    f.json(
        "monitors.json",
        &json!([{"name":"DP-1","model":"X","serial":"Y"},{"name":"DP-2","model":"X","serial":"Y"}]),
    );
    assert!(
        !f.command(BRIGHTNESS)
            .args(["DP-1", "5"])
            .output()
            .unwrap()
            .status
            .success()
    );
    assert!(!f.log().contains("ddcutil"));
}

#[test]
fn failed_ddc_write_never_reports_success() {
    let f = Fixture::new();
    let out = f
        .command(BRIGHTNESS)
        .args(["DP-1", "-5"])
        .env("FAKE_DDC_FAIL", "1")
        .output()
        .unwrap();
    assert!(!out.status.success());
    assert!(out.stdout.is_empty());
}
