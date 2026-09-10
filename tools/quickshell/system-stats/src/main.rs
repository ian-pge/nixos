use quickshell_system_stats::{Paths, Sampler};
use std::{
    io::{self, Write},
    thread,
    time::{Duration, Instant},
};

fn main() -> io::Result<()> {
    let mut sampler = Sampler::new(Paths::default());
    let start = Instant::now();
    let mut stdout = io::stdout().lock();
    loop {
        thread::sleep(Duration::from_secs(1));
        let value = sampler.sample(start.elapsed());
        if let Err(error) = writeln!(stdout, "{value}").and_then(|_| stdout.flush()) {
            // Quickshell closing the pipe ends telemetry without a panic.
            if error.kind() == io::ErrorKind::BrokenPipe {
                return Ok(());
            }
            return Err(error);
        }
    }
}
