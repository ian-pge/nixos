//! End-to-end tests use isolated files and fake commands, never real monitor
//! writes, flake updates, builds or privilege elevation.
use nix::{
    sys::signal::{Signal, kill},
    unistd::Pid,
};
use serde_json::{Value, json};
use std::{
    env, fs,
    io::Write,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Child, Command, Output, Stdio},
    thread,
    time::{Duration, Instant},
};

const CHECKER: &str = env!("CARGO_BIN_EXE_quickshell-update-checker");
const INSTALLER: &str = env!("CARGO_BIN_EXE_quickshell-update-installer");
const BRIGHTNESS: &str = env!("CARGO_BIN_EXE_quickshell-brightness");

struct Fixture {
    temp: tempfile::TempDir,
}
impl Fixture {
    fn new() -> Self {
        let this = Self {
            temp: tempfile::tempdir().unwrap(),
        };
        for dir in ["bin", "flake", "cache", "store"] {
            fs::create_dir(this.path(dir)).unwrap();
        }
        fs::write(this.path("flake/flake.nix"), "{ outputs = _: {}; }").unwrap();
        this.json("flake/flake.lock", &lock("old"));
        this.json("new.lock", &lock("new"));
        this.json(
            "monitors.json",
            &json!([{"name":"DP-1","model":"U2720Q","serial":"ABC"}, {"name":"eDP-1"}]),
        );
        for name in ["nix", "nh", "hyprctl", "ddcutil", "brightnessctl", "qs"] {
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
        .env("NIXOS_FLAKE_DIR", self.path("flake"))
        .env("XDG_CACHE_HOME", self.path("cache"))
        .env("QS_CURRENT_SYSTEM_LINK", self.path("current"))
        .env("QS_SYSTEM_PROFILE", self.path("profile"))
        .env("QS_STORE_DIR", self.path("store"))
        .env("QS_UPDATE_ACTIVATOR", "/tmp/not-immutable")
        .env("QS_UPDATE_ELEVATOR", "/tmp/not-immutable/bin/run0")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
        cmd
    }
    fn read_json(&self, path: &str) -> Value {
        serde_json::from_slice(&fs::read(self.path(path)).unwrap()).unwrap()
    }
    fn log(&self) -> String {
        fs::read_to_string(self.path("commands")).unwrap_or_default()
    }
    fn original_restored(&self) {
        assert_eq!(self.read_json("flake/flake.lock"), lock("old"));
        assert!(!self.path("cache/quickshell/top-bar/update-result").exists());
    }
    fn configure_system(&self) -> PathBuf {
        let system = env::var_os("QS_TEST_SYSTEM")
            .map(PathBuf::from)
            .unwrap_or_else(|| "/run/current-system".into())
            .canonicalize()
            .unwrap();
        std::os::unix::fs::symlink(&system, self.path("current")).unwrap();
        let mut info = serde_json::Map::new();
        for path in [&system, &system.join("sw").canonicalize().unwrap()] {
            info.insert(
                path.file_name().unwrap().to_str().unwrap().to_string(),
                json!({"references":[]}),
            );
        }
        self.json(
            "path-info.json",
            &json!({"version":2,"storeDir":"/nix/store","info":info}),
        );
        system
    }
}

fn lock(rev: &str) -> Value {
    json!({"version":7,"root":"root","nodes":{"root":{"inputs":{"nixpkgs":"nixpkgs"}},
        "nixpkgs":{"locked":{"rev":rev,"lastModified":1}}}})
}
fn success(output: Output) -> Value {
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).unwrap()
}
fn wait_for(path: &Path, child: &mut Child) {
    let start = Instant::now();
    while !path.exists() {
        assert!(
            child.try_wait().unwrap().is_none(),
            "helper exited before reaching checkpoint"
        );
        assert!(
            start.elapsed() < Duration::from_secs(10),
            "helper timed out"
        );
        thread::sleep(Duration::from_millis(20));
    }
}
fn wait_exit(child: &mut Child) -> std::process::ExitStatus {
    let start = Instant::now();
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            return status;
        }
        if start.elapsed() > Duration::from_secs(10) {
            let _ = child.kill();
            let _ = child.wait();
            panic!("helper did not exit");
        }
        thread::sleep(Duration::from_millis(20));
    }
}

