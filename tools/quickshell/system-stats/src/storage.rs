//! On-demand allocated-file-size estimates, isolated from the live sampler.
//!
//! Files are never opened. Directory descriptors use O_NOFOLLOW, including
//! during traversal, so a concurrent replacement cannot redirect a root scan
//! through a symlink. Only mountinfo and filesystem metadata are read.
use anyhow::{Context, Result, bail, ensure};
use nix::{
    fcntl::{AT_FDCWD, AtFlags, OFlag, openat},
    sys::stat::{Mode, SFlag, fstat, fstatat},
};
use serde_json::{Value, json};
use std::{
    collections::{HashMap, HashSet},
    ffi::{OsStr, OsString},
    fs::{self, File, OpenOptions},
    io::{self, Write},
    os::unix::fs::{OpenOptionsExt, PermissionsExt},
    os::{
        fd::AsRawFd,
        unix::ffi::{OsStrExt, OsStringExt},
    },
    path::{Component, Path, PathBuf},
    time::{Instant, SystemTime, UNIX_EPOCH},
};

const IDS: [&str; 6] = ["docker", "nix", "applications", "personal", "vm", "other"];
const DOCKER: usize = 0;
const NIX: usize = 1;
const APPS: usize = 2;
const PERSONAL: usize = 3;
const VM: usize = 4;
const OTHER: usize = 5;

pub struct Options {
    pub home: PathBuf,
    pub output: PathBuf,
    pub root: PathBuf,
}

fn clean_absolute(path: &Path) -> bool {
    path.is_absolute()
        && path
            .components()
            .all(|part| matches!(part, Component::RootDir | Component::Normal(_)))
}

impl Options {
    pub fn validate(&self) -> Result<()> {
        ensure!(
            clean_absolute(&self.home) && self.home != Path::new("/"),
            "Invalid home path"
        );
        ensure!(clean_absolute(&self.root), "Invalid root path");
        ensure!(
            fs::canonicalize(&self.root).ok().as_deref() == Some(&self.root),
            "Root must be an existing directory without symlink aliases"
        );
        ensure!(self.root.is_dir(), "Root must be a directory");
        validate_output(&self.output)
    }
}

fn validate_output(path: &Path) -> Result<()> {
    ensure!(
        clean_absolute(path),
        "Output must be an absolute path without parent components"
    );
    let parent = path.parent().context("Output needs a parent directory")?;
    ensure!(path.file_name().is_some(), "Output needs a file name");
    ensure!(
        fs::canonicalize(parent).ok().as_deref() == Some(parent) && parent.is_dir(),
        "Output parent must exist without symlink aliases"
    );
    match fs::symlink_metadata(path) {
        Ok(meta) => ensure!(meta.is_file(), "Output must be a regular file"),
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(_) => bail!("Output is inaccessible"),
    }
    Ok(())
}

#[derive(Clone, Debug)]
struct Mount {
    point: PathBuf,
    device: String,
    kind: String,
}

// mountinfo uses octal escapes for whitespace and backslashes. Decode bytes,
// not UTF-8 characters: Linux filenames need not be valid UTF-8.
fn mount_path(field: &str) -> Result<PathBuf> {
    let bytes = field.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'\\' {
            ensure!(index + 3 < bytes.len(), "Invalid mount escape");
            let octal = &bytes[index + 1..index + 4];
            ensure!(
                octal.iter().all(|byte| (b'0'..=b'7').contains(byte)),
                "Invalid mount escape"
            );
            let value = (octal[0] - b'0') as u16 * 64
                + (octal[1] - b'0') as u16 * 8
                + (octal[2] - b'0') as u16;
            ensure!(value > 0 && value <= 255, "Invalid mount escape");
            decoded.push(value as u8);
            index += 4;
        } else {
            decoded.push(bytes[index]);
            index += 1;
        }
    }
    let path = PathBuf::from(OsString::from_vec(decoded));
    ensure!(clean_absolute(&path), "Invalid mount path");
    Ok(path)
}

fn mounts(text: &str) -> Result<Vec<Mount>> {
    text.lines()
        .map(|line| {
            let (before, after) = line.split_once(" - ").context("Invalid mount record")?;
            let fields: Vec<_> = before.split_whitespace().collect();
            ensure!(fields.len() >= 6, "Incomplete mount record");
            Ok(Mount {
                point: mount_path(fields[4])?,
                device: fields[2].to_owned(),
                kind: after
                    .split_whitespace()
                    .next()
                    .context("Missing filesystem type")?
                    .to_owned(),
            })
        })
        .collect()
}

