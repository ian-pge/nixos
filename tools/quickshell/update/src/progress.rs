//! Summarises Nix `--log-format internal-json` activities for the update widget:
//! global build and download counters, transferred bytes and the running jobs.
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    time::{Duration, Instant},
};

// Activity and result numbers from Nix's libutil/include/nix/util/logging.hh.
const ACT_COPY_PATH: u64 = 100;
const ACT_REALISE: u64 = 102;
const ACT_COPY_PATHS: u64 = 103;
const ACT_BUILDS: u64 = 104;
const ACT_BUILD: u64 = 105;
const ACT_SUBSTITUTE: u64 = 108;
const RES_BUILD_LOG_LINE: u64 = 101;
const RES_SET_PHASE: u64 = 104;
const RES_PROGRESS: u64 = 105;
const RES_SET_EXPECTED: u64 = 106;
const RES_POST_BUILD_LOG_LINE: u64 = 107;
// Nix verbosity: error, warn, notice, info. Higher levels are debug chatter.
const LVL_ERROR: u64 = 0;
const LVL_INFO: u64 = 3;

const MIN_INTERVAL: Duration = Duration::from_millis(250);
const MAX_INTERVAL: Duration = Duration::from_secs(1);
const MAX_RUNNING: usize = 8;
const MAX_LOG_CHARS: usize = 160;

struct Activity {
    kind: u64,
    parent: u64,
    name: String,
    phase: String,
    log: String,
    started: Instant,
    done: u64,
    expected: u64,
}

#[derive(Default, Clone, Copy)]
struct Counter {
    done: u64,
    expected: u64,
}

impl Counter {
    fn json(self) -> Value {
        json!({"done":self.done,"expected":self.expected.max(self.done)})
    }
}

#[derive(Default)]
pub struct Progress {
    activities: HashMap<u64, Activity>,
    builds: Counter,
    downloads: Counter,
    expected_bytes: u64,
    finished_bytes: u64,
    realising: bool,
    dirty: bool,
    last_emit: Option<Instant>,
    sample: Option<(Instant, u64)>,
    speed: f64,
    errors: Vec<String>,
}

impl Progress {
    /// Consumes one stderr line and returns the plain text worth logging, if any.
    pub fn handle(&mut self, line: &str) -> Option<String> {
        let Some(payload) = line.strip_prefix("@nix ") else {
            return Some(clean(line));
        };
        let Ok(event) = serde_json::from_str::<Value>(payload) else {
            return Some(clean(line));
        };
        let id = event["id"].as_u64().unwrap_or(0);
        match event["action"].as_str().unwrap_or("") {
            "msg" => return self.message(&event),
            "start" => self.start(id, &event),
            "stop" => self.stop(id),
            "result" => self.result(id, &event),
            _ => return None,
        }
        None
    }

    fn message(&mut self, event: &Value) -> Option<String> {
        let level = event["level"].as_u64().unwrap_or(LVL_INFO);
        let text = clean(event["msg"].as_str().unwrap_or(""));
        if level == LVL_ERROR && !text.is_empty() {
            self.errors.push(text.clone());
            if self.errors.len() > 3 {
                self.errors.remove(0);
            }
        }
        (level <= LVL_INFO).then_some(text)
    }

    fn start(&mut self, id: u64, event: &Value) {
        let kind = event["type"].as_u64().unwrap_or(0);
        if kind == ACT_REALISE {
            self.realising = true;
        }
        let name = match kind {
            ACT_BUILD | ACT_SUBSTITUTE => event["fields"][0]
                .as_str()
                .map(store_name)
                .unwrap_or_default(),
            _ => String::new(),
        };
        // Count copied NAR bytes: unlike network transfers they always match the
        // expected total, whatever compression a binary cache uses. Copies made
        // during evaluation are not part of that total.
        if kind == ACT_COPY_PATH && !self.realising {
            return;
        }
        self.activities.insert(
            id,
            Activity {
                kind,
                parent: event["parent"].as_u64().unwrap_or(0),
                name,
                phase: String::new(),
                log: String::new(),
                started: Instant::now(),
                done: 0,
                expected: 0,
            },
        );
        self.dirty |= matches!(kind, ACT_BUILD | ACT_SUBSTITUTE | ACT_REALISE);
    }