const MOCK: &str = r#"
set -eu
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$FAKE_ROOT/commands"
case "$name" in
  nix)
    if [ "$1" = path-info ]; then cat "$FAKE_ROOT/path-info.json"; exit; fi
    if [ "${FAKE_NIX_FAIL:-0}" = 1 ]; then exit 1; fi
    target=$PWD
    while [ "$#" -gt 0 ]; do
      if [ "$1" = --flake ]; then target=$2; shift 2; else shift; fi
    done
    cp "$FAKE_ROOT/new.lock" "$target/flake.lock"
    ;;
  nh)
    case "${FAKE_NH_MODE:-fail}" in
      fail) exit 1 ;;
      sleep)
        printf '%s\n' "$$" > "$FAKE_ROOT/child-pid"
        touch "$FAKE_ROOT/building"
        exec sleep 60 ;;
      ok)
        while [ "$1" != --out-link ]; do shift; done
        ln -s "$FAKE_RESULT" "$2" ;;
    esac
    ;;
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
  qs) exit 99 ;; # Never contact a real Quickshell instance.
  *) exit 99 ;;
esac
"#;

#[test]
fn cache_reuse_source_invalidation_and_build_failure() {
    let f = Fixture::new();
    assert_eq!(
        success(f.command(CHECKER).arg("force").output().unwrap())["hasUpdates"],
        true
    );
    success(f.command(CHECKER).output().unwrap());
    assert_eq!(f.log().lines().filter(|s| s.starts_with("nix ")).count(), 1);
    let out = f.command(INSTALLER).output().unwrap();
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stdout).contains("Reusing the lockfile"));
    f.original_restored();
    fs::write(f.path("flake/flake.nix"), "changed").unwrap();
    let out = f.command(INSTALLER).output().unwrap();
    assert!(!out.status.success());
    assert!(!String::from_utf8_lossy(&out.stdout).contains("Reusing the lockfile"));
    assert_eq!(f.log().lines().filter(|s| s.starts_with("nix ")).count(), 2);
    f.original_restored();
    assert!(
        !f.path("cache/quickshell/top-bar/update-candidate.lock")
            .exists()
    );
}

#[test]
fn failed_check_is_structured_and_retried() {
    let f = Fixture::new();
    assert_eq!(
        success(
            f.command(CHECKER)
                .env("FAKE_NIX_FAIL", "1")
                .output()
                .unwrap()
        )["state"],
        "error"
    );
    assert!(
        !f.path("cache/quickshell/top-bar/update-candidate.lock")
            .exists()
    );
    assert_eq!(success(f.command(CHECKER).output().unwrap())["state"], "ok");
    f.original_restored();
}

#[test]
fn absent_lockfile_is_removed_after_failure() {
    let f = Fixture::new();
    fs::remove_file(f.path("flake/flake.lock")).unwrap();
    assert!(!f.command(INSTALLER).output().unwrap().status.success());
    assert!(!f.path("flake/flake.lock").exists());
}

#[test]
fn checker_and_shell_cleaner_share_the_same_lock() {
    let f = Fixture::new();
    let cache = f.path("cache/quickshell/top-bar");
    fs::create_dir_all(&cache).unwrap();
    let lock_path = cache.join("updates.lock");
    let lock = fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(&lock_path)
        .unwrap();
    fs2::FileExt::lock_exclusive(&lock).unwrap();
    assert!(
        !Command::new("flock")
            .arg("-n")
            .arg(&lock_path)
            .arg("true")
            .status()
            .unwrap()
            .success()
    );
    let mut child = f.command(CHECKER).spawn().unwrap();
    thread::sleep(Duration::from_millis(100));
    assert!(child.try_wait().unwrap().is_none());
    assert!(f.log().is_empty());
    kill(Pid::from_raw(child.id() as i32), Signal::SIGTERM).unwrap();
    assert_eq!(wait_exit(&mut child).code(), Some(143));
    drop(lock);
    assert!(
        Command::new("flock")
            .arg("-n")
            .arg(&lock_path)
            .arg("true")
            .status()
            .unwrap()
            .success()
    );
    success(f.command(CHECKER).output().unwrap());
}