struct Mounts {
    allowed: HashMap<PathBuf, bool>,
    kind: String,
}

impl Mounts {
    fn new(records: Vec<Mount>, root: &Path) -> Result<Self> {
        let backing = records
            .iter()
            .filter(|mount| root.starts_with(&mount.point))
            .max_by_key(|mount| mount.point.components().count())
            .context("Root mount is unavailable")?;
        let allowed = records
            .iter()
            .filter(|mount| mount.point.starts_with(root))
            .map(|mount| {
                (
                    mount.point.clone(),
                    mount.device == backing.device && mount.kind == backing.kind,
                )
            })
            .collect();
        Ok(Self {
            allowed,
            kind: backing.kind.clone(),
        })
    }

    fn enter(&self, path: &Path) -> bool {
        self.allowed.get(path).copied().unwrap_or(true)
    }
}

fn canonical_category_path(path: &Path) -> PathBuf {
    if let Ok(relative) = path.strip_prefix("/persist/home") {
        Path::new("/home").join(relative)
    } else if let Ok(relative) = path.strip_prefix("/persist/system") {
        Path::new("/").join(relative)
    } else {
        path.to_path_buf()
    }
}

fn classify(path: &Path, home: &Path) -> (usize, bool) {
    let path = canonical_category_path(path);
    if path.starts_with("/var/lib/docker") || path.starts_with("/var/lib/containerd") {
        return (DOCKER, false);
    }
    if path.starts_with("/nix/store") {
        return (NIX, false);
    }
    if path.starts_with("/var/lib/libvirt/images") {
        return (VM, false);
    }
    if path.starts_with("/var/lib/flatpak") {
        return (APPS, false);
    }
    for user_home in [home, Path::new("/root")] {
        let Ok(relative) = path.strip_prefix(user_home) else {
            continue;
        };
        if relative.starts_with(".local/share/docker") {
            return (DOCKER, false);
        }
        if relative.starts_with(".local/share/libvirt/images")
            || relative.starts_with("VirtualBox VMs")
        {
            return (VM, false);
        }
        if relative.starts_with(".config/nixos") || relative.starts_with(".local/share/chezmoi") {
            return (PERSONAL, false);
        }
        if relative.starts_with(".cache") {
            return (APPS, true);
        }
        if relative
            .components()
            .next()
            .is_some_and(|part| part.as_os_str().as_bytes().starts_with(b"."))
        {
            return (APPS, false);
        }
        return (PERSONAL, false);
    }
    if path.starts_with("/home") {
        (PERSONAL, false)
    } else {
        (OTHER, false)
    }
}

#[derive(Default)]
struct Totals {
    bytes: [u64; 6],
    partial: [bool; 6],
    cache_bytes: u64,
    errors: u64,
}

impl Totals {
    fn add(&mut self, category: usize, cache: bool, blocks: i64) {
        let bytes = u64::try_from(blocks).unwrap_or(0).saturating_mul(512);
        self.bytes[category] = self.bytes[category].saturating_add(bytes);
        if cache {
            self.cache_bytes = self.cache_bytes.saturating_add(bytes);
        }
    }

    fn failure(&mut self, path: &Path, home: &Path) {
        self.errors += 1;
        self.partial[classify(path, home).0] = true;
        let path = canonical_category_path(path);
        // A denied ancestor can hide more than its own directory's category.
        for (prefix, category) in [
            (PathBuf::from("/var/lib/docker"), DOCKER),
            (PathBuf::from("/var/lib/containerd"), DOCKER),
            (PathBuf::from("/nix/store"), NIX),
            (PathBuf::from("/var/lib/libvirt/images"), VM),
            (PathBuf::from("/var/lib/flatpak"), APPS),
        ] {
            if prefix.starts_with(&path) {
                self.partial[category] = true;
            }
        }
        for user_home in [home, Path::new("/root")] {
            for (relative, category) in [
                (".cache", APPS),
                (".local/share/docker", DOCKER),
                (".local/share/libvirt/images", VM),
                ("VirtualBox VMs", VM),
                (".config/nixos", PERSONAL),
                (".local/share/chezmoi", PERSONAL),
            ] {
                if user_home.join(relative).starts_with(&path) {
                    self.partial[category] = true;
                }
            }
        }
        if path == Path::new("/persist") {
            self.partial.fill(true);
        }
    }

