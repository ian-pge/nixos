//! Local telemetry; no subprocesses and no writes to procfs or sysfs.
use anyhow::{Context, Result, ensure};
use serde_json::{Value, json};
use std::{
    fs,
    path::{Path, PathBuf},
    time::Duration,
};

#[derive(Clone, Copy, Debug)]
struct Cpu {
    idle: u128,
    total: u128,
}

fn cpu_totals(text: &str) -> Result<Cpu> {
    let mut fields = text
        .lines()
        .next()
        .context("Missing aggregate CPU counters")?
        .split_whitespace();
    ensure!(
        fields.next() == Some("cpu"),
        "Missing aggregate CPU counters"
    );
    // guest and guest_nice are already included in user/nice, so exclude them.
    let values: Vec<u128> = fields
        .take(8)
        .map(str::parse::<u64>)
        .collect::<std::result::Result<Vec<_>, _>>()?
        .into_iter()
        .map(u128::from)
        .collect();
    ensure!(values.len() == 8, "Incomplete CPU counters");
    Ok(Cpu {
        idle: values[3] + values[4],
        total: values.iter().sum(),
    })
}

/// Python's round uses ties-to-even. Integer arithmetic preserves that policy.
fn percent(used: u128, total: u128) -> u64 {
    if total == 0 {
        return 0;
    }
    let scaled = used.min(total) * 100;
    let quotient = scaled / total;
    let remainder = scaled % total;
    (quotient
        + u128::from(
            remainder * 2 > total || (remainder * 2 == total && !quotient.is_multiple_of(2)),
        )) as u64
}

fn cpu_percent(before: Cpu, after: Cpu) -> u64 {
    // Counter resets/hotplug start a new baseline instead of producing spikes.
    let Some(total) = after.total.checked_sub(before.total) else {
        return 0;
    };
    let Some(idle) = after.idle.checked_sub(before.idle) else {
        return 0;
    };
    percent(total.saturating_sub(idle), total)
}

fn memory_percent(text: &str) -> Result<u64> {
    let mut total = None;
    let mut available = None;
    for line in text.lines() {
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        if key == "MemTotal" || key == "MemAvailable" {
            let value = value
                .split_whitespace()
                .next()
                .context("Missing memory value")?
                .parse::<u64>()?;
            if key == "MemTotal" {
                total = Some(value);
            } else {
                available = Some(value);
            }
        }
    }
    let total = total.context("MemTotal is missing")?;
    let available = available.context("MemAvailable is missing")?;
    Ok(percent(
        u128::from(total.saturating_sub(available)),
        u128::from(total),
    ))
}

pub fn disk_percent(path: &Path) -> Result<u64> {
    let stat = nix::sys::statvfs::statvfs(path)?;
    // Like shutil.disk_usage: used = total - f_bfree, not total - f_bavail.
    Ok(percent(
        u128::from(stat.blocks().saturating_sub(stat.blocks_free())),
        u128::from(stat.blocks()),
    ))
}

pub struct Paths {
    pub proc: PathBuf,
    pub backlight: PathBuf,
    pub disk: PathBuf,
}
impl Default for Paths {
    fn default() -> Self {
        Self {
            proc: "/proc".into(),
            backlight: "/sys/class/backlight".into(),
            disk: "/".into(),
        }
    }
}

pub struct Sampler {
    paths: Paths,
    previous: Option<Cpu>,
    backlight: Option<PathBuf>,
    disk: Option<(Duration, u64)>,
}

impl Sampler {
    pub fn new(paths: Paths) -> Self {
        let previous = fs::read_to_string(paths.proc.join("stat"))
            .ok()
            .and_then(|s| cpu_totals(&s).ok());
        Self {
            paths,
            previous,
            backlight: None,
            disk: None,
        }
    }

    fn brightness(&mut self) -> Result<u64> {
        if !self.backlight.as_ref().is_some_and(|p| p.is_dir()) {
            self.backlight = match fs::read_dir(&self.paths.backlight) {
                Ok(entries) => entries
                    .filter_map(|e| e.ok())
                    .map(|e| e.path())
                    .find(|p| p.is_dir()),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
                Err(e) => return Err(e.into()),
            };
        }
        let Some(path) = &self.backlight else {
            return Ok(0);
        };
        let read =
            |name| -> Result<u64> { Ok(fs::read_to_string(path.join(name))?.trim().parse()?) };
        Ok(percent(
            u128::from(read("brightness")?),
            u128::from(read("max_brightness")?),
        ))
    }

    pub fn sample(&mut self, elapsed: Duration) -> Value {
        match self.read(elapsed, disk_percent) {
            Ok(value) => value,
            Err(error) => json!({"error":format!("{error:#}")}),
        }
    }