#[test]
fn cancellation_while_awaiting_confirmation_restores_lock() {
    let f = Fixture::new();
    let system = f.configure_system();
    let output_path = f.path("installer-output");
    let output = fs::File::create(&output_path).unwrap();
    let mut child = f
        .command(INSTALLER)
        .env("FAKE_NH_MODE", "ok")
        .env("FAKE_RESULT", system)
        .stdin(Stdio::piped())
        .stdout(output)
        .spawn()
        .unwrap();
    let start = Instant::now();
    while !fs::read_to_string(&output_path)
        .unwrap()
        .contains("awaitingInstall")
    {
        assert!(child.try_wait().unwrap().is_none());
        assert!(start.elapsed() < Duration::from_secs(10));
        thread::sleep(Duration::from_millis(20));
    }
    kill(Pid::from_raw(child.id() as i32), Signal::SIGTERM).unwrap();
    assert_eq!(wait_exit(&mut child).code(), Some(143));
    f.original_restored();
}

#[test]
fn non_store_build_result_is_rejected() {
    let f = Fixture::new();
    let out = f
        .command(INSTALLER)
        .env("FAKE_NH_MODE", "ok")
        .env("FAKE_RESULT", f.path("store"))
        .output()
        .unwrap();
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stdout).contains("without a valid NixOS system result"));
    f.original_restored();
}

#[test]
fn cancellation_kills_builder_restores_lock_and_unlocks() {
    for signal in [Signal::SIGTERM, Signal::SIGINT] {
        let f = Fixture::new();
        let mut child = f
            .command(INSTALLER)
            .env("FAKE_NH_MODE", "sleep")
            .spawn()
            .unwrap();
        wait_for(&f.path("building"), &mut child);
        kill(Pid::from_raw(child.id() as i32), signal).unwrap();
        assert_eq!(wait_exit(&mut child).code(), Some(128 + signal as i32));
        f.original_restored();
        let pid = fs::read_to_string(f.path("child-pid"))
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        assert!(
            kill(Pid::from_raw(pid), None).is_err(),
            "builder is still alive"
        );
        success(f.command(CHECKER).output().unwrap());
    }
}

#[test]
fn eof_and_mutable_activation_helper_are_rejected() {
    let f = Fixture::new();
    let system = f.configure_system();
    let out = f
        .command(INSTALLER)
        .env("FAKE_NH_MODE", "ok")
        .env("FAKE_RESULT", &system)
        .output()
        .unwrap();
    assert!(!out.status.success());
    let text = String::from_utf8_lossy(&out.stdout);
    assert!(text.contains("awaitingInstall"), "{text}");
    assert!(text.contains("console closed"), "{text}");
    f.original_restored();
    let mut child = f
        .command(INSTALLER)
        .env("FAKE_NH_MODE", "ok")
        .env("FAKE_RESULT", &system)
        .stdin(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(b"install\n").unwrap();
    let out = child.wait_with_output().unwrap();
    assert!(!out.status.success());
    assert!(
        String::from_utf8_lossy(&out.stdout).contains("immutable activation helper is unavailable")
    );
    f.original_restored();
}

#[test]
fn brightness_external_burst_and_stale_cache() {
    let f = Fixture::new();
    // Missing bus must invalidate even a fresh, otherwise plausible cache.
    let previous = json!({"monitor":"DP-1","model":"U2720Q","serial":"ABC","bus":991234,
        "current":5,"maximum":100,"checkedAt":quickshell_helpers::update::now()});
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