    fn categories(&mut self, used: u64) -> Value {
        let sum = self.bytes.iter().copied().fold(0_u64, u64::saturating_add);
        if self.errors == 0 && sum <= used {
            self.bytes[OTHER] = self.bytes[OTHER].saturating_add(used - sum);
        }
        Value::Array(
            IDS.iter()
                .enumerate()
                .map(|(index, id)| {
                    let bytes = if self.partial[index] && self.bytes[index] == 0 {
                        Value::Null
                    } else {
                        json!(self.bytes[index])
                    };
                    let mut category = json!({"id":id,"bytes":bytes,"partial":self.partial[index]});
                    if index == APPS {
                        category["cacheBytes"] = json!(self.cache_bytes);
                        category["dataBytes"] =
                            json!(self.bytes[APPS].saturating_sub(self.cache_bytes));
                    }
                    category
                })
                .collect(),
        )
    }
}

struct Scanner<'a> {
    root: &'a Path,
    home: &'a Path,
    mounts: Mounts,
    seen: HashSet<(u64, u64)>,
    totals: Totals,
}

impl Scanner<'_> {
    fn virtual_path(&self, path: &Path) -> PathBuf {
        Path::new("/").join(path.strip_prefix(self.root).unwrap_or(path))
    }

    fn visit(&mut self, parent: &impl std::os::fd::AsFd, name: &OsStr, path: &Path, depth: usize) {
        if !self.mounts.enter(path) {
            return;
        }
        let virtual_path = self.virtual_path(path);
        let stat = match fstatat(parent, name, AtFlags::AT_SYMLINK_NOFOLLOW) {
            Ok(stat) => stat,
            Err(nix::errno::Errno::ENOENT) => return,
            Err(_) => {
                self.totals.failure(&virtual_path, self.home);
                return;
            }
        };
        let kind = SFlag::from_bits_truncate(stat.st_mode) & SFlag::S_IFMT;
        if !matches!(kind, SFlag::S_IFREG | SFlag::S_IFDIR | SFlag::S_IFLNK) {
            return;
        }
        let directory = kind == SFlag::S_IFDIR;
        if !directory {
            // Bind-mounted files can alias another path even with nlink == 1.
            if !self.seen.insert((stat.st_dev, stat.st_ino)) {
                return;
            }
            let (category, cache) = classify(&virtual_path, self.home);
            self.totals.add(category, cache, stat.st_blocks);
            return;
        }
        // Bound descriptors and stack use even on adversarial directory trees.
        if depth > 512 {
            self.totals.failure(&virtual_path, self.home);
            return;
        }
        let descriptor = match openat(
            parent,
            name,
            OFlag::O_RDONLY | OFlag::O_DIRECTORY | OFlag::O_CLOEXEC | OFlag::O_NOFOLLOW,
            Mode::empty(),
        ) {
            Ok(descriptor) => descriptor,
            Err(nix::errno::Errno::ENOENT) => return,
            Err(_) => {
                self.totals.failure(&virtual_path, self.home);
                return;
            }
        };
        let stat = match fstat(&descriptor) {
            Ok(stat) => stat,
            Err(_) => {
                self.totals.failure(&virtual_path, self.home);
                return;
            }
        };
        if !self.seen.insert((stat.st_dev, stat.st_ino)) {
            return;
        }
        let (category, cache) = classify(&virtual_path, self.home);
        self.totals.add(category, cache, stat.st_blocks);
        // /proc/self/fd resolves our O_NOFOLLOW-opened descriptor, never a
        // user-controlled path. Keep it open until enumeration is complete.
        let entries = match fs::read_dir(format!("/proc/self/fd/{}", descriptor.as_raw_fd())) {
            Ok(entries) => entries,
            Err(_) => {
                self.totals.failure(&virtual_path, self.home);
                return;
            }
        };
        let mut names = Vec::new();
        for entry in entries {
            match entry {
                Ok(entry) => names.push(entry.file_name()),
                Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                Err(_) => self.totals.failure(&virtual_path, self.home),
            }
        }
        if depth == 0 {
            names.sort_by_key(|name| match name.as_bytes() {
                b"home" => 0,
                b"var" => 1,
                b"nix" => 2,
                b"persist" => 4,
                _ => 3,
            });
        }
        for name in names {
            self.visit(&descriptor, &name, &path.join(&name), depth + 1);
        }
    }
}