    fn stop(&mut self, id: u64) {
        if let Some(activity) = self.activities.remove(&id) {
            match activity.kind {
                ACT_COPY_PATH => self.finished_bytes += activity.done.max(activity.expected),
                // Nix closes its counters before sending the final count, which
                // leaves the last job pending (e.g. 1 / 2 builds).
                ACT_BUILDS => self.builds.expected = self.builds.done,
                ACT_COPY_PATHS => self.downloads.expected = self.downloads.done,
                _ => {}
            }
            self.dirty = true;
        }
    }

    fn result(&mut self, id: u64, event: &Value) {
        let fields = event["fields"].as_array().map(Vec::as_slice).unwrap_or(&[]);
        let number = |index: usize| fields.get(index).and_then(Value::as_u64).unwrap_or(0);
        let Some(activity) = self.activities.get_mut(&id) else {
            return;
        };
        match event["type"].as_u64().unwrap_or(0) {
            RES_BUILD_LOG_LINE | RES_POST_BUILD_LOG_LINE => {
                let line = log_line(fields.first().and_then(Value::as_str).unwrap_or(""));
                if !line.is_empty() {
                    activity.log = line;
                    self.dirty = true;
                }
            }
            RES_SET_PHASE => {
                activity.phase = fields.first().and_then(Value::as_str).unwrap_or("").into();
                self.dirty = true;
            }
            RES_PROGRESS => {
                let counter = Counter {
                    done: number(0),
                    expected: number(1),
                };
                match activity.kind {
                    ACT_BUILDS => self.builds = counter,
                    ACT_COPY_PATHS => self.downloads = counter,
                    _ => {
                        activity.done = counter.done;
                        activity.expected = counter.expected;
                    }
                }
                self.dirty = true;
            }
            RES_SET_EXPECTED if activity.kind == ACT_REALISE && number(0) == ACT_COPY_PATH => {
                self.expected_bytes = number(1);
                self.dirty = true;
            }
            _ => {}
        }
    }

    fn descends_from(&self, mut id: u64, ancestor: u64) -> bool {
        for _ in 0..8 {
            match self.activities.get(&id) {
                Some(activity) if activity.parent == ancestor => return true,
                Some(activity) if activity.parent != 0 => id = activity.parent,
                _ => return false,
            }
        }
        false
    }

    fn copied_bytes(&self, ancestor: Option<u64>) -> Counter {
        let mut total = Counter::default();
        for (id, activity) in &self.activities {
            if activity.kind == ACT_COPY_PATH
                && ancestor.is_none_or(|ancestor| self.descends_from(*id, ancestor))
            {
                total.done += activity.done;
                total.expected += activity.expected;
            }
        }
        total
    }

    /// Returns a widget snapshot when one is due. `force` ignores throttling
    /// but still skips unchanged state, e.g. for the final update.
    pub fn due(&mut self, now: Instant, force: bool) -> Option<Value> {
        if !self.realising {
            return None;
        }
        let since = self.last_emit.map(|last| now.duration_since(last));
        let ready = match since {
            None => true,
            Some(_) if force => self.dirty,
            Some(since) => (self.dirty && since >= MIN_INTERVAL) || since >= MAX_INTERVAL,
        };
        if !ready {
            return None;
        }
        self.last_emit = Some(now);
        self.dirty = false;
        Some(self.snapshot(now))
    }

    fn snapshot(&mut self, now: Instant) -> Value {
        let bytes = self.finished_bytes + self.copied_bytes(None).done;
        if let Some((then, previous)) = self.sample {
            let seconds = now.duration_since(then).as_secs_f64();
            if seconds >= 0.9 {
                let current = bytes.saturating_sub(previous) as f64 / seconds;
                self.speed = 0.5 * self.speed + 0.5 * current;
                self.sample = Some((now, bytes));
            }
        } else {
            self.sample = Some((now, bytes));
        }
        let mut running: Vec<_> = self
            .activities
            .iter()
            .filter(|(_, activity)| matches!(activity.kind, ACT_BUILD | ACT_SUBSTITUTE))
            .collect();
        // Builds first, then the longest-running jobs.
        running.sort_by_key(|(id, activity)| (activity.kind != ACT_BUILD, activity.started, **id));
        let count = running.len();
        let running: Vec<_> = running
            .into_iter()
            .take(MAX_RUNNING)
            .map(|(id, activity)| {
                let elapsed = now.saturating_duration_since(activity.started).as_secs();
                if activity.kind == ACT_BUILD {
                    json!({"kind":"build","name":activity.name,"phase":activity.phase,
                        "log":activity.log,"elapsed":elapsed})
                } else {
                    let copied = self.copied_bytes(Some(*id));
                    json!({"kind":"download","name":activity.name,"elapsed":elapsed,
                        "bytes":copied.done,"expectedBytes":copied.expected.max(copied.done)})
                }
            })
            .collect();
        let total = self.builds.expected.max(self.builds.done)
            + self.downloads.expected.max(self.downloads.done);
        let done = self.builds.done + self.downloads.done;
        json!({
            "percent": (done * 100).checked_div(total).unwrap_or(0).min(100),
            "builds": self.builds.json(),
            "downloads": {
                "done": self.downloads.done,
                "expected": self.downloads.expected.max(self.downloads.done),
                "bytes": bytes,
                "expectedBytes": self.expected_bytes.max(bytes),
                "speed": self.speed.round() as u64,
            },
            "runningCount": count,
            "running": running,
        })
    }

