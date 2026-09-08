use crate::{diff, process::Runner};
use anyhow::{Context, Result, bail, ensure};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeSet,
    env,
    fs::{self, File, OpenOptions, Permissions},
    io::{self, BufRead, Write},
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::Command,
    sync::mpsc,
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

pub fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

pub struct Paths {
    pub flake: PathBuf,
    pub cache: PathBuf,
    pub current: PathBuf,
    pub profile: PathBuf,
    pub store: PathBuf,
}

impl Paths {
    pub fn from_env() -> Result<Self> {
        let home = PathBuf::from(env::var_os("HOME").context("HOME is unset")?);
        let resolve =
            |key, fallback: PathBuf| env::var_os(key).map(PathBuf::from).unwrap_or(fallback);
        // Absolute paths remain valid when the builder changes working directory.
        Ok(Self {
            flake: std::path::absolute(resolve("NIXOS_FLAKE_DIR", home.join(".config/nixos")))?,
            cache: std::path::absolute(
                resolve("XDG_CACHE_HOME", home.join(".cache")).join("quickshell/top-bar"),
            )?,
            current: resolve("QS_CURRENT_SYSTEM_LINK", "/run/current-system".into()),
            profile: resolve("QS_SYSTEM_PROFILE", "/nix/var/nix/profiles/system".into()),
            store: resolve("QS_STORE_DIR", "/nix/store".into()),
        })
    }

    fn clear_candidate(&self) -> Result<()> {
        remove(&self.cache.join("update-candidate.lock"))?;
        remove(&self.cache.join("update-candidate.json"))
    }

    fn lock(&self, runner: &Runner, timeout: Option<Duration>) -> Result<File> {
        fs::create_dir_all(&self.cache)?;
        let lock = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(self.cache.join("updates.lock"))?;
        let start = Instant::now();
        loop {
            runner.check()?;
            match fs2::FileExt::try_lock_exclusive(&lock) {
                Ok(()) => return Ok(lock),
                Err(error) if error.kind() == io::ErrorKind::WouldBlock => {}
                Err(error) => return Err(error.into()),
            }
            ensure!(
                !timeout.is_some_and(|limit| start.elapsed() >= limit),
                "The update check did not finish in time."
            );
            thread::sleep(Duration::from_millis(50));
        }
    }
}

fn remove(path: &Path) -> Result<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error).with_context(|| format!("Cannot remove {}", path.display())),
    }
}

fn atomic(path: &Path, contents: &[u8], permissions: Option<Permissions>) -> Result<()> {
    let mut temporary = tempfile::NamedTempFile::new_in(path.parent().context("Missing parent")?)?;
    temporary.write_all(contents)?;
    if let Some(permissions) = permissions {
        temporary.as_file().set_permissions(permissions)?;
    }
    temporary.as_file().sync_all()?;
    temporary.persist(path).map_err(|error| error.error)?;
    File::open(path.parent().unwrap())?.sync_all()?;
    Ok(())
}

fn write_json(path: &Path, value: &Value) -> Result<()> {
    atomic(path, format!("{value}\n").as_bytes(), None)
}

fn read_json(path: &Path) -> Result<Value> {
    Ok(serde_json::from_slice(&fs::read(path)?)?)
}
fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
fn optional_read(path: &Path) -> Result<Option<Vec<u8>>> {
    match fs::read(path) {
        Ok(bytes) => Ok(Some(bytes)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.into()),
    }
}

fn fingerprint(flake: &[u8], lock: Option<&[u8]>) -> String {
    hash(
        format!(
            "flake.nix={}\nflake.lock={}\n",
            hash(flake),
            lock.map(hash).unwrap_or("missing".into())
        )
        .as_bytes(),
    )
}
fn source_hash(paths: &Paths) -> Result<String> {
    Ok(fingerprint(
        &fs::read(paths.flake.join("flake.nix"))?,
        optional_read(&paths.flake.join("flake.lock"))?.as_deref(),
    ))
}

