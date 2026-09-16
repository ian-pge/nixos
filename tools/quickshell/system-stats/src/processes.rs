//! Optional, panel-only process scan. One /proc/PID/stat read feeds both lists.
use serde_json::{Value, json};
use std::{collections::HashMap, fs, path::Path, time::Duration};

#[derive(Debug)]
struct Process {
    pid: u32,
    name: String,
    start: u64,
    ticks: u64,
    memory: u64,
}

fn display_name(root: &Path, process: &Process) -> String {
    // comm is limited to 15 bytes. Resolve only the displayed winners, never
    // every command line (which may contain private arguments).
    fs::read_link(root.join(format!("{}/exe", process.pid)))
        .ok()
        .and_then(|path| {
            path.file_name()
                .map(|name| name.to_string_lossy().into_owned())
        })
        .map(|name| {
            name.strip_prefix('.')
                .and_then(|name| name.strip_suffix("-wrapped"))
                .unwrap_or(&name)
                .to_owned()
        })
        .unwrap_or_else(|| process.name.clone())
}

fn parse_stat(text: &str, page_size: u64) -> Option<Process> {
    let open = text.find('(')?;
    let close = text.rfind(')')?;
    let fields: Vec<_> = text.get(close + 1..)?.split_whitespace().collect();
    let read = |index: usize| fields.get(index)?.parse::<u64>().ok();
    Some(Process {
        pid: text.get(..open)?.trim().parse().ok()?,
        name: text
            .get(open + 1..close)?
            .chars()
            .map(|c| if c.is_control() { ' ' } else { c })
            .collect(),
        ticks: read(11)?.checked_add(read(12)?)?,
        start: read(19)?,
        memory: (fields.get(21)?.parse::<i64>().ok()?.max(0) as u64).checked_mul(page_size)?,
    })
}

pub struct ProcessSampler {
    generation: u64,
    previous: HashMap<u32, Process>,
    previous_at: Option<Duration>,
    next: Duration,
    ticks_per_second: u64,
    page_size: u64,
}

impl Default for ProcessSampler {
    fn default() -> Self {
        // sysconf has no pointer arguments; query the actual kernel units once.
        let ticks = unsafe { nix::libc::sysconf(nix::libc::_SC_CLK_TCK) };
        let page = unsafe { nix::libc::sysconf(nix::libc::_SC_PAGESIZE) };
        Self::new(ticks.max(0) as u64, page.max(0) as u64)
    }
}

impl ProcessSampler {
    fn new(ticks_per_second: u64, page_size: u64) -> Self {
        Self {
            generation: 0,
            previous: HashMap::new(),
            previous_at: None,
            next: Duration::ZERO,
            ticks_per_second,
            page_size,
        }
    }

