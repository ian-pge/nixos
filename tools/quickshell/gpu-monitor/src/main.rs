mod control;
use quickshell_gpu_monitor::{Nvidia, PCI_ROOT, Sampler};
use std::{
    io::{self, Write},
    path::PathBuf,
    sync::atomic::Ordering,
    thread,
    time::{Duration, Instant},
};

fn main() -> anyhow::Result<()> {
    let mut root = PathBuf::from(PCI_ROOT);
    let mut once = false;
    let mut args = std::env::args_os().skip(1);
    while let Some(arg) = args.next() {
        match arg.to_str() {
            Some("--once") => once = true,
            Some("--sysfs-root") => {
                root = args
                    .next()
                    .map(PathBuf::from)
                    .ok_or_else(|| anyhow::anyhow!("--sysfs-root requires a directory"))?
            }
            Some("--help" | "-h") => {
                println!("quickshell-gpu-monitor [--once] [--sysfs-root DIRECTORY]");
                return Ok(());
            }
            _ => anyhow::bail!("Unknown argument: {}", arg.to_string_lossy()),
        }
    }
    let mut sampler = Sampler::new(root, Nvidia::default());
    let control = control::listen();
    let started = Instant::now();
    let mut stdout = io::stdout().lock();
    loop {
        let tick = Instant::now();
        let report = serde_json::to_string(
            &sampler.sample_with_top(started.elapsed(), control.load(Ordering::Relaxed)),
        )?;
        if let Err(error) = writeln!(stdout, "{report}").and_then(|_| stdout.flush()) {
            if error.kind() == io::ErrorKind::BrokenPipe {
                return Ok(());
            }
            return Err(error.into());
        }
        if once {
            return Ok(());
        }
        thread::sleep(Duration::from_secs(1).saturating_sub(tick.elapsed()));
    }
}