fn pending(paths: &Paths) -> Result<Option<Value>> {
    let path = paths.cache.join("pending-reboot.json");
    if !path.exists() {
        return Ok(None);
    }
    let document = read_json(&path).unwrap_or(Value::Null);
    let target = document["targetSystem"].as_str().map(PathBuf::from);
    if document["version"] == 1
        && target.as_ref().is_some_and(|target| {
            target.starts_with(&paths.store)
                && target != &paths.store
                && paths.current.canonicalize().ok().as_ref() != Some(target)
                && paths.profile.canonicalize().ok().as_ref() == Some(target)
        })
    {
        return Ok(Some(reboot_status(target.as_ref().unwrap(), Value::Null)));
    }
    remove(&path)?;
    Ok(None)
}

fn reboot_status(target: &Path, checked_at: Value) -> Value {
    json!({"state":"reboot-required","hasUpdates":false,"message":"Update ready — reboot required",
        "updates":[],"targetSystem":target,"checkedAt":checked_at})
}

fn fresh(paths: &Paths) -> Option<Value> {
    let file = paths.cache.join("updates.json");
    let value = read_json(&file).ok()?;
    let source = source_hash(paths).ok()?;
    let age = fs::metadata(file).ok()?.modified().ok()?.elapsed().ok()?;
    ((value["state"].is_null() || value["state"] == "ok")
        && value["updates"].is_array()
        && value["sourceHash"] == source
        && (value["checkedAt"].is_null() || value["checkedAt"].is_number())
        && age < Duration::from_secs(1800))
    .then_some(value)
}

fn lock_updates(old: &Value, new: &Value) -> Result<Vec<Value>> {
    let old_nodes = old["nodes"]
        .as_object()
        .context("Invalid previous flake lock")?;
    let new_nodes = new["nodes"]
        .as_object()
        .context("Invalid updated flake lock")?;
    let root = new["root"].as_str().unwrap_or("root");
    let inputs = new_nodes.get(root).and_then(|n| n["inputs"].as_object());
    let names: BTreeSet<_> = old_nodes.keys().chain(new_nodes.keys()).collect();
    let mut updates = Vec::new();
    for name in names {
        if name == root {
            continue;
        }
        let old_node = old_nodes.get(name).unwrap_or(&Value::Null);
        let new_node = new_nodes.get(name).unwrap_or(&Value::Null);
        if old_node["locked"] == new_node["locked"] {
            continue;
        }
        let node = new_nodes.get(name).unwrap_or(old_node);
        let display = inputs
            .and_then(|inputs| inputs.iter().find(|(_, v)| **v == *name))
            .map_or(name, |(key, _)| key);
        let date = match node["locked"].get("lastModified").filter(|v| !v.is_null()) {
            None => "unknown".into(),
            Some(value) => {
                chrono::DateTime::from_timestamp(value.as_i64().context("Invalid input date")?, 0)
                    .context("Input date is out of range")?
                    .format("%Y-%m-%d")
                    .to_string()
            }
        };
        updates.push(json!({"name":display,"date":date}));
    }
    updates.sort_by(|a, b| a["name"].as_str().cmp(&b["name"].as_str()));
    Ok(updates)
}

