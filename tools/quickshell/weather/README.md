# Quickshell weather

`quickshell-weather` supplies the bar temperature and monthly calendar from a
single shared process. It detects the current connection's approximate location
using `https://fwd.gr/api/tools/ip` (Cloudflare IP geolocation), then requests Open-Meteo's current temperature
and daily WMO weather codes plus minimum/maximum temperatures (`past_days=31`,
`forecast_days=16`, `timezone=auto`). IP geolocation can be inaccurate, even on
fixed fibre connections, and particularly behind VPNs. All returned daily
dates remain local ISO date strings; do not parse them as UTC instants. Past Days
are archived model data, not measured observations. Dates beyond the returned
coverage have no weather icon.

Location lookup needs no account, API key, Wi-Fi scanning or extra system service.
Keep curl's default IPv4/IPv6 selection: the two addresses can be located
differently, so do not force IPv4. The API's successful `data.location` response
is normalized to city name, latitude and longitude only. IP address and other
network/client metadata are neither emitted nor cached.

## Protocol and cache

Standard output is JSON Lines, each containing `data`, `stale`, and `error`.
When available, the cached snapshot is emitted immediately, then the refreshed
snapshot or an offline report. The snapshot contains `version`, `updatedAt`
(Unix seconds), `location`, `timezone`, nullable `temperatureC`, and `days`
(ISO dates mapped to `{code, temperatureMinC, temperatureMaxC}`, all nullable).
The protocol version is `2`; temperatures are Celsius. Diagnostics go to standard error.

Only complete successful snapshots replace
`$XDG_CACHE_HOME/quickshell/weather/v2.json` (or `$HOME/.cache/...`), atomically.
Cache data older than 24 hours, invalid versions, malformed dates and future
timestamps are ignored. A geolocation/forecast failure retains the previous
city and its data together, marked stale. No fresh city is paired with old data.
Existing v2 snapshots remain compatible when changing geolocation providers and
are replaced after the first complete successful refresh.

The Rust binary invokes `curl` directly with argument arrays, HTTPS-only URLs,
a 5-second connection timeout, 12-second request timeout and 1 MiB response cap.
Its Nix wrapper pins curl in PATH. Rust handles validation, normalized output,
cache expiry and atomic replacement. No shell parsing of weather output occurs.

`WeatherData.qml` launches this command at startup, hourly and on calendar opening
when stale. Repeated openings within one minute do not retry a failed request.
One snapshot is shared by all monitors. The UI rechecks expiry every minute and
displays `--°`/no daily weather after the maximum age, while the calendar remains usable.
Calendar cells show monochrome Nerd Font weather icons in `Theme.sideWeather`,
with rounded min/max temperatures beneath them. Missing or incomplete temperature
ranges remain blank; zero and negative temperatures are preserved. Days beyond
forecast coverage show only their date. The old v1 cache is not reused or deleted.

## Verification

```sh
nix develop .#rust --command cargo test --manifest-path tools/quickshell/weather/Cargo.toml
nix build --no-link .#quickshellWeather
```

Tests use local fixtures and isolated temporary caches, never live weather APIs.
`--help` does not access the network. The QML calendar and weather-state tests live
under `home_manager/quickshell/top-bar/tests/`.

Sources: [fwd.gr IP API](https://fwd.gr/tools/ip-api),
[Open-Meteo Forecast API](https://open-meteo.com/en/docs).