    pub fn sample(&mut self, root: &Path, elapsed: Duration, generation: u64) -> Option<Value> {
        if self.generation != generation {
            self.generation = generation;
            self.previous.clear();
            self.previous_at = None;
            self.next = Duration::ZERO;
        }
        if generation == 0 || elapsed < self.next {
            return None;
        }
        self.next = elapsed + Duration::from_secs(2);
        let entries = match fs::read_dir(root) {
            Ok(entries) if self.ticks_per_second > 0 && self.page_size > 0 => entries,
            _ => {
                self.previous.clear();
                self.previous_at = None;
                return Some(
                    json!({"generation":generation,"error":"Process counters unavailable"}),
                );
            }
        };
        let processes: HashMap<_, _> = entries
            .flatten()
            .filter_map(|entry| {
                let pid = entry.file_name().to_str()?.parse::<u32>().ok()?;
                let bytes = fs::read(entry.path().join("stat")).ok()?;
                let process = parse_stat(&String::from_utf8_lossy(&bytes), self.page_size)?;
                (process.pid == pid).then_some((pid, process))
            })
            .collect();
        let seconds = self
            .previous_at
            .and_then(|at| elapsed.checked_sub(at))
            .filter(|delta| !delta.is_zero())
            .map(|delta| delta.as_secs_f64());
        let mut cpu = Vec::new();
        let mut memory = Vec::new();
        for process in processes.values() {
            if process.memory > 0 {
                memory.push((process, process.memory));
            }
            if let Some(seconds) = seconds
                && let Some(before) = self.previous.get(&process.pid)
                && before.start == process.start
                && let Some(ticks) = process.ticks.checked_sub(before.ticks)
            {
                cpu.push((
                    process,
                    ticks as f64 / self.ticks_per_second as f64 / seconds * 100.0,
                ));
            }
        }
        cpu.sort_by(|(a, av), (b, bv)| bv.total_cmp(av).then(a.pid.cmp(&b.pid)));
        memory.sort_by(|(a, av), (b, bv)| bv.cmp(av).then(a.pid.cmp(&b.pid)));
        let cpu = seconds.map(|_| {
            cpu.iter()
                .take(5)
                .map(|(p, usage)| json!({"pid":p.pid,"name":display_name(root,p),"usage":usage}))
                .collect::<Vec<_>>()
        });
        let memory: Vec<_> = memory
            .iter()
            .take(5)
            .map(|(p, bytes)| json!({"pid":p.pid,"name":display_name(root,p),"memoryBytes":bytes}))
            .collect();
        self.previous = processes;
        self.previous_at = Some(elapsed);
        Some(json!({"generation":generation,"cpu":cpu,"memory":memory}))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn stat(pid: u32, ticks: u64, start: u64, pages: i64) -> String {
        format!(
            "{pid} (a ) tricky name) S 1 1 1 0 -1 0 0 0 0 0 {ticks} 0 0 0 20 0 1 0 {start} 0 {pages}"
        )
    }
    fn write(root: &Path, pid: u32, ticks: u64, start: u64, pages: i64) {
        fs::create_dir_all(root.join(pid.to_string())).unwrap();
        fs::write(
            root.join(format!("{pid}/stat")),
            stat(pid, ticks, start, pages),
        )
        .unwrap();
    }
    #[test]
    fn stat_handles_names_units_and_malformed_counters() {
        let p = parse_stat(&stat(42, 123, 500, 3), 4096).unwrap();
        assert_eq!((p.pid, p.ticks, p.start, p.memory), (42, 123, 500, 12288));
        assert_eq!(p.name, "a ) tricky name");
        assert_eq!(parse_stat(&stat(42, 1, 1, -1), 4096).unwrap().memory, 0);
        for text in ["", "42 (bad)", "42 () S"] {
            assert!(parse_stat(text, 4096).is_none());
        }
    }
    #[test]
    fn scans_only_on_demand_and_resets_baseline_after_close_or_reopen() {
        let dir = tempfile::tempdir().unwrap();
        let mut s = ProcessSampler::new(100, 4096);
        assert!(
            s.sample(&dir.path().join("missing"), Duration::ZERO, 0)
                .is_none()
        );
        write(dir.path(), 42, 100, 1, 2);
        let first = s.sample(dir.path(), Duration::ZERO, 1).unwrap();
        assert!(first["cpu"].is_null());
        assert_eq!(first["memory"][0]["memoryBytes"], 8192);
        assert!(
            s.sample(&dir.path().join("missing"), Duration::from_secs(1), 1)
                .is_none()
        );
        write(dir.path(), 42, 500, 1, 2);
        assert_eq!(
            s.sample(dir.path(), Duration::from_secs(2), 1).unwrap()["cpu"][0]["usage"],
            200.0
        );
        assert!(s.sample(dir.path(), Duration::from_secs(3), 0).is_none());
        assert!(s.sample(dir.path(), Duration::from_secs(100), 2).unwrap()["cpu"].is_null());
        assert!(s.sample(dir.path(), Duration::from_secs(101), 3).unwrap()["cpu"].is_null());
    }
    #[test]
    fn ranking_is_bounded_deterministic_and_pid_reuse_is_not_a_spike() {
        let dir = tempfile::tempdir().unwrap();
        let mut s = ProcessSampler::new(100, 4096);
        for pid in 1..=8 {
            write(dir.path(), pid, 100, 1, pid as i64);
        }
        s.sample(dir.path(), Duration::ZERO, 1);
        for pid in 1..=8 {
            write(dir.path(), pid, 100 + u64::from(pid) * 20, 1, pid as i64);
        }
        write(dir.path(), 8, 90000, 2, 8); // reused PID: ignore its first CPU delta
        write(dir.path(), 7, 1, 1, 7); // reset counter
        fs::write(dir.path().join("3/stat"), "disappeared").unwrap();
        let report = s.sample(dir.path(), Duration::from_secs(2), 1).unwrap();
        assert_eq!(report["memory"].as_array().unwrap().len(), 5);
        assert_eq!(report["memory"][0]["pid"], 8);
        assert_eq!(report["cpu"][0]["pid"], 6);
        assert_eq!(report["cpu"].as_array().unwrap().len(), 5);
    }
}