fn check_inner(paths: &Paths, runner: &Runner) -> Result<Value> {
    let flake = fs::read(paths.flake.join("flake.nix"))?;
    let lock = optional_read(&paths.flake.join("flake.lock"))?;
    let base_hash = fingerprint(&flake, lock.as_deref());
    let before: Value = match &lock {
        Some(bytes) => serde_json::from_slice(bytes)?,
        None => json!({"nodes":{},"root":"root","version":7}),
    };
    ensure!(before["nodes"].is_object(), "Invalid previous flake lock");
    let temporary = tempfile::tempdir()?;
    fs::write(temporary.path().join("flake.nix"), flake)?;
    if let Some(lock) = lock {
        fs::write(temporary.path().join("flake.lock"), lock)?;
    }
    runner.capture(
        Command::new("nix")
            .args(["flake", "update", "--flake"])
            .arg(temporary.path()),
    )?;
    let candidate = fs::read(temporary.path().join("flake.lock"))?;
    let updates = lock_updates(&before, &serde_json::from_slice(&candidate)?)?;
    let count = updates.len();
    if count > 0 {
        atomic(&paths.cache.join("update-candidate.lock"), &candidate, None)?;
        write_json(
            &paths.cache.join("update-candidate.json"),
            &json!({"version":1,
            "baseHash":base_hash,"candidateHash":hash(&candidate),"checkedAt":now()}),
        )?;
    } else {
        paths.clear_candidate()?;
    }
    Ok(
        json!({"state":"ok","hasUpdates":count>0,"updates":updates,"sourceHash":base_hash,"checkedAt":now(),
        "message":if count>0 {format!("{count} update(s) available")} else {"System is up to date".into()}}),
    )
}

pub fn check(paths: &Paths, runner: &Runner, force: bool) -> Result<Value> {
    // Also serialize pending-reboot reads with the installer/cleaner. A checker
    // must never remove a pending record while a generation is being installed.
    let _lock = paths.lock(runner, None)?;
    if let Some(status) = pending(paths)? {
        return Ok(status);
    }
    if !force && let Some(status) = fresh(paths) {
        return Ok(status);
    }
    let status = match check_inner(paths, runner) {
        Ok(status) => status,
        Err(error) => {
            runner.check()?;
            let _ = writeln!(io::stderr(), "Update check failed: {error:#}");
            paths.clear_candidate()?;
            json!({"state":"error","hasUpdates":false,"message":"Unable to check for updates",
                "updates":[],"sourceHash":source_hash(paths).ok(),"checkedAt":now()})
        }
    };
    write_json(&paths.cache.join("updates.json"), &status)?;
    Ok(status)
}

pub fn event(phase: &str, message: &str) -> Result<()> {
    emit(&json!({"phase":phase,"message":message}))
}
fn emit(value: &Value) -> Result<()> {
    let mut stdout = io::stdout().lock();
    writeln!(stdout, "@@QS_UPDATE@@{value}")?;
    stdout.flush()?;
    Ok(())
}
fn log(message: &str) -> Result<()> {
    writeln!(io::stdout().lock(), "{message}")?;
    Ok(())
}

struct Transaction {
    lock_path: PathBuf,
    result_link: PathBuf,
    original: Option<(Vec<u8>, Permissions, SystemTime)>,
    committed: bool,
}

impl Transaction {
    fn new(paths: &Paths) -> Result<Self> {
        let lock_path = paths.flake.join("flake.lock");
        let original = optional_read(&lock_path)?
            .map(|bytes| {
                let meta = fs::metadata(&lock_path)?;
                Ok::<_, anyhow::Error>((bytes, meta.permissions(), meta.modified()?))
            })
            .transpose()?;
        Ok(Self {
            lock_path,
            result_link: paths.cache.join("update-result"),
            original,
            committed: false,
        })
    }
    fn restore(&mut self) -> Result<()> {
        if !self.committed {
            if let Some((bytes, permissions, modified)) = &self.original {
                atomic(&self.lock_path, bytes, Some(permissions.clone()))?;
                File::options()
                    .write(true)
                    .open(&self.lock_path)?
                    .set_modified(*modified)?;
            } else {
                remove(&self.lock_path)?;
            }
            self.committed = true;
        }
        remove(&self.result_link)
    }
}

impl Drop for Transaction {
    fn drop(&mut self) {
        if let Err(error) = self.restore() {
            let _ = writeln!(
                io::stderr(),
                "Unable to clean up update transaction: {error:#}"
            );
        }
    }
}

