# Quickshell weather

`quickshell-weather` supplies the bar temperature and monthly calendar from a
single shared process. It detects the current connection's approximate location
using `https://fwd.gr/api/tools/ip` (Cloudflare IP geolocation), then requests Open-Meteo's current temperature
and daily WMO weather codes plus minimum/maximum temperatures, alongside hourly
conditions, temperature, apparent temperature, precipitation probability and
amount, wind speed and gusts (`past_days=31`,
`forecast_days=16`, `timezone=auto`). IP geolocation can be inaccurate, even on
fixed fibre connections, and particularly behind VPNs. All returned daily
dates remain local ISO date strings; do not parse them as UTC instants. Past Days
are archived model data, not measured observations. Dates beyond the returned
coverage have no weather icon.

Location lookup needs no account, API key, Wi-Fi scanning or extra system service.
Press `s` in the calendar or day detail to search cities/postcodes through
Open-Meteo's geocoding API. Results include region and country. Arrow keys and
Enter or a mouse click select a result; Escape returns to the previous view.
A searched city lasts only for the current calendar session. Every new opening
returns to automatic IP geolocation and refreshes it, even if the previous report
is recent. Notification/Polkit restoration and moving an already-open calendar to
another monitor preserve the current city. The search contains cities only, with
no automatic/manual mode choice. There is no saved location preference; legacy
`location.json` files are ignored. Requests for a searched city skip IP geolocation.
Keep curl's default IPv4/IPv6 selection: the two addresses can be located
differently, so do not force IPv4. The API's successful `data.location` response
is normalized to city name, latitude and longitude only. IP address and other
network/client metadata are neither emitted nor cached.

## Protocol and cache

Standard output is JSON Lines, each containing `data`, `stale`, `error`, and
`manualLocation` (null in automatic mode). Snapshots include `locationIsManual`;
old v2 snapshots default to automatic mode. A cache from another city or location
mode is never emitted for a newly selected location.
When available, the cached snapshot is emitted immediately, then the refreshed
snapshot or an offline report. The snapshot contains `version`, `updatedAt`
(Unix seconds), `location`, `timezone`, nullable `temperatureC`, and `days`
(ISO dates mapped to `{code, temperatureMinC, temperatureMaxC, hours}`). Each
hour contains local `time` (`HH:mm`), nullable `code`, `temperatureC`,
`apparentTemperatureC`, `precipitationProbability` (%), `precipitationMm`,
`windKmh`, and `gustsKmh`. Rain amounts cover the preceding hour. Old v2 snapshots
without `hours` remain readable; hourly details appear after a successful refresh.
The protocol version is `2`; temperatures are Celsius. Diagnostics go to standard error.

Only complete successful snapshots replace
`$XDG_CACHE_HOME/quickshell/weather/v2.json` (or `$HOME/.cache/...`), atomically.
Temporary city requests use a separate `manual-v2.json` cache so local weather
remains available offline after browsing another city.
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
Calendar cells show monochrome Nerd Font weather icons (green for clear/partly
cloudy skies, red for drizzle/rain/showers/thunderstorms, the weather accent otherwise),
with rounded min/max temperatures beneath them. Missing or incomplete temperature
ranges remain blank; zero and negative temperatures are preserved. Days beyond
forecast coverage show only their date. The old v1 cache is not reused or deleted.

`h/j/k/l` and arrow keys select days (left/right: one day; up/down: one week).
`u/d` or Page Up/Down change months while clamping the selected day to the target
month. Clicking a day or pressing Enter opens its hourly detail in the same panel.
In detail, `h/l` change days, `j/k` and the mouse wheel scroll hours, and Escape
or the back chevron returns to the grid. A second Escape closes the calendar.
`n` or Home returns to today in the grid, including from detail. The selected day
uses the same background, outline and bold number as today, with an orange accent.
Selection and detail state are shared across monitors.

CLI options: `--search QUERY` returns `{results, error}`; `--location JSON`
uses `{name, latitude, longitude}` for this request only. No arguments means
automatic IP geolocation. The shared QML service debounces searches, ignores
obsolete responses, and refreshes immediately after selection or reopening.
If a forecast request is already in flight, it finishes before the new one starts;
its response is ignored after the location changes.

## Verification

```sh
nix develop .#rust --command cargo test --manifest-path tools/quickshell/weather/Cargo.toml
nix build --no-link .#quickshellWeather
```

Tests use local fixtures and isolated temporary caches, never live weather APIs.
`--help` does not access the network. The QML calendar and weather-state tests live
under `desktop/tests/`; the frontend sources are in `desktop/features/calendar/`.

Sources: [fwd.gr IP API](https://fwd.gr/tools/ip-api),
[Open-Meteo Forecast API](https://open-meteo.com/en/docs).
