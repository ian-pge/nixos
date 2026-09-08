use std::time::{SystemTime, UNIX_EPOCH};

// 1998-11-15 00:00:00 in Europe/Paris was 1998-11-14 23:00:00 UTC.
const BIRTH_UNIX_SECONDS: f64 = 911_084_400.0;
const SECONDS_PER_YEAR: f64 = 365.2425 * 24.0 * 60.0 * 60.0;

fn age_at(unix_seconds: f64) -> f64 {
    ((unix_seconds - BIRTH_UNIX_SECONDS) / SECONDS_PER_YEAR).max(0.0)
}

fn main() {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0.0, |duration| duration.as_secs_f64());

    println!("<b> <big> {:.9} </big></b>", age_at(now));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn age_uses_the_same_mean_year_as_the_previous_clock() {
        assert_eq!(age_at(BIRTH_UNIX_SECONDS), 0.0);
        assert!((age_at(BIRTH_UNIX_SECONDS + SECONDS_PER_YEAR) - 1.0).abs() < f64::EPSILON * 2.0);
    }
}
