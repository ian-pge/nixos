//! Use the same suspend-aware clock for both readers' freshness deadlines.
use anyhow::{Result, ensure};
use std::time::Duration;

pub fn boot_time() -> Result<Duration> {
    let mut value = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    // SAFETY: one valid timespec and a supported Linux clock.
    ensure!(
        unsafe { libc::clock_gettime(libc::CLOCK_BOOTTIME, &mut value) } == 0,
        "Cannot read suspend-aware clock"
    );
    Ok(Duration::new(
        value.tv_sec.try_into()?,
        value.tv_nsec.try_into()?,
    ))
}
