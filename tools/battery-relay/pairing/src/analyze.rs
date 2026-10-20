//! Offline verification of already-captured advertisements with the PC's own
//! newly written Account Key. No network, device connection or key output.
use anyhow::{Context, Result};
use battery_relay_fastpair_setup::account_key_path;
use battery_relay_receiver::fast_pair::AccountKey;
use serde_json::{Value, json};
use std::{
    fs,
    io::{BufRead, BufReader},
};

pub fn run(path: &str) -> Result<()> {
    let key = AccountKey::load(&account_key_path()?)?;
    let mut count = 0;
    let mut matched = 0;
    let file = BufReader::new(fs::File::open(path)?);
    for line in file.lines() {
        let line = line?;
        // Writer flushes complete lines. In-progress capture files are allowed.
        let item: Value = serde_json::from_str(&line).context("Invalid capture record")?;
        if item["event"] != "advertisement_observation" {
            continue;
        }
        for service in item["services"].as_array().context("Missing services")? {
            if service["uuid"] != "0000fe2c-0000-1000-8000-00805f9b34fb" {
                continue;
            }
            let payload = hex::decode(service["hex"].as_str().context("Missing data")?)?;
            count += 1;
            if let Some(values) = key.decode(&payload) {
                matched += 1;
                println!(
                    "{}",
                    json!({
                        "event":"pc_key_matched_battery",
                        "source":item["source"],
                        "time_ms":item["time_ms"],
                        "rssi":item["rssi"],
                        "left": values.left,
                        "right": values.right,
                        "case": values.case,
                    "validation":"PC Account Key Bloom match + decrypted header and bounded percentages; lid position is supplied by the operator, not inferred by this decoder"
                    })
                );
            }
        }
    }
    println!(
        "{}",
        json!({"event":"summary","fast_pair_observations":count,"matched":matched,"unmatched_or_unsupported":count-matched})
    );
    Ok(())
}