    fn read(
        &mut self,
        elapsed: Duration,
        disk_reader: impl FnOnce(&Path) -> Result<u64>,
    ) -> Result<Value> {
        let cpu = cpu_totals(&fs::read_to_string(self.paths.proc.join("stat"))?)?;
        let usage = self.previous.map_or(0, |before| cpu_percent(before, cpu));
        self.previous = Some(cpu);
        let memory = memory_percent(&fs::read_to_string(self.paths.proc.join("meminfo"))?)?;
        if self
            .disk
            .is_none_or(|(checked, _)| elapsed.saturating_sub(checked) >= Duration::from_secs(30))
        {
            self.disk = Some((elapsed, disk_reader(&self.paths.disk)?));
        }
        let brightness = self.brightness()?;
        Ok(json!({"cpu":usage,"memory":memory,"disk":self.disk.unwrap().1,"brightness":brightness}))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn cpu_excludes_guest_and_handles_resets_and_idle() {
        let before = cpu_totals("cpu 100 0 50 800 50 0 0 0 99 99\ncpu0 1 2 3").unwrap();
        assert_eq!(before.total, 1000);
        assert_eq!(
            cpu_percent(
                before,
                cpu_totals("cpu 130 0 60 860 50 0 0 0 999 999").unwrap()
            ),
            40
        );
        assert_eq!(cpu_percent(before, before), 0);
        assert_eq!(
            cpu_percent(before, cpu_totals("cpu 1 0 0 9 0 0 0 0").unwrap()),
            0
        );
        for bad in ["", "cpu0 1 2 3 4 5 6 7 8", "cpu 1 2", "cpu a 0 0 0 0 0 0 0"] {
            assert!(cpu_totals(bad).is_err());
        }
    }
    #[test]
    fn percentages_match_python_rounding_and_stay_bounded() {
        assert_eq!(percent(1, 8), 12);
        assert_eq!(percent(3, 8), 38);
        assert_eq!(percent(1, 0), 0);
        assert_eq!(percent(101, 100), 100);
        assert_eq!(
            memory_percent("MemTotal: 1000 kB\nMemFree: 100 kB\nMemAvailable: 400 kB").unwrap(),
            60
        );
        assert!(memory_percent("MemTotal: 1000 kB").is_err());
    }
    fn fixture() -> (tempfile::TempDir, Sampler) {
        let temp = tempfile::tempdir().unwrap();
        fs::create_dir(temp.path().join("proc")).unwrap();
        fs::create_dir(temp.path().join("backlight")).unwrap();
        fs::write(temp.path().join("proc/stat"), "cpu 1 0 0 9 0 0 0 0").unwrap();
        fs::write(
            temp.path().join("proc/meminfo"),
            "MemTotal: 1000 kB\nMemAvailable: 400 kB\n",
        )
        .unwrap();
        let sampler = Sampler::new(Paths {
            proc: temp.path().join("proc"),
            backlight: temp.path().join("backlight"),
            disk: temp.path().into(),
        });
        (temp, sampler)
    }
    #[test]
    fn disk_is_cached_and_retried_on_failure() {
        let (_temp, mut s) = fixture();
        assert!(
            s.read(Duration::ZERO, |_| anyhow::bail!("unavailable"))
                .is_err()
        );
        assert_eq!(
            s.read(Duration::from_secs(1), |_| Ok(33)).unwrap()["disk"],
            33
        );
        assert_eq!(
            s.read(Duration::from_secs(30), |_| panic!("too soon"))
                .unwrap()["disk"],
            33
        );
        assert_eq!(
            s.read(Duration::from_secs(31), |_| Ok(44)).unwrap()["disk"],
            44
        );
    }
    #[test]
    fn missing_hotplugged_and_removed_backlight() {
        let (temp, mut s) = fixture();
        assert_eq!(s.sample(Duration::ZERO)["brightness"], 0);
        let panel = temp.path().join("backlight/panel");
        fs::create_dir(&panel).unwrap();
        fs::write(panel.join("brightness"), "3\n").unwrap();
        fs::write(panel.join("max_brightness"), "8\n").unwrap();
        assert_eq!(s.sample(Duration::from_secs(1))["brightness"], 38);
        fs::write(panel.join("brightness"), "invalid").unwrap();
        assert!(s.sample(Duration::from_secs(2))["error"].is_string());
        fs::remove_file(panel.join("brightness")).unwrap();
        fs::remove_file(panel.join("max_brightness")).unwrap();
        fs::remove_dir(panel).unwrap();
        assert_eq!(s.sample(Duration::from_secs(3))["brightness"], 0);
    }
    #[test]
    fn transient_proc_error_does_not_prevent_recovery() {
        let (temp, mut s) = fixture();
        fs::write(temp.path().join("proc/stat"), "malformed").unwrap();
        assert!(s.sample(Duration::ZERO)["error"].is_string());
        fs::write(temp.path().join("proc/stat"), "cpu 2 0 0 18 0 0 0 0").unwrap();
        let value = s.sample(Duration::from_secs(1));
        assert_eq!(value["cpu"], 10);
        assert!(value["error"].is_null());
        assert_eq!(value.as_object().unwrap().len(), 4);
    }
}