fn checked_candidate(paths: &Paths) -> Option<Vec<u8>> {
    let meta = read_json(&paths.cache.join("update-candidate.json")).ok()?;
    let bytes = fs::read(paths.cache.join("update-candidate.lock")).ok()?;
    let value: Value = serde_json::from_slice(&bytes).ok()?;
    (meta["version"] == 1
        && value["nodes"].is_object()
        && meta["baseHash"] == source_hash(paths).ok()?
        && meta["candidateHash"] == hash(&bytes))
    .then_some(bytes)
}

fn await_install(runner: &Runner) -> Result<()> {
    let (sender, receiver) = mpsc::channel();
    thread::spawn(move || {
        for line in io::stdin().lock().lines() {
            let stop = line.is_err() || line.as_ref().is_ok_and(|line| line == "install");
            if sender.send(line).is_err() || stop {
                break;
            }
        }
    });
    loop {
        runner.check()?;
        match receiver.recv_timeout(Duration::from_millis(50)) {
            Ok(line) => {
                if line? == "install" {
                    return Ok(());
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                bail!("The update console closed before boot installation.")
            }
        }
    }
}

fn immutable_executable(path: &Path) -> bool {
    // Validate the resolved path too; a symlink escaping the store is not an
    // immutable activation helper. Never accept a mutable PATH override here.
    path.is_absolute()
        && path.starts_with("/nix/store")
        && path
            .canonicalize()
            .is_ok_and(|p| p.starts_with("/nix/store"))
        && fs::metadata(path).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

fn activate(result: &Path, runner: &Runner) -> Result<()> {
    let activator = PathBuf::from(env::var_os("QS_UPDATE_ACTIVATOR").unwrap_or_default());
    ensure!(
        immutable_executable(&activator),
        "The immutable activation helper is unavailable."
    );
    let elevator = PathBuf::from(env::var_os("QS_UPDATE_ELEVATOR").unwrap_or_default());
    ensure!(
        immutable_executable(&elevator) && elevator.ends_with("bin/run0"),
        "The systemd authorization helper is unavailable."
    );
    runner.check()?;
    runner
        .activation(
            Command::new(elevator)
                .arg("--pipe")
                .arg(activator)
                .arg(result),
        )
        .context("Boot generation installation failed")
}

pub fn install(paths: &Paths, runner: &Runner) -> Result<()> {
    let _lock = paths.lock(runner, Some(Duration::from_secs(300)))?;
    ensure!(
        paths.flake.is_dir(),
        "Unable to open the NixOS configuration."
    );
    let mut transaction = Transaction::new(paths)?;
    let result = install_inner(paths, runner, &mut transaction);
    let rollback = transaction.restore();
    // Explicit restoration lets us report errors instead of silently losing the
    // original lockfile. Drop remains a fallback for early unwinding.
    rollback.context("Failed to restore the previous lockfile or remove the build link")?;
    result
}

fn install_inner(paths: &Paths, runner: &Runner, transaction: &mut Transaction) -> Result<()> {
    event("updating", "Updating flake inputs")?;
    log("📦 Updating flake inputs...\n")?;
    if let Some(candidate) = checked_candidate(paths) {
        let permissions = transaction
            .original
            .as_ref()
            .map(|(_, p, _)| p.clone())
            .unwrap_or_else(|| Permissions::from_mode(0o644));
        atomic(&transaction.lock_path, &candidate, Some(permissions))?;
        log("✓ Reusing the lockfile already checked by the update widget.")?;
    } else {
        paths.clear_candidate()?;
        runner
            .stream(
                Command::new("nix")
                    .args(["flake", "update"])
                    .current_dir(&paths.flake),
            )
            .context("Lockfile update failed. The previous lockfile will be restored.")?;
    }
    event("building", "Building the new NixOS configuration")?;
    log("\n🔨 Building the new NixOS configuration...\n")?;
    remove(&transaction.result_link)?;
    runner
        .stream(
            Command::new("nh")
                .args(["os", "build", "--out-link"])
                .arg(&transaction.result_link)
                .args(["--diff", "never", "--no-nom"])
                .arg(&paths.flake)
                .current_dir(&paths.flake),
        )
        .context("System build failed. The previous lockfile will be restored.")?;
    let result = transaction
        .result_link
        .canonicalize()
        .context("Missing NixOS build result")?;
    ensure!(
        result.starts_with("/nix/store")
            && immutable_executable(&result.join("bin/switch-to-configuration")),
        "The build finished without a valid NixOS system result."
    );
    let summary = diff::build(&paths.current, &result, runner)
        .context("The build succeeded, but its package changes could not be summarized.")?;
    emit(
        &json!({"phase":"awaitingInstall","message":"Package changes","changes":summary["changes"],
        "counts":summary["counts"],"total":summary["total"]}),
    )?;
    await_install(runner)?;
    event("installing", "Waiting for authorization")?;
    log("\n🔐 Requesting authorization...\n")?;
    commit(paths, transaction, &result, || activate(&result, runner))?;
    let _ = runner.stream(Command::new("qs").args([
        "--config",
        "top-bar",
        "ipc",
        "call",
        "topbar",
        "refreshNix",
    ]));
    log("\n✅ NixOS update installed. Reboot to use the new generation.")?;
    event("success", "Update ready — reboot required")
}

fn commit(
    paths: &Paths,
    transaction: &mut Transaction,
    result: &Path,
    activation: impl FnOnce() -> Result<()>,
) -> Result<()> {
    activation()?;
    // From this point on the boot profile has changed. Never roll back the
    // lockfile because a later cache write, IPC notification or stdout fails.
    transaction.committed = true;
    write_json(
        &paths.cache.join("pending-reboot.json"),
        &json!({"version":1,"targetSystem":result,"createdAt":now()}),
    )?;
    write_json(
        &paths.cache.join("updates.json"),
        &reboot_status(result, json!(now())),
    )?;
    paths.clear_candidate()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;
    fn fixture() -> (tempfile::TempDir, Paths) {
        let temp = tempfile::tempdir().unwrap();
        let paths = Paths {
            flake: temp.path().join("flake"),
            cache: temp.path().join("cache"),
            current: temp.path().join("current"),
            profile: temp.path().join("profile"),
            store: temp.path().join("store"),
        };
        fs::create_dir(&paths.flake).unwrap();
        fs::create_dir(&paths.cache).unwrap();
        fs::write(paths.flake.join("flake.nix"), "flake").unwrap();
        (temp, paths)
    }
    #[test]
    fn changes_include_removals_and_input_aliases() {
        let old = json!({"nodes":{"old":{"locked":{"rev":"a"}},"nixpkgs":{"locked":{"rev":"a"}}}});
        let new = json!({"root":"root","nodes":{"root":{"inputs":{"nix":"nixpkgs"}},
            "nixpkgs":{"locked":{"rev":"b","lastModified":0}},"added":{"locked":{"rev":"c"}}}});
        assert_eq!(
            lock_updates(&old, &new).unwrap(),
            vec![
                json!({"name":"added","date":"unknown"}),
                json!({"name":"nix","date":"1970-01-01"}),
                json!({"name":"old","date":"unknown"})
            ]
        );
        assert!(lock_updates(&json!({}), &new).is_err());
    }
    #[test]
    fn rollback_restores_contents_permissions_and_missing_lock() {
        let (_temp, p) = fixture();
        {
            let _tx = Transaction::new(&p).unwrap();
            fs::write(p.flake.join("flake.lock"), "new").unwrap();
        }
        assert!(!p.flake.join("flake.lock").exists());
        fs::write(p.flake.join("flake.lock"), "old").unwrap();
        fs::set_permissions(p.flake.join("flake.lock"), Permissions::from_mode(0o640)).unwrap();
        {
            let _tx = Transaction::new(&p).unwrap();
            fs::write(p.flake.join("flake.lock"), "new").unwrap();
        }
        assert_eq!(
            fs::read_to_string(p.flake.join("flake.lock")).unwrap(),
            "old"
        );
        assert_eq!(
            fs::metadata(p.flake.join("flake.lock"))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o640
        );
    }
    #[test]
    fn candidate_requires_both_hashes() {
        let (_temp, p) = fixture();
        let candidate = b"{\"nodes\":{}}";
        fs::write(p.cache.join("update-candidate.lock"), candidate).unwrap();
        write_json(&p.cache.join("update-candidate.json"),&json!({"version":1,"baseHash":source_hash(&p).unwrap(),"candidateHash":hash(candidate)})).unwrap();
        assert_eq!(checked_candidate(&p).unwrap(), candidate);
        fs::write(p.flake.join("flake.nix"), "changed").unwrap();
        assert!(checked_candidate(&p).is_none());
        fs::write(p.flake.join("flake.nix"), "flake").unwrap();
        fs::write(
            p.cache.join("update-candidate.lock"),
            "{\"nodes\":{\"tampered\":{}}}",
        )
        .unwrap();
        assert!(checked_candidate(&p).is_none());
    }
    #[test]
    fn activation_failure_rolls_back_success_commits_and_reboot_clears_pending() {
        let (_temp, p) = fixture();
        fs::create_dir(&p.store).unwrap();
        let target = p.store.join("target");
        fs::create_dir(&target).unwrap();
        symlink(&target, &p.profile).unwrap();
        fs::write(p.flake.join("flake.lock"), "old").unwrap();
        {
            let mut tx = Transaction::new(&p).unwrap();
            fs::write(&tx.lock_path, "new").unwrap();
            assert!(commit(&p, &mut tx, &target, || bail!("denied")).is_err());
        }
        assert_eq!(
            fs::read_to_string(p.flake.join("flake.lock")).unwrap(),
            "old"
        );
        assert!(pending(&p).unwrap().is_none());
        {
            let mut tx = Transaction::new(&p).unwrap();
            fs::write(&tx.lock_path, "new").unwrap();
            commit(&p, &mut tx, &target, || Ok(())).unwrap();
        }
        assert_eq!(
            fs::read_to_string(p.flake.join("flake.lock")).unwrap(),
            "new"
        );
        assert_eq!(pending(&p).unwrap().unwrap()["state"], "reboot-required");
        symlink(&target, &p.current).unwrap();
        assert!(pending(&p).unwrap().is_none());
        assert!(!p.cache.join("pending-reboot.json").exists());
    }
    #[test]
    fn committed_lock_survives_status_write_failure() {
        let (_temp, p) = fixture();
        {
            let mut tx = Transaction::new(&p).unwrap();
            fs::write(&tx.lock_path, "new").unwrap();
            fs::create_dir(p.cache.join("pending-reboot.json")).unwrap();
            assert!(commit(&p, &mut tx, Path::new("/nix/store/example"), || Ok(())).is_err());
        }
        assert_eq!(
            fs::read_to_string(p.flake.join("flake.lock")).unwrap(),
            "new"
        );
    }
    #[test]
    fn mutable_activator_is_rejected() {
        assert!(!immutable_executable(Path::new("/bin/sh")));
        assert!(!immutable_executable(Path::new("/tmp/run0")));
        assert!(!immutable_executable(Path::new("/nix/store/../something")));
    }
    #[test]
    fn native_lock_is_compatible_with_flock() {
        let (_temp, p) = fixture();
        let lock = p.lock(&Runner::default(), None).unwrap();
        assert!(p.lock(&Runner::default(), Some(Duration::ZERO)).is_err());
        drop(lock);
        assert!(p.lock(&Runner::default(), Some(Duration::ZERO)).is_ok());
    }
}
