//! Child processes remain cancellable without leaving a builder holding our lock.
use anyhow::{Context, Result, bail};
use nix::{
    sys::signal::{Signal, killpg},
    unistd::Pid,
};
use std::{
    fs::{self, File},
    io::{BufRead, BufReader, Read},
    os::unix::process::CommandExt,
    process::{Command, Stdio},
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
        mpsc,
    },
    thread,
    time::{Duration, Instant},
};

/// Called with each output line, and with `None` at least every 25 ms.
pub type LineHandler<'a> = &'a mut dyn FnMut(Option<&str>);

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

    pub fn capture(&self, command: &mut Command) -> Result<String> {
        self.execute(command, false, true, None)
    }

    pub fn stream(&self, command: &mut Command) -> Result<()> {
        self.execute(command, true, true, None).map(|_| ())
    }

    /// Like `stream`, but hands stdout and stderr lines to `handler`. nh
    /// forwards Nix's log to stdout, while nix itself writes it to stderr.
    pub fn stream_lines(&self, command: &mut Command, handler: LineHandler) -> Result<()> {
        self.execute(command, true, true, Some(handler)).map(|_| ())
    }

    /// Once privileged boot installation starts, let it finish (or roll back)
    /// before handling cancellation and deciding whether to restore flake.lock.
    pub fn activation(&self, command: &mut Command) -> Result<()> {
        self.execute(command, true, false, None).map(|_| ())
    }

    fn execute(
        &self,
        command: &mut Command,
        stream: bool,
        cancellable: bool,
        mut handler: Option<LineHandler>,
    ) -> Result<String> {
        if cancellable {
            self.check()?;
        }
        let stdout = tempfile::NamedTempFile::new()?;
        let stderr = tempfile::NamedTempFile::new()?;
        if handler.is_some() {
            command.stdout(Stdio::piped()).stderr(Stdio::piped());
        } else if stream {
            command
                .stdout(Stdio::inherit())
                .stderr(File::options().write(true).open("/dev/stdout")?);
        } else {
            command.stdout(stdout.reopen()?).stderr(stderr.reopen()?);
        }
        // Do not let nix/nh consume the install confirmation intended for us.
        if cancellable {
            command.stdin(Stdio::null());
        }
        command.process_group(0);
        let description = format!("{command:?}");
        let mut child = command
            .spawn()
            .with_context(|| format!("Cannot start {description}"))?;
        let lines = handler.is_some().then(|| {
            let (sender, receiver) = mpsc::channel();
            if let Some(stdout) = child.stdout.take() {
                read_lines(stdout, sender.clone());
            }
            if let Some(stderr) = child.stderr.take() {
                read_lines(stderr, sender);
            }
            receiver
        });
        let mut stopped = None;
        let status = loop {
            if let Some(status) = child.try_wait()? {
                break status;
            }
            if cancellable && self.signal().is_some() {
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
            match (&mut handler, &lines) {
                (Some(handler), Some(lines)) => {
                    drain(lines, handler, Duration::from_millis(25));
                }
                _ => thread::sleep(Duration::from_millis(25)),
            }
        };
        if stopped.is_some() {
            // The leader can exit before a child does; clean up its process group.
            let _ = killpg(Pid::from_raw(child.id() as i32), Signal::SIGKILL);
            self.check()?;
        }
        if let (Some(handler), Some(lines)) = (&mut handler, &lines) {
            // Read what the child wrote before exiting. A leftover grandchild
            // holding the pipe open must not block us for long.
            let deadline = Instant::now() + Duration::from_secs(2);
            while Instant::now() < deadline && drain(lines, handler, Duration::from_millis(25)) {}
        }
        if !status.success() {
            let error = fs::read_to_string(stderr.path()).unwrap_or_default();
            bail!("{description} failed ({status}): {}", error.trim());
        }
        if stream {
            Ok(String::new())
        } else {
            Ok(fs::read_to_string(stdout.path())?)
        }
    }
}

/// Sends each line of `stream` until EOF. The receiver disconnects once
/// every stream feeding it has closed.
fn read_lines(stream: impl Read + Send + 'static, sender: mpsc::Sender<String>) {
    thread::spawn(move || {
        let mut reader = BufReader::new(stream);
        let mut buffer = Vec::new();
        while reader
            .read_until(b'\n', &mut buffer)
            .is_ok_and(|read| read > 0)
        {
            let line = String::from_utf8_lossy(&buffer);
            if sender
                .send(line.trim_end_matches(['\n', '\r']).to_string())
                .is_err()
            {
                break;
            }
            buffer.clear();
        }
    });
}

/// Forwards available lines, waiting up to `timeout` for the first one, then
/// ticks the handler. Returns false once the pipe is closed and drained.
fn drain(lines: &mpsc::Receiver<String>, handler: &mut LineHandler, timeout: Duration) -> bool {
    let mut open = true;
    match lines.recv_timeout(timeout) {
        Ok(line) => {
            handler(Some(&line));
            loop {
                match lines.try_recv() {
                    Ok(line) => handler(Some(&line)),
                    Err(mpsc::TryRecvError::Empty) => break,
                    Err(mpsc::TryRecvError::Disconnected) => {
                        open = false;
                        break;
                    }
                }
            }
        }
        Err(mpsc::RecvTimeoutError::Timeout) => {}
        Err(mpsc::RecvTimeoutError::Disconnected) => {
            thread::sleep(timeout);
            open = false;
        }
    }
    handler(None);
    open
}
