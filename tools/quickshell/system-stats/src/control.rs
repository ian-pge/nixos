//! Newline-delimited generation: 0 disables top lists, a positive ID starts one.
use std::{
    io::{self, BufRead},
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
    thread,
};

pub fn listen() -> Arc<AtomicU64> {
    let generation = Arc::new(AtomicU64::new(0));
    let input = Arc::clone(&generation);
    thread::spawn(move || {
        for line in io::stdin().lock().lines() {
            let Ok(line) = line else {
                break;
            };
            if let Ok(value) = line.trim().parse::<u64>() {
                input.store(value, Ordering::Relaxed);
            }
        }
        // Losing the controlling pipe must not leave expensive scans enabled.
        input.store(0, Ordering::Relaxed);
    });
    generation
}