pub fn collect(options: &Options) -> Result<Value> {
    options.validate()?;
    let start = Instant::now();
    let table =
        mounts(&fs::read_to_string("/proc/self/mountinfo").context("Cannot read mount table")?)?;
    let mount_table = Mounts::new(table, &options.root)?;
    let filesystem = mount_table.kind.clone();
    let mut scanner = Scanner {
        root: &options.root,
        home: &options.home,
        mounts: mount_table,
        seen: HashSet::new(),
        totals: Totals::default(),
    };
    scanner.visit(&AT_FDCWD, options.root.as_os_str(), &options.root, 0);
    let stat = nix::sys::statvfs::statvfs(&options.root).context("Cannot read disk capacity")?;
    let total = stat.blocks().saturating_mul(stat.fragment_size());
    let used = stat
        .blocks()
        .saturating_sub(stat.blocks_free())
        .saturating_mul(stat.fragment_size());
    let available = stat.blocks_available().saturating_mul(stat.fragment_size());
    let categories = scanner.totals.categories(used);
    let error_count = scanner.totals.errors;
    Ok(json!({
        "schemaVersion": 1,
        "measuredAt": SystemTime::now().duration_since(UNIX_EPOCH)?.as_millis() as u64,
        "durationMs": start.elapsed().as_millis() as u64,
        "estimated": true,
        "filesystem": filesystem,
        "disk": { "totalBytes": total, "usedBytes": used, "availableBytes": available },
        "categories": categories,
        "errors": { "count": error_count, "message": if error_count == 0 { "" } else { "Some filesystem entries could not be measured; partial categories are lower bounds." } }
    }))
}