    /// The last Nix error messages, used to explain a failed build.
    pub fn error(&self) -> Option<String> {
        (!self.errors.is_empty()).then(|| self.errors.join("\n"))
    }
}

/// `/nix/store/<32-char hash>-firefox-133.0.drv` → `firefox-133.0`.
fn store_name(path: &str) -> String {
    let base = path.rsplit('/').next().unwrap_or(path);
    let base = base.strip_suffix(".drv").unwrap_or(base);
    match base.split_once('-') {
        Some((hash, name)) if hash.len() == 32 && !name.is_empty() => name.into(),
        _ => base.into(),
    }
}

/// Removes ANSI escape sequences and control characters.
fn clean(text: &str) -> String {
    let mut output = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\u{1b}' {
            match chars.next() {
                // CSI: parameters until a final byte in @..~.
                Some('[') => {
                    for c in chars.by_ref() {
                        if ('@'..='~').contains(&c) {
                            break;
                        }
                    }
                }
                // OSC: until BEL or ST.
                Some(']') => {
                    while let Some(c) = chars.next() {
                        if c == '\u{7}' || (c == '\u{1b}' && chars.next_if_eq(&'\\').is_some()) {
                            break;
                        }
                    }
                }
                _ => {}
            }
        } else if c == '\t' {
            output.push(' ');
        } else if !c.is_control() || c == '\n' {
            output.push(c);
        }
    }
    output.trim_end().into()
}

