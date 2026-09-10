//! Fake TabCtl only: never list, focus or close the user's real tabs.
use nix::{
    sys::signal::{Signal, kill},
    unistd::Pid,
};
use serde_json::{Value, json};
use std::{
    env, fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};

const BIN: &str = env!("CARGO_BIN_EXE_quickshell-chrome-tabs");
struct Fixture {
    temp: tempfile::TempDir,
}
impl Fixture {
    fn new() -> Self {
        let f = Self {
            temp: tempfile::tempdir().unwrap(),
        };
        fs::create_dir(f.path("bin")).unwrap();
        let shell = env::var("QS_TEST_SHELL").unwrap_or_else(|_| "/bin/sh".into());
        fs::write(f.path("bin/tabctl"), format!("#!{shell}\n{MOCK}")).unwrap();
        fs::set_permissions(f.path("bin/tabctl"), fs::Permissions::from_mode(0o755)).unwrap();
        f
    }
    fn path(&self, name: &str) -> PathBuf {
        self.temp.path().join(name)
    }
    fn command(&self, args: &[&str]) -> Command {
        let mut cmd = Command::new(BIN);
        cmd.args(args)
            .env(
                "PATH",
                format!(
                    "{}:{}",
                    self.path("bin").display(),
                    env::var("PATH").unwrap()
                ),
            )
            .env("HOME", self.temp.path())
            .env("XDG_CONFIG_HOME", self.path("config"))
            .env("XDG_CACHE_HOME", self.path("cache"))
            .env("FAKE_ROOT", self.temp.path())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .stdin(Stdio::null());
        cmd
    }
    fn json(&self, args: &[&str], mode: &str) -> Value {
        let out = self.command(args).env("FAKE_MODE", mode).output().unwrap();
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        serde_json::from_slice(&out.stdout).unwrap()
    }
}
const MOCK: &str = r#"
set -eu
printf '%s\n' "$@" > "$FAKE_ROOT/args"
case "${FAKE_MODE:-ok}" in
    error) printf 'Error: Chrome unavailable\nextra diagnostic\n' >&2; exit 1 ;;
    malformed) printf 'not json'; exit 0 ;;
    sleep) printf '%s' "$$" > "$FAKE_ROOT/pid"; exec sleep 60 ;;
esac
if [ "$1" = --format ]; then
    printf '[{"id":"7","title":"Example","url":"https://example.test/"}]\n'
elif [ "$1" = status ]; then
    printf 'native status\n'; exit 7
fi
"#;

#[test]
fn lists_tabs_without_a_chrome_database() {
    let f = Fixture::new();
    assert_eq!(
        f.json(&["list"], "ok"),
        json!({"ok":true,"tabs":[{"id":"7","title":"Example","url":"https://example.test/","iconPath":""}]})
    );
    assert_eq!(
        fs::read_to_string(f.path("args")).unwrap(),
        "--format\njson\nlist\n"
    );
    assert!(!f.path("config").exists());
}
#[test]
fn tab_actions_forward_arguments_without_shell_evaluation() {
    let f = Fixture::new();
    let id = "7; touch unexpected";
    assert_eq!(f.json(&["activate", id], "ok"), json!({"ok":true}));
    assert_eq!(
        fs::read_to_string(f.path("args")).unwrap(),
        format!("activate\n--focused\n{id}\n")
    );
    assert_eq!(f.json(&["close", "7"], "ok"), json!({"ok":true}));
    assert_eq!(fs::read_to_string(f.path("args")).unwrap(), "close\n7\n");
}
#[test]
fn failures_keep_the_qml_json_protocol() {
    let f = Fixture::new();
    assert_eq!(
        f.json(&["list"], "error"),
        json!({"ok":false,"tabs":[],"error":"Chrome unavailable"})
    );
    assert_eq!(
        f.json(&["close", "7"], "error"),
        json!({"ok":false,"error":"Chrome unavailable"})
    );
    assert_eq!(
        f.json(&["list"], "malformed"),
        json!({"ok":false,"tabs":[],"error":"Invalid TabCtl response"})
    );
    let out = f
        .command(&["list"])
        .env("PATH", f.path("missing"))
        .output()
        .unwrap();
    assert!(out.status.success());
    assert_eq!(
        serde_json::from_slice::<Value>(&out.stdout).unwrap()["ok"],
        false
    );
}
#[test]
fn status_is_passed_through_and_invalid_usage_fails() {
    let f = Fixture::new();
    let out = f.command(&["status"]).output().unwrap();
    assert_eq!(out.status.code(), Some(7));
    assert_eq!(out.stdout, b"native status\n");
    for args in [vec![], vec!["unknown"], vec!["close"], vec!["activate", ""]] {
        assert_eq!(f.command(&args).output().unwrap().status.code(), Some(2));
    }
}
#[test]
fn cancellation_terminates_tabctl_and_emits_no_stale_success() {
    let f = Fixture::new();
    let mut child = f
        .command(&["list"])
        .env("FAKE_MODE", "sleep")
        .spawn()
        .unwrap();
    let start = Instant::now();
    while !f.path("pid").exists() {
        assert!(child.try_wait().unwrap().is_none());
        if start.elapsed() > Duration::from_secs(5) {
            let _ = child.kill();
            let _ = child.wait();
            panic!("TabCtl did not start");
        }
        thread::sleep(Duration::from_millis(20));
    }
    kill(Pid::from_raw(child.id() as i32), Signal::SIGTERM).unwrap();
    let start = Instant::now();
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            assert_eq!(status.code(), Some(143));
            break;
        }
        if start.elapsed() > Duration::from_secs(5) {
            let _ = child.kill();
            let _ = child.wait();
            panic!("TabCtl was not cancelled");
        }
        thread::sleep(Duration::from_millis(20));
    }
    let pid = fs::read_to_string(f.path("pid")).unwrap().parse().unwrap();
    assert!(kill(Pid::from_raw(pid), None).is_err());
    assert!(child.wait_with_output().unwrap().stdout.is_empty());
}