/// Only this explicit destination is written. The old report survives errors.
pub fn write_report(output: &Path, report: &Value) -> Result<()> {
    validate_output(output)?;
    let parent = output.parent().context("Missing output parent")?;
    let temporary = parent.join(format!(".quickshell-storage-{}.tmp", std::process::id()));
    let mut file = OpenOptions::new()
        .create_new(true)
        .write(true)
        .mode(0o600)
        .open(&temporary)
        .context("Cannot create report")?;
    let result = (|| -> Result<()> {
        serde_json::to_writer(&mut file, report)?;
        file.write_all(b"\n")?;
        file.set_permissions(fs::Permissions::from_mode(0o644))?;
        file.sync_all()?;
        fs::rename(&temporary, output).context("Cannot publish report")?;
        File::open(parent)?.sync_all()?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::{MetadataExt, symlink};

    #[test]
    fn categories_respect_boundaries_and_persistence_aliases() {
        let home = Path::new("/home/test");
        for (path, category, cache) in [
            ("/var/lib/docker/btrfs/subvolumes/one", DOCKER, false),
            ("/var/lib/docker-old", OTHER, false),
            ("/var/lib/containerd/data", DOCKER, false),
            ("/nix/store/package", NIX, false),
            ("/nix/var", OTHER, false),
            ("/home/test/.cache/thumbnails", APPS, true),
            ("/root/.cache/tool", APPS, true),
            ("/home/test/.vscode/extensions", APPS, false),
            ("/home/test/.config/nixos/.cache", PERSONAL, false),
            ("/home/test/.local/share/chezmoi/file", PERSONAL, false),
            ("/persist/home/test/PhD/file", PERSONAL, false),
            ("/persist/system/var/lib/docker/data", DOCKER, false),
            ("/home/test/.local/share/docker/data", DOCKER, false),
            ("/home/test/VirtualBox VMs/disk", VM, false),
            ("/var/lib/libvirt/images/disk", VM, false),
            ("/var/lib/libvirt/config", OTHER, false),
        ] {
            assert_eq!(classify(Path::new(path), home), (category, cache), "{path}");
        }
    }

    #[test]
    fn mount_table_decodes_escapes_and_excludes_external_and_pseudo_mounts() {
        let table = mounts("1 0 0:32 /root / rw - btrfs /dev/root rw\n2 1 0:32 /persist /persist rw - btrfs /dev/root rw\n3 1 0:42 / /proc rw - proc proc rw\n4 1 8:2 / /home/test/External\\040Drive rw - ext4 /dev/other rw\n").unwrap();
        let table = Mounts::new(table, Path::new("/")).unwrap();
        assert!(table.enter(Path::new("/persist")));
        assert!(!table.enter(Path::new("/proc")));
        assert!(!table.enter(Path::new("/home/test/External Drive")));
        for invalid in [
            "/bad\\",
            "/bad\\099",
            "/bad\\000",
            "/bad\\777",
            "relative",
            "/../bad",
        ] {
            assert!(mount_path(invalid).is_err());
        }
        assert_eq!(mount_path("/a\\134b").unwrap(), Path::new("/a\\b"));
    }

    #[test]
    fn scan_deduplicates_hardlinks_counts_sparse_blocks_and_never_follows_links() {
        let fixture = tempfile::tempdir().unwrap();
        let personal = fixture.path().join("home/test/PhD");
        fs::create_dir_all(&personal).unwrap();
        let cache = fixture.path().join("home/test/.cache");
        fs::create_dir_all(&cache).unwrap();
        let sparse = personal.join("sparse");
        File::create(&sparse)
            .unwrap()
            .set_len(1024 * 1024 * 1024)
            .unwrap();
        fs::write(cache.join("data"), vec![1_u8; 8192]).unwrap();
        fs::hard_link(cache.join("data"), cache.join("linked")).unwrap();
        symlink("/", personal.join("escape")).unwrap();
        let skipped = fixture.path().join("proc");
        fs::create_dir(&skipped).unwrap();
        fs::write(skipped.join("not-scanned"), vec![1_u8; 65536]).unwrap();
        let mounts = Mounts {
            kind: "fixture".into(),
            allowed: HashMap::from([(skipped, false)]),
        };
        let mut scan = Scanner {
            root: fixture.path(),
            home: Path::new("/home/test"),
            mounts,
            seen: HashSet::new(),
            totals: Totals::default(),
        };
        scan.visit(&AT_FDCWD, fixture.path().as_os_str(), fixture.path(), 0);
        assert_eq!(scan.totals.errors, 0);
        let cache_bytes = fs::metadata(&cache).unwrap().blocks() * 512
            + fs::metadata(cache.join("data")).unwrap().blocks() * 512;
        assert_eq!(scan.totals.cache_bytes, cache_bytes);
        assert!(scan.totals.bytes[PERSONAL] < 1024 * 1024);
        let before = scan.totals.bytes;
        scan.visit(&AT_FDCWD, fixture.path().as_os_str(), fixture.path(), 0);
        assert_eq!(
            before, scan.totals.bytes,
            "directory aliases are visited once"
        );
    }

    #[test]
    fn partial_reports_do_not_fabricate_zero_or_a_balanced_total() {
        let mut totals = Totals::default();
        totals.failure(Path::new("/var/lib/docker"), Path::new("/home/test"));
        totals.bytes[PERSONAL] = 50;
        let categories = totals.categories(1000);
        assert_eq!(categories[DOCKER]["bytes"], Value::Null);
        assert_eq!(categories[DOCKER]["partial"], true);
        assert_eq!(categories[OTHER]["bytes"], 0);
        let mut complete = Totals::default();
        complete.bytes[DOCKER] = 2000;
        assert_eq!(complete.categories(1000)[DOCKER]["bytes"], 2000);
        let mut metadata = Totals::default();
        metadata.bytes[NIX] = 700;
        assert_eq!(metadata.categories(1000)[OTHER]["bytes"], 300);
        let mut home_denied = Totals::default();
        home_denied.failure(Path::new("/home/test"), Path::new("/home/test"));
        for category in [DOCKER, APPS, PERSONAL, VM] {
            assert!(home_denied.partial[category]);
        }
    }

    #[test]
    fn report_write_is_atomic_readable_and_rejects_symlink_destinations() {
        let fixture = tempfile::tempdir().unwrap();
        let output = fixture.path().join("report.json");
        write_report(&output, &json!({"schemaVersion":1})).unwrap();
        write_report(&output, &json!({"schemaVersion":2})).unwrap();
        assert_eq!(
            serde_json::from_slice::<Value>(&fs::read(&output).unwrap()).unwrap()["schemaVersion"],
            2
        );
        assert_eq!(
            fs::metadata(&output).unwrap().permissions().mode() & 0o777,
            0o644
        );
        let alias = fixture.path().join("alias");
        symlink(&output, &alias).unwrap();
        assert!(write_report(&alias, &json!({})).is_err());
        assert!(write_report(&fixture.path().join("missing/report.json"), &json!({})).is_err());
        let directory_alias = fixture.path().join("diralias");
        symlink(fixture.path(), &directory_alias).unwrap();
        assert!(write_report(&directory_alias.join("other.json"), &json!({})).is_err());
    }
}