/// The visible text of a build log line, keeping only the last carriage-return
/// segment (progress bars) and a bounded length.
fn log_line(line: &str) -> String {
    let visible = line
        .rsplit('\r')
        .find(|segment| !segment.trim().is_empty())
        .unwrap_or("");
    let text = clean(visible);
    let text = text.trim();
    match text.char_indices().nth(MAX_LOG_CHARS) {
        Some((index, _)) => format!("{}…", &text[..index]),
        None => text.into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn feed(progress: &mut Progress, lines: &[&str]) {
        for line in lines {
            progress.handle(line);
        }
    }

    #[test]
    fn names_ansi_and_carriage_returns() {
        assert_eq!(
            store_name("/nix/store/8awrgywy14lppl0sqkc05j3jiagcblgi-firefox-133.0.drv"),
            "firefox-133.0"
        );
        assert_eq!(store_name("/nix/store/short-name"), "short-name");
        assert_eq!(
            clean("\u{1b}[31;1merror:\u{1b}[0m boom\t!"),
            "error: boom !"
        );
        assert_eq!(log_line("10%\r50%\r\u{1b}[1m90%\u{1b}[0m\r"), "90%");
        assert_eq!(
            log_line(&"x".repeat(400)).chars().count(),
            MAX_LOG_CHARS + 1
        );
    }

    #[test]
    fn evaluation_is_silent_until_realisation_starts() {
        let mut progress = Progress::default();
        assert_eq!(
            progress.handle("> Building NixOS configuration").as_deref(),
            Some("> Building NixOS configuration")
        );
        feed(
            &mut progress,
            &[r#"@nix {"action":"start","id":1,"level":4,"parent":0,"text":"","type":100}"#],
        );
        assert!(progress.due(Instant::now(), true).is_none());
        assert!(progress.activities.is_empty());
    }

    #[test]
    fn snapshot_tracks_counters_builds_and_downloads() {
        let mut progress = Progress::default();
        let path = "/nix/store/8awrgywy14lppl0sqkc05j3jiagcblgi";
        feed(
            &mut progress,
            &[
                r#"@nix {"action":"start","id":1,"level":0,"parent":0,"text":"","type":102}"#,
                r#"@nix {"action":"start","id":2,"level":0,"parent":0,"text":"","type":104}"#,
                r#"@nix {"action":"start","id":3,"level":0,"parent":0,"text":"","type":103}"#,
                r#"@nix {"action":"result","fields":[100,2000],"id":1,"type":106}"#,
                r#"@nix {"action":"result","fields":[101,9999],"id":1,"type":106}"#,
                r#"@nix {"action":"result","fields":[1,4,1,0],"id":2,"type":105}"#,
                r#"@nix {"action":"result","fields":[2,6,1,0],"id":3,"type":105}"#,
            ],
        );
        feed(
            &mut progress,
            &[
                &format!(
                    r#"@nix {{"action":"start","fields":["{path}-firefox-133.0.drv","",1,1],"id":4,"level":3,"parent":0,"text":"building","type":105}}"#
                ),
                r#"@nix {"action":"result","fields":["buildPhase"],"id":4,"type":104}"#,
                r#"@nix {"action":"result","fields":["\u001b[1m[12/40]\u001b[0m compiling"],"id":4,"type":101}"#,
                &format!(
                    r#"@nix {{"action":"start","fields":["{path}-linux-6.18","https://cache.nixos.org"],"id":5,"level":4,"parent":0,"text":"","type":108}}"#
                ),
                r#"@nix {"action":"start","id":6,"level":4,"parent":5,"text":"","type":100}"#,
                r#"@nix {"action":"result","fields":[300,1000,0,0],"id":6,"type":105}"#,
                // Raw network transfers are ignored: compression makes them disagree.
                r#"@nix {"action":"start","id":7,"level":4,"parent":6,"text":"","type":101}"#,
                r#"@nix {"action":"result","fields":[999,999,0,0],"id":7,"type":105}"#,
                r#"@nix {"action":"start","id":8,"level":4,"parent":0,"text":"","type":100}"#,
                r#"@nix {"action":"result","fields":[500,500,0,0],"id":8,"type":105}"#,
                r#"@nix {"action":"stop","id":8}"#,
            ],
        );
        let snapshot = progress.due(Instant::now(), false).unwrap();
        assert_eq!(snapshot["percent"], 30);
        assert_eq!(snapshot["builds"], json!({"done":1,"expected":4}));
        assert_eq!(snapshot["downloads"]["done"], 2);
        assert_eq!(snapshot["downloads"]["bytes"], 800);
        assert_eq!(snapshot["downloads"]["expectedBytes"], 2000);
        assert_eq!(snapshot["runningCount"], 2);
        let running = snapshot["running"].as_array().unwrap();
        assert_eq!(running[0]["name"], "firefox-133.0");
        assert_eq!(running[0]["phase"], "buildPhase");
        assert_eq!(running[0]["log"], "[12/40] compiling");
        assert_eq!(running[1]["kind"], "download");
        assert_eq!(running[1]["name"], "linux-6.18");
        assert_eq!(running[1]["bytes"], 300);
        assert_eq!(running[1]["expectedBytes"], 1000);
        // Throttled until something changes or the heartbeat interval elapses.
        let now = Instant::now();
        assert!(progress.due(now, false).is_none());
        assert!(progress.due(now + MAX_INTERVAL, false).is_some());
        progress.handle(r#"@nix {"action":"stop","id":4}"#);
        assert!(progress.due(now + MAX_INTERVAL, false).is_none());
        let last = progress.due(now + MAX_INTERVAL, true).unwrap();
        assert_eq!(last["runningCount"], 1);
        progress.handle(r#"@nix {"action":"result","fields":[2,3,0,0],"id":2,"type":105}"#);
        progress.handle(r#"@nix {"action":"stop","id":2}"#);
        let closed = progress.due(now + MAX_INTERVAL * 2, true).unwrap();
        assert_eq!(closed["builds"], json!({"done":2,"expected":2}));
    }

    #[test]
    fn errors_are_kept_without_ansi_and_debug_is_hidden() {
        let mut progress = Progress::default();
        assert!(
            progress
                .handle(r#"@nix {"action":"msg","level":5,"msg":"chatty"}"#)
                .is_none()
        );
        assert_eq!(
            progress
                .handle(r#"@nix {"action":"msg","level":0,"msg":"\u001b[31;1merror:\u001b[0m builder failed"}"#)
                .as_deref(),
            Some("error: builder failed")
        );
        assert_eq!(progress.error().as_deref(), Some("error: builder failed"));
    }
}
