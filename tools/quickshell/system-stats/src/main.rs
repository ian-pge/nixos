mod control;
use quickshell_system_stats::{Paths, Sampler, processes::ProcessSampler};
use std::{
    io::{self, Write},
    sync::atomic::Ordering,
    thread,
    time::{Duration, Instant},
};

fn main() -> io::Result<()> {
    let mut sampler = Sampler::new(Paths::default());
    let mut processes = ProcessSampler::default();
    let control = control::listen();
    let start = Instant::now();
    let mut stdout = io::stdout().lock();
    loop {
        thread::sleep(Duration::from_secs(1));
        let elapsed = start.elapsed();
        let mut value = sampler.sample(elapsed);
        if let Some(top) = processes.sample(
            std::path::Path::new("/proc"),
            elapsed,
            control.load(Ordering::Relaxed),
        ) {
            value["top"] = top;
        }
        if let Err(error) = writeln!(stdout, "{value}").and_then(|_| stdout.flush()) {
            // Quickshell closing the pipe ends telemetry without a panic.
            if error.kind() == io::ErrorKind::BrokenPipe {
                return Ok(());
            }
            return Err(error);
        }
    }
}
