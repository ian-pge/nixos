use anyhow::{Context, Result, bail};
use chrono::{NaiveDate, NaiveTime};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{collections::BTreeMap, fs, io::Write, path::Path};

pub const MAX_AGE: u64 = 24 * 60 * 60;
pub const VERSION: u32 = 2;
pub const LOCATION_URL: &str = "https://fwd.gr/api/tools/ip";

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Location {
    pub name: String,
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Weather {
    pub version: u32,
    pub updated_at: u64,
    pub location: Location,
    #[serde(default)]
    pub location_is_manual: bool,
    pub timezone: String,
    pub temperature_c: Option<f64>,
    pub days: BTreeMap<String, DayWeather>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DayWeather {
    pub code: Option<i64>,
    pub temperature_min_c: Option<f64>,
    pub temperature_max_c: Option<f64>,
    #[serde(default)]
    pub hours: Vec<HourWeather>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HourWeather {
    pub time: String,
    pub code: Option<i64>,
    pub temperature_c: Option<f64>,
    pub apparent_temperature_c: Option<f64>,
    pub precipitation_probability: Option<f64>,
    pub precipitation_mm: Option<f64>,
    pub wind_kmh: Option<f64>,
    pub gusts_kmh: Option<f64>,
}

impl HourWeather {
    fn valid(&self) -> bool {
        self.time.len() == 5
            && NaiveTime::parse_from_str(&self.time, "%H:%M").is_ok()
            && self.temperature_c.is_none_or(f64::is_finite)
            && self.apparent_temperature_c.is_none_or(f64::is_finite)
            && self
                .precipitation_probability
                .is_none_or(|n| n.is_finite() && (0.0..=100.0).contains(&n))
            && [self.precipitation_mm, self.wind_kmh, self.gusts_kmh]
                .iter()
                .all(|n| n.is_none_or(|n| n.is_finite() && n >= 0.0))
    }
}

impl DayWeather {
    fn valid(&self) -> bool {
        self.temperature_min_c.is_none_or(f64::is_finite)
            && self.temperature_max_c.is_none_or(f64::is_finite)
            && !matches!((self.temperature_min_c, self.temperature_max_c),
                (Some(min), Some(max)) if min > max)
            && self.hours.len() <= 25
            && self.hours.iter().all(HourWeather::valid)
    }
}

#[derive(Debug, Serialize)]
pub struct Report<'a> {
    pub data: Option<&'a Weather>,
    pub stale: bool,
    pub error: Option<&'a str>,
    #[serde(rename = "manualLocation")]
    pub manual_location: Option<&'a Location>,
}

pub fn validate_location(location: &Location) -> Result<()> {
    if location.name.trim().is_empty()
        || location.name.chars().count() > 120
        || location.name.chars().any(char::is_control)
        || !location.latitude.is_finite()
        || location.latitude.abs() > 90.0
        || !location.longitude.is_finite()
        || location.longitude.abs() > 180.0
    {
        bail!("invalid location");
    }
    Ok(())
}

#[derive(Debug, Serialize)]
pub struct SearchLocation {
    #[serde(flatten)]
    pub location: Location,
    pub region: String,
    pub country: String,
}

pub fn search_locations(
    query: &str,
    fetch: impl Fn(&str) -> Result<Value>,
) -> Result<Vec<SearchLocation>> {
    let query = query.trim();
    if query.chars().count() < 2 {
        return Ok(Vec::new());
    }
    if query.chars().count() > 120 {
        bail!("query too long");
    }
    let mut encoded = String::new();
    for byte in query.bytes() {
        if byte.is_ascii_alphanumeric() || b"-._~".contains(&byte) {
            encoded.push(byte as char);
        } else {
            encoded.push_str(&format!("%{byte:02X}"));
        }
    }
    let value = fetch(&format!(
        "https://geocoding-api.open-meteo.com/v1/search?name={encoded}&count=8&language=fr&format=json"
    ))?;
    if value["error"].as_bool() == Some(true) {
        bail!("geocoding failed");
    }
    let Some(results) = value.get("results") else {
        return Ok(Vec::new());
    };
    results
        .as_array()
        .context("invalid search results")?
        .iter()
        .take(8)
        .map(|result| {
            let location = Location {
                name: result["name"]
                    .as_str()
                    .context("missing location name")?
                    .to_owned(),
                latitude: coordinate(&result["latitude"], 90.0)?,
                longitude: coordinate(&result["longitude"], 180.0)?,
            };
            validate_location(&location)?;
            let label = |key: &str| {
                result[key]
                    .as_str()
                    .unwrap_or("")
                    .chars()
                    .filter(|c| !c.is_control())
                    .take(120)
                    .collect()
            };
            Ok(SearchLocation {
                location,
                region: label("admin1"),
                country: label("country"),
            })
        })
        .collect()
}

fn coordinate(value: &Value, limit: f64) -> Result<f64> {
    let number = value
        .as_f64()
        .or_else(|| value.as_str()?.parse().ok())
        .context("missing coordinate")?;
    if !number.is_finite() || number.abs() > limit {
        bail!("invalid coordinate");
    }
    Ok(number)
}

pub fn parse_location(value: &Value) -> Result<Location> {
    if value["success"].as_bool() != Some(true) {
        bail!("geolocation request unsuccessful");
    }
    let area = &value["data"]["location"];
    let name: String = area["city"]
        .as_str()
        .context("missing city")?
        .chars()
        .filter(|c| !c.is_control())
        .take(120)
        .collect();
    let name = name.trim();
    if name.is_empty() {
        bail!("missing city");
    }
    Ok(Location {
        name: name.to_owned(),
        latitude: coordinate(&area["latitude"], 90.0)?,
        longitude: coordinate(&area["longitude"], 180.0)?,
    })
}

pub fn forecast_url(location: &Location) -> String {
    format!(
        "https://api.open-meteo.com/v1/forecast?latitude={}&longitude={}&current=temperature_2m&daily=weather_code,temperature_2m_min,temperature_2m_max&hourly=weather_code,temperature_2m,apparent_temperature,precipitation_probability,precipitation,wind_speed_10m,wind_gusts_10m&past_days=31&forecast_days=16&timezone=auto&temperature_unit=celsius&wind_speed_unit=kmh&precipitation_unit=mm",
        location.latitude, location.longitude
    )
}

fn valid_date(value: &str) -> bool {
    value.len() == 10
        && NaiveDate::parse_from_str(value, "%Y-%m-%d")
            .is_ok_and(|date| date.format("%Y-%m-%d").to_string() == value)
}

fn optional_temperature(value: &Value) -> Result<Option<f64>> {
    if value.is_null() {
        Ok(None)
    } else {
        Ok(Some(
            value
                .as_f64()
                .filter(|value| value.is_finite())
                .context("invalid temperature")?,
        ))
    }
}

pub fn parse_forecast(value: &Value, location: Location, now: u64) -> Result<Weather> {
    let dates = value["daily"]["time"]
        .as_array()
        .context("missing daily dates")?;
    let codes = value["daily"]["weather_code"]
        .as_array()
        .context("missing daily codes")?;
    let minimums = value["daily"]["temperature_2m_min"]
        .as_array()
        .context("missing daily minimum temperatures")?;
    let maximums = value["daily"]["temperature_2m_max"]
        .as_array()
        .context("missing daily maximum temperatures")?;
    if dates.is_empty()
        || dates.len() != codes.len()
        || dates.len() > 64
        || dates.len() != minimums.len()
        || dates.len() != maximums.len()
    {
        bail!("invalid daily arrays");
    }
    let mut days = BTreeMap::new();
    for (index, (date, code)) in dates.iter().zip(codes).enumerate() {
        let date = date
            .as_str()
            .filter(|date| valid_date(date))
            .context("invalid date")?;
        let code = if code.is_null() {
            None
        } else {
            Some(code.as_i64().context("invalid weather code")?)
        };
        let day = DayWeather {
            code,
            temperature_min_c: optional_temperature(&minimums[index])?,
            temperature_max_c: optional_temperature(&maximums[index])?,
            hours: Vec::new(),
        };
        if !day.valid() || days.insert(date.to_string(), day).is_some() {
            bail!("invalid or duplicate daily data");
        }
    }
    if let Some(hourly) = value.get("hourly") {
        parse_hours(hourly, &mut days)?;
    }
    let timezone = value["timezone"]
        .as_str()
        .filter(|zone| !zone.is_empty())
        .context("missing timezone")?
        .to_owned();
    let temperature_c = optional_temperature(&value["current"]["temperature_2m"])?;
    Ok(Weather {
        version: VERSION,
        updated_at: now,
        location,
        location_is_manual: false,
        timezone,
        temperature_c,
        days,
    })
}

fn parse_hours(value: &Value, days: &mut BTreeMap<String, DayWeather>) -> Result<()> {
    let times = value["time"].as_array().context("missing hourly times")?;
    let keys = [
        "weather_code",
        "temperature_2m",
        "apparent_temperature",
        "precipitation_probability",
        "precipitation",
        "wind_speed_10m",
        "wind_gusts_10m",
    ];
    let arrays = keys
        .iter()
        .map(|key| {
            value[*key]
                .as_array()
                .filter(|values| values.len() == times.len())
                .context("invalid hourly array")
        })
        .collect::<Result<Vec<_>>>()?;
    if times.len() > 64 * 25 {
        bail!("too many hourly values");
    }
    for (index, time) in times.iter().enumerate() {
        let time = time.as_str().context("invalid hourly time")?;
        let (date, time) = time.split_once('T').context("invalid hourly timestamp")?;
        let day = days.get_mut(date).context("hour outside daily coverage")?;
        let code = &arrays[0][index];
        let hour = HourWeather {
            time: time.to_owned(),
            code: if code.is_null() {
                None
            } else {
                Some(code.as_i64().context("invalid hourly code")?)
            },
            temperature_c: optional_temperature(&arrays[1][index])?,
            apparent_temperature_c: optional_temperature(&arrays[2][index])?,
            precipitation_probability: optional_temperature(&arrays[3][index])?,
            precipitation_mm: optional_temperature(&arrays[4][index])?,
            wind_kmh: optional_temperature(&arrays[5][index])?,
            gusts_kmh: optional_temperature(&arrays[6][index])?,
        };
        if !hour.valid() || day.hours.len() >= 25 {
            bail!("invalid hourly data");
        }
        day.hours.push(hour);
    }
    Ok(())
}

pub fn load_cache(path: &Path, now: u64) -> Option<Weather> {
    if fs::metadata(path).ok()?.len() > 1024 * 1024 {
        return None;
    }
    let weather: Weather = serde_json::from_slice(&fs::read(path).ok()?).ok()?;
    if weather.version != VERSION
        || weather.updated_at > now
        || now - weather.updated_at > MAX_AGE
        || weather.days.len() > 64
        || weather.days.keys().any(|date| !valid_date(date))
        || weather.days.values().any(|day| !day.valid())
        || weather.location.name.is_empty()
        || weather.timezone.is_empty()
        || !weather.location.latitude.is_finite()
        || weather.location.latitude.abs() > 90.0
        || !weather.location.longitude.is_finite()
        || weather.location.longitude.abs() > 180.0
    {
        return None;
    }
    Some(weather)
}

fn save_cache(path: &Path, weather: &Weather) -> Result<()> {
    let directory = path.parent().context("missing cache directory")?;
    fs::create_dir_all(directory)?;
    let mut file = tempfile::NamedTempFile::new_in(directory)?;
    serde_json::to_writer(&mut file, weather)?;
    file.flush()?;
    file.persist(path)?;
    Ok(())
}

/// One process, JSON Lines: cached data immediately, then a refreshed result.
/// Never combine a newly detected city with forecasts cached for another city.
pub fn update(
    path: &Path,
    now: u64,
    fetch: impl Fn(&str) -> Result<Value>,
    emit: impl FnMut(Report<'_>) -> Result<()>,
) -> Result<()> {
    update_with_location(path, now, None, fetch, emit)
}

pub fn update_with_location(
    path: &Path,
    now: u64,
    manual: Option<&Location>,
    fetch: impl Fn(&str) -> Result<Value>,
    mut emit: impl FnMut(Report<'_>) -> Result<()>,
) -> Result<()> {
    if let Some(location) = manual {
        validate_location(location)?;
    }
    let cached = load_cache(path, now).filter(|weather| {
        weather.location_is_manual == manual.is_some()
            && manual.is_none_or(|location| {
                location.name == weather.location.name
                    && location.latitude == weather.location.latitude
                    && location.longitude == weather.location.longitude
            })
    });
    if let Some(weather) = &cached {
        emit(Report {
            data: Some(weather),
            stale: now - weather.updated_at >= 3600,
            error: None,
            manual_location: manual,
        })?;
    }
    let fresh = (|| {
        let location = match manual {
            Some(location) => location.clone(),
            None => parse_location(&fetch(LOCATION_URL)?)?,
        };
        let mut weather = parse_forecast(&fetch(&forecast_url(&location))?, location, now)?;
        weather.location_is_manual = manual.is_some();
        Ok::<_, anyhow::Error>(weather)
    })();
    match fresh {
        Ok(weather) => {
            if let Err(error) = save_cache(path, &weather) {
                eprintln!("Unable to save weather cache: {error}");
            }
            emit(Report {
                data: Some(&weather),
                stale: false,
                error: None,
                manual_location: manual,
            })
        }
        Err(error) => {
            eprintln!("Weather refresh failed: {error}");
            emit(Report {
                data: cached.as_ref(),
                stale: true,
                error: Some("Météo indisponible"),
                manual_location: manual,
            })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn location_search_encodes_queries_and_returns_unambiguous_labels() {
        let results = search_locations(" Saint-Étienne, France &x=1 ", |url| {
            assert!(url.contains("name=Saint-%C3%89tienne%2C%20France%20%26x%3D1&"));
            assert!(url.contains("language=fr"));
            Ok(
                json!({"results": [{"name": "Saint-Étienne", "latitude": 45.4,
                "longitude": 4.4, "admin1": "Auvergne-Rhône-Alpes", "country": "France"}]}),
            )
        })
        .unwrap();
        assert_eq!(results[0].location.name, "Saint-Étienne");
        assert_eq!(results[0].region, "Auvergne-Rhône-Alpes");
        assert_eq!(results[0].country, "France");
        assert!(
            search_locations("x", |_| panic!("short query must not fetch"))
                .unwrap()
                .is_empty()
        );
        assert!(
            search_locations("missing", |_| Ok(json!({})))
                .unwrap()
                .is_empty()
        );
        assert!(
            search_locations("Paris", |_| Ok(json!({"results": [
            {"name": "Paris", "latitude": 100, "longitude": 2}]})))
            .is_err()
        );
    }

    #[test]
    fn manual_location_rejects_invalid_coordinates() {
        let location = parse_location(&location_response()).unwrap();
        assert!(validate_location(&location).is_ok());
        let mut invalid = location.clone();
        invalid.longitude = 181.0;
        assert!(validate_location(&invalid).is_err());
    }

    #[test]
    fn manual_location_bypasses_ip_and_never_reuses_another_city_cache() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("weather.json");
        save_cache(&path, &weather(100)).unwrap();
        let paris = parse_location(&location_response()).unwrap();
        let lyon = Location {
            name: "Lyon".into(),
            latitude: 45.75,
            longitude: 4.85,
        };
        let mut reports = Vec::new();
        update_with_location(
            &path,
            200,
            Some(&lyon),
            |url| {
                assert!(!url.contains("fwd.gr"));
                assert!(url.contains("latitude=45.75"));
                Ok(forecast())
            },
            |report| {
                reports.push(serde_json::to_value(report)?);
                Ok(())
            },
        )
        .unwrap();
        assert_eq!(reports.len(), 1);
        assert_eq!(reports[0]["data"]["location"]["name"], "Lyon");
        assert_eq!(reports[0]["manualLocation"]["name"], "Lyon");
        reports.clear();
        update_with_location(
            &path,
            300,
            Some(&paris),
            |_| bail!("offline"),
            |report| {
                reports.push(serde_json::to_value(report)?);
                Ok(())
            },
        )
        .unwrap();
        assert_eq!(reports.len(), 1);
        assert!(reports[0]["data"].is_null());
        assert_eq!(reports[0]["manualLocation"]["name"], "Paris");
        reports.clear();
        update(
            &path,
            300,
            |_| bail!("offline"),
            |report| {
                reports.push(serde_json::to_value(report)?);
                Ok(())
            },
        )
        .unwrap();
        assert_eq!(reports.len(), 1);
        assert!(reports[0]["data"].is_null());
        assert!(reports[0]["manualLocation"].is_null());
    }

    fn location_response() -> Value {
        json!({"success": true, "data": {"location": {
            "city": "Paris", "latitude": 48.85, "longitude": 2.35
        }}})
    }
    fn forecast() -> Value {
        json!({"timezone": "Europe/Paris", "current": {"temperature_2m": 0.0},
            "daily": {"time": ["2026-09-09", "2026-09-10", "2026-09-11"], "weather_code": [3, 0, null],
                "temperature_2m_min": [-3.5, 0.0, null], "temperature_2m_max": [0.0, 12.5, null]}})
    }
    fn weather(now: u64) -> Weather {
        parse_forecast(
            &forecast(),
            parse_location(&location_response()).unwrap(),
            now,
        )
        .unwrap()
    }

    fn forecast_with_hours() -> Value {
        let mut value = forecast();
        value["hourly"] = json!({
            "time": ["2026-09-10T00:00", "2026-09-10T01:00", "2026-09-11T00:00"],
            "weather_code": [0, 61, null], "temperature_2m": [0, -1, null],
            "apparent_temperature": [-2, -3, null], "precipitation_probability": [0, 70, null],
            "precipitation": [0, 1.2, null], "wind_speed_10m": [8, 12, null],
            "wind_gusts_10m": [15, 24, null]
        });
        value
    }

    #[test]
    fn hourly_details_preserve_local_days_nulls_and_zeroes() {
        let weather = parse_forecast(
            &forecast_with_hours(),
            parse_location(&location_response()).unwrap(),
            100,
        )
        .unwrap();
        assert!(weather.days["2026-09-09"].hours.is_empty());
        let hours = &weather.days["2026-09-10"].hours;
        assert_eq!(hours.len(), 2);
        assert_eq!(hours[0].time, "00:00");
        assert_eq!(hours[0].temperature_c, Some(0.0));
        assert_eq!(hours[0].precipitation_probability, Some(0.0));
        assert_eq!(hours[1].apparent_temperature_c, Some(-3.0));
        assert_eq!(hours[1].precipitation_mm, Some(1.2));
        assert_eq!(hours[1].wind_kmh, Some(12.0));
        assert_eq!(hours[1].gusts_kmh, Some(24.0));
        assert_eq!(weather.days["2026-09-11"].hours[0].temperature_c, None);
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("weather.json");
        save_cache(&path, &weather).unwrap();
        assert_eq!(
            load_cache(&path, 100).unwrap().days["2026-09-10"]
                .hours
                .len(),
            2
        );
    }

    #[test]
    fn malformed_hourly_data_is_rejected() {
        for (field, values) in [
            (
                "time",
                json!(["2026-09-10T25:00", "2026-09-10T01:00", "2026-09-11T00:00"]),
            ),
            (
                "time",
                json!(["2026-09-12T00:00", "2026-09-10T01:00", "2026-09-11T00:00"]),
            ),
            ("temperature_2m", json!([1])),
            ("precipitation_probability", json!([101, 70, null])),
            ("precipitation", json!([-1, 1, null])),
            ("wind_speed_10m", json!(["fast", 1, null])),
        ] {
            let mut value = forecast_with_hours();
            value["hourly"][field] = values;
            assert!(
                parse_forecast(&value, parse_location(&location_response()).unwrap(), 100).is_err(),
                "{field}"
            );
        }
    }

    #[test]
    fn daily_only_v2_cache_remains_readable() {
        let mut value = serde_json::to_value(weather(100)).unwrap();
        for day in value["days"].as_object_mut().unwrap().values_mut() {
            day.as_object_mut().unwrap().remove("hours");
        }
        let old: Weather = serde_json::from_value(value).unwrap();
        assert!(
            old.days
                .values()
                .all(|day| day.hours.is_empty() && day.valid())
        );
    }

    #[test]
    fn location_and_query_preserve_auto_location_and_horizon() {
        assert_eq!(LOCATION_URL, "https://fwd.gr/api/tools/ip");
        let location = parse_location(&location_response()).unwrap();
        assert_eq!(location.name, "Paris");
        let url = forecast_url(&location);
        for parameter in [
            "latitude=48.85",
            "longitude=2.35",
            "past_days=31",
            "forecast_days=16",
            "timezone=auto",
            "daily=weather_code,temperature_2m_min,temperature_2m_max",
        ] {
            assert!(url.contains(parameter));
        }
    }
    #[test]
    fn geolocation_requires_success_city_and_valid_coordinates() {
        for success in [json!(false), Value::Null, json!("true")] {
            let mut value = location_response();
            value["success"] = success;
            assert!(parse_location(&value).is_err());
        }
        for city in [Value::Null, json!(""), json!(" \n\t\u{0000} "), json!(42)] {
            let mut value = location_response();
            value["data"]["location"]["city"] = city;
            assert!(parse_location(&value).is_err());
        }
        for key in ["latitude", "longitude"] {
            for coordinate in [
                Value::Null,
                json!(true),
                json!("NaN"),
                json!("inf"),
                json!("oops"),
            ] {
                let mut value = location_response();
                value["data"]["location"][key] = coordinate;
                assert!(parse_location(&value).is_err());
            }
        }
        for (key, coordinate) in [
            ("latitude", 91),
            ("latitude", -91),
            ("longitude", 181),
            ("longitude", -181),
        ] {
            let mut value = location_response();
            value["data"]["location"][key] = json!(coordinate);
            assert!(parse_location(&value).is_err());
        }
        for value in [
            json!({}),
            json!({"success": true}),
            json!({"success": true, "data": {"location": null}}),
        ] {
            assert!(parse_location(&value).is_err());
        }
    }
    #[test]
    fn geolocation_normalizes_only_city_and_coordinates() {
        let mut value = location_response();
        value["data"]["location"]["city"] = json!(" \nSaint-Martin-d’Hères\t ");
        value["data"]["location"]["latitude"] = json!("0");
        value["data"]["location"]["longitude"] = json!(-180);
        // Documentation-only IP: this metadata must never reach the cache or UI.
        value["data"]["ip"] = json!("2001:db8::1");
        value["data"]["network"] = json!({"asn": 64500});
        value["data"]["security"] = json!({"isVpn": false});
        value["data"]["userAgent"] = json!("example client");
        assert_eq!(
            serde_json::to_value(parse_location(&value).unwrap()).unwrap(),
            json!({
                "name": "Saint-Martin-d’Hères", "latitude": 0.0, "longitude": -180.0
            })
        );
        value["data"]["location"]["city"] = json!("é".repeat(121));
        assert_eq!(parse_location(&value).unwrap().name.chars().count(), 120);
    }
    #[test]
    fn zero_temperature_clear_sky_null_and_dates_survive() {
        let weather = weather(100);
        assert_eq!(weather.temperature_c, Some(0.0));
        assert_eq!(weather.days["2026-09-10"].code, Some(0));
        assert_eq!(weather.days["2026-09-10"].temperature_min_c, Some(0.0));
        assert_eq!(weather.days["2026-09-10"].temperature_max_c, Some(12.5));
        assert_eq!(weather.days["2026-09-09"].temperature_min_c, Some(-3.5));
        assert_eq!(weather.days["2026-09-09"].temperature_max_c, Some(0.0));
        assert_eq!(weather.days["2026-09-11"].code, None);
        assert_eq!(weather.days["2026-09-11"].temperature_min_c, None);
        assert_eq!(weather.days["2026-09-11"].temperature_max_c, None);
        assert!(!weather.days.contains_key("2026-09-12"));
        let report = serde_json::to_value(weather).unwrap();
        assert_eq!(report["version"], VERSION);
        assert_eq!(report["days"]["2026-09-10"]["temperatureMinC"], 0.0);
        assert_eq!(report["days"]["2026-09-10"]["temperatureMaxC"], 12.5);
    }
    #[test]
    fn malformed_forecast_cannot_replace_cache() {
        for invalid in [
            json!({}),
            json!({"error": true}),
            {
                let mut value = forecast();
                value["daily"]["time"][0] = json!("2026-02-29");
                value
            },
            {
                let mut value = forecast();
                value["daily"]["weather_code"] = json!([0]);
                value
            },
            {
                let mut value = forecast();
                value["daily"]["temperature_2m_min"] = json!([0]);
                value
            },
            {
                let mut value = forecast();
                value["daily"]["temperature_2m_max"] = Value::Null;
                value
            },
            {
                let mut value = forecast();
                value["daily"]["temperature_2m_max"][0] = json!("12");
                value
            },
            {
                let mut value = forecast();
                value["daily"]["temperature_2m_min"][0] = json!(20);
                value
            },
            {
                let mut value = forecast();
                value["daily"]["time"][0] = json!("2026-09-10");
                value
            },
        ] {
            assert!(
                parse_forecast(&invalid, parse_location(&location_response()).unwrap(), 100)
                    .is_err()
            );
        }
        assert!(valid_date("2024-02-29"));
        assert!(!valid_date("2026-9-10"));
    }
    #[test]
    fn cache_expiry_future_timestamp_and_corruption() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("weather.json");
        save_cache(&path, &weather(100)).unwrap();
        assert!(load_cache(&path, 100).is_some());
        assert!(load_cache(&path, 100 + MAX_AGE).is_some());
        assert!(load_cache(&path, 101 + MAX_AGE).is_none());
        assert!(load_cache(&path, 99).is_none());
        let mut old = weather(100);
        old.version = 1;
        save_cache(&path, &old).unwrap();
        assert!(load_cache(&path, 100).is_none());
        fs::write(&path, "{broken").unwrap();
        assert!(load_cache(&path, 100).is_none());
    }
    #[test]
    fn successful_refresh_then_offline_fallback_then_expiry() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("weather.json");
        let mut reports = Vec::new();
        update(
            &path,
            100,
            |url| {
                Ok(if url == LOCATION_URL {
                    location_response()
                } else {
                    forecast()
                })
            },
            |report| {
                reports.push(serde_json::to_value(report)?);
                Ok(())
            },
        )
        .unwrap();
        assert_eq!(reports.len(), 1);
        assert_eq!(reports[0]["data"]["temperatureC"], 0.0);
        reports.clear();
        update(
            &path,
            200,
            |_| bail!("offline"),
            |report| {
                reports.push(serde_json::to_value(report)?);
                Ok(())
            },
        )
        .unwrap();
        assert_eq!(reports.len(), 2);
        assert_eq!(reports[1]["data"]["updatedAt"], 100);
        assert_eq!(reports[1]["stale"], true);
        reports.clear();
        update(
            &path,
            101 + MAX_AGE,
            |_| bail!("offline"),
            |report| {
                reports.push(serde_json::to_value(report)?);
                Ok(())
            },
        )
        .unwrap();
        assert_eq!(reports.len(), 1);
        assert!(reports[0]["data"].is_null());
    }
    #[test]
    fn refresh_replaces_previous_city_and_forecast_together() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("weather.json");
        save_cache(&path, &weather(100)).unwrap();
        let mut reports = Vec::new();
        update(
            &path,
            200,
            |url| {
                if url == LOCATION_URL {
                    Ok(json!({"success": true, "data": {"location": {
                        "city": "Grenoble", "latitude": 45.17869, "longitude": 5.71479
                    }}}))
                } else {
                    assert!(url.starts_with("https://api.open-meteo.com/v1/forecast?latitude=45.17869&longitude=5.71479&"));
                    let mut value = forecast();
                    value["current"]["temperature_2m"] = json!(18);
                    Ok(value)
                }
            },
            |report| {
                reports.push(serde_json::to_value(report)?);
                Ok(())
            },
        ).unwrap();
        assert_eq!(reports.len(), 2);
        assert_eq!(reports[0]["data"]["location"]["name"], "Paris");
        assert_eq!(reports[0]["data"]["temperatureC"], 0.0);
        assert_eq!(reports[1]["data"]["location"]["name"], "Grenoble");
        assert_eq!(reports[1]["data"]["temperatureC"], 18.0);
        assert_eq!(reports[1]["stale"], false);
        assert!(reports[1]["error"].is_null());
        let cached = load_cache(&path, 200).unwrap();
        assert_eq!(cached.location.name, "Grenoble");
        assert_eq!(cached.temperature_c, Some(18.0));
        assert_eq!(cached.updated_at, 200);
    }
    #[test]
    fn failed_geolocation_preserves_cache_without_requesting_forecast() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("weather.json");
        save_cache(&path, &weather(100)).unwrap();
        let original = fs::read(&path).unwrap();
        for response in [
            json!({"success": false, "error": "unavailable"}),
            json!({"success": true, "data": {}}),
        ] {
            let mut reports = Vec::new();
            update(
                &path,
                200,
                |url| {
                    assert_eq!(url, LOCATION_URL);
                    Ok(response.clone())
                },
                |report| {
                    reports.push(serde_json::to_value(report)?);
                    Ok(())
                },
            )
            .unwrap();
            assert_eq!(reports.len(), 2);
            assert_eq!(reports[1]["data"]["location"]["name"], "Paris");
            assert_eq!(reports[1]["data"]["updatedAt"], 100);
            assert_eq!(reports[1]["stale"], true);
            assert_eq!(reports[1]["error"], "Météo indisponible");
            assert_eq!(fs::read(&path).unwrap(), original);
        }
    }
    #[test]
    fn failed_forecast_does_not_mix_locations_or_overwrite_cache() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("weather.json");
        save_cache(&path, &weather(100)).unwrap();
        update(
            &path,
            200,
            |url| {
                if url != LOCATION_URL {
                    bail!("forecast unavailable");
                }
                let mut value = location_response();
                value["data"]["location"]["city"] = json!("Lyon");
                Ok(value)
            },
            |report| {
                assert_eq!(report.data.unwrap().location.name, "Paris");
                Ok(())
            },
        )
        .unwrap();
        assert_eq!(load_cache(&path, 200).unwrap().updated_at, 100);
    }
}
