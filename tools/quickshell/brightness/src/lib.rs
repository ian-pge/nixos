pub mod brightness;
pub mod process;

use anyhow::Result;
use serde_json::Value;
use std::io::{self, Write};

pub fn output(value: &Value) -> Result<()> {
    writeln!(io::stdout().lock(), "{value}")?;
    Ok(())
}

pub fn main_result(task: impl FnOnce(&process::Runner) -> Result<()>) {
    let result = process::Runner::new().and_then(|runner| {
        let result = task(&runner);
        if let Err(error) = &result {
            let _ = writeln!(io::stderr(), "{error:#}");
        }
        if let Some(signal) = runner.signal() {
            std::process::exit(128 + signal);
        }
        result
    });
    if result.is_err() {
        std::process::exit(1);
    }
}

pub fn now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
