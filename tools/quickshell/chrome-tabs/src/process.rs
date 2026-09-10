//! Keep TabCtl subprocesses tied to the Quickshell request that started them.
use anyhow::{Context, Result, bail};
use nix::{
    sys::signal::{Signal, killpg},
    unistd::Pid,
};
use std::{
    fs,
    os::unix::process::CommandExt,
    process::{Command, Output, Stdio},
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

#[derive(Default)]
pub struct Runner {
    signal: Arc<AtomicUsize>,
}

impl Runner {
    pub fn new() -> Result<Self> {
        let runner = Self::default();
        for signal in [signal_hook::consts::SIGINT, signal_hook::consts::SIGTERM] {
            signal_hook::flag::register_usize(signal, runner.signal.clone(), signal as usize)?;
        }
        Ok(runner)
    }

    pub fn signal(&self) -> Option<i32> {
        match self.signal.load(Ordering::Relaxed) {
            0 => None,
            signal => Some(signal as i32),
        }
    }

    pub fn check(&self) -> Result<()> {
        if let Some(signal) = self.signal() {
            bail!("Interrupted by signal {signal}");
        }
        Ok(())
    }

    pub fn capture(&self, args: &[&str]) -> Result<Output> {
        self.execute(Command::new("tabctl").args(args))
    }

    fn execute(&self, command: &mut Command) -> Result<Output> {
        self.check()?;
        let stdout = tempfile::NamedTempFile::new()?;
        let stderr = tempfile::NamedTempFile::new()?;
        command
            .stdout(stdout.reopen()?)
            .stderr(stderr.reopen()?)
            .stdin(Stdio::null());
        command.process_group(0);
        let description = format!("{command:?}");
        let mut child = command
            .spawn()
            .with_context(|| format!("Cannot start {description}"))?;
        let mut stopped = None;
        let status = loop {
            if let Some(status) = child.try_wait()? {
                break status;
            }
            if self.signal().is_some() {
                let pid = Pid::from_raw(child.id() as i32);
                if let Some(since) = stopped {
                    if Instant::now().duration_since(since) >= Duration::from_secs(2) {
                        let _ = killpg(pid, Signal::SIGKILL);
                    }
                } else {
                    let _ = killpg(pid, Signal::SIGTERM);
                    stopped = Some(Instant::now());
                }
            }
            thread::sleep(Duration::from_millis(25));
        };
        if stopped.is_some() {
            // The leader can exit before a child does; clean up its process group.
            let _ = killpg(Pid::from_raw(child.id() as i32), Signal::SIGKILL);
            self.check()?;
        }
        Ok(Output {
            status,
            stdout: fs::read(stdout.path())?,
            stderr: fs::read(stderr.path())?,
        })
    }
}
