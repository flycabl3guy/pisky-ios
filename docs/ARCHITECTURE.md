# PiSky — Architecture Report (Android source → iOS port)

This is the architecture breakdown of the existing **PiSky Android** app (Kotlin / Jetpack
Compose, 19 Gradle modules, ~29 K LOC) that this iOS project ports to native SwiftUI. It is
the reference for the port; read it alongside [ANDROID_TO_IOS_MAPPING.md](ANDROID_TO_IOS_MAPPING.md)
(component-by-component equivalents) and [PORTING_NOTES.md](PORTING_NOTES.md) (what can't port 1:1).

PiSky is a **read-only ADS-B receiver dashboard**. It polls a home PiAware/Ultrafeeder receiver
(reverse-proxied by an `nginx` host at `192.168.1.207:8088`) over HTTP/JSON, classifies and
enriches aircraft, and renders ~20 instrument-style screens. There is no write path to the
receiver, no accounts, no cloud — all state is local.

---

## 1. Layered structure

```
app            → shell: MainActivity, navigation graph, foreground TrackingService, PiSkyApp (Application)
core:domain    → pure models, enums, repository interfaces, classification + integrity + telemetry logic
core:network   → Retrofit services, kotlinx.serialization DTOs, DTO→domain mappers, Prometheus parser
core:data      → Room DB, DataStore prefs, repository IMPLEMENTATIONS, WorkManager, notifications, ErrorLog
core:ui        → Compose theme (Hangar Luxe), shared components, custom-Canvas chart/meter/gauge toolkit
feature:*      → 14 feature modules, one per screen-family (see §5)
```

Dependency direction: `feature → core:data/ui → core:network → core:domain`. `core:domain` has no
Android dependencies and ports almost verbatim to Swift.

The iOS port collapses the Gradle multi-module graph into **folder groups inside one app target**
(SwiftPM multi-module is unnecessary for a solo app). Same layering, same names:
`Domain/ · Network/ · Data/ · DesignSystem/ · Features/ · App/`.

---

## 2. Data contract (the spine of the port)

The whole app is driven by one polled JSON document, `aircraft.json`, mapped into the domain
`Aircraft` model. **Field-name/type fidelity here is the single most important thing in the port** —
these become Swift `Codable` structs.

- **`AircraftDto`** (76 fields) — wire shape of `aircraft.json`. snake_case keys via `@SerialName`
  (`alt_baro`, `nac_p`, `gs`, `nav_modes`, `dbFlags`, `routeset{from,to}`, …). `alt_baro` is a union
  (`Int | "ground"`) handled by a custom serializer → ports to a Swift enum + custom `Codable`.
- **`Aircraft`** (61 fields) — domain model with computed display props (`routeDisplay`,
  `isMilitary`, `isInteresting/isPia/isLadd` from `dbFlags` bit masks, `displayCallsign`,
  `typeDescription`, `altitudeDisplay`, `speedDisplay`, `verticalRateDisplay`).
- **`StatsDto`** — full readsb `stats.json` hierarchy (`last1min/5min/15min/total/latest` →
  `local{accepted,strong_signals,signal,noise,…}`, `cpr`, `cpu`, `tracks`). Drives Signal / Engine
  Room / Wrench.
- **`PiVitalsDto`** — `/pi-vitals.json` system telemetry (temp, load, mem, disk, sdr, services,
  per-band 1090/978 mps). Drives Engine Room / Wrench / Diagnostics hardware health.
- **`Rolling24hResponseDto`** — `/pi-rolling-24h.json` (`todayCentral`/`today`/`rolling24h`/`recent[]`/
  `militaryHistory[]`). Canonical aircraft count = `todayCentral`.
- **`OutlineDto`** → `CoverageOutline` (24 h coverage polygon, projected to bearing/range).
- **`PromMetrics`** — `/data/stats.prom` Prometheus exposition parsed for RSSI quartiles + feed
  connector status.

### Endpoints (all under `http://192.168.1.207:8088/`)
| Path | Drives |
|---|---|
| `/enrich/aircraft.json` (fallback `/skyaware/data/aircraft.json`) | live aircraft (enriched: reg/type/desc/route/dbFlags) |
| `/skyaware978/data/aircraft.json` | UAT 978 band aircraft (merged, ADS-B wins dupes) |
| `/skyaware/data/receiver.json` | receiver lat/lon, version, refresh |
| `/skyaware/data/stats.json` | readsb decode stats |
| `/data/outline.json` | coverage polygon |
| `/data/stats.prom` | feed connectors + RSSI quartiles |
| `/pi-vitals.json` | Pi hardware telemetry |
| `/pi-rolling-24h.json` | rolling 24 h counters + military history |

No WebSocket — HTTP polling only. `ConnectionMode.WEBSOCKET` is a vestigial enum case.

---

## 3. Live data flow

```
TrackingService (foreground)            iOS: foreground-only poll loop + BGProcessingTask
   └─ AircraftRepository.startLiveUpdates(config)
        └─ poll loop @ pollIntervalMs (default 1 s; 3 s when tar1090 WebView is foreground)
             ├─ GET enrich/aircraft.json  (fallback skyaware) + skyaware978
             ├─ merge + dedupe (ADS-B wins over UAT), sort by distance
             ├─ AircraftDto.toDomain():  haversine distance/bearing, Emergency.from(),
             │                            AircraftClassifier.classify(), type/airline/country enrich
             ├─ recordDailyAircraft()  → Room daily_aircraft (30-day retention)
             ├─ fireNotifications()    → emergency / military / custom-rule alerts (dedup sets)
             └─ expose via Flows: observeAircraft / observeLiveStats / observeMilitaryAircraft / …

PiVitalsRepository (telemetry hub, separate cadence)   iOS: a second polling actor
   ├─ /pi-vitals.json   @ 5 s     ├─ /data/stats.json + .prom @ 10 s (atomic pair)
   ├─ /pi-rolling-24h   @ 30 s    ├─ /data/outline.json       @ 30 s
   └─ /data/receiver.json @ 60 s  └─ 180-sample trend ring-buffer (≈30 min) for the Trends screen
```

ViewModels subscribe to repository `Flow`s via `stateIn(WhileSubscribed)`. In Swift this becomes
`@Observable` view models reading `AsyncStream` / `Combine` publishers, started/stopped on
`.onAppear`/`.onDisappear`.

---

## 4. Storage

| Concern | Android | Rows / keys |
|---|---|---|
| Relational | **Room** v6 (destructive migration) | `favorites(hex,addedAt)`, `aircraft_tags(hex,category,note,timestamp)`, `daily_aircraft([date,hex],type,callsign,registration,firstSeenMs,isMilitary)`, `flight_trail([hex,ts_ms],lat,lon,alt_baro,track,ground_speed)` |
| Preferences | **DataStore** | display/map/notification toggles + connection config + onboarded flag (14 + 6 keys) |
| 24h cache | DataStore | 11 keys mirroring `Rolling24hStats` |
| Mil DB | bundled `us_military_aircraft.csv` + OTA cache | `hex → {typeName, operator, registration}` |
| Crash/error | `ErrorLog` ring buffer + file | 200 entries, 256 KB file |

iOS: relational → **SwiftData** (`@Model`, the Room analog), preferences → **UserDefaults** wrapper,
password → **Keychain**, mil CSV bundled in `Resources/`, ErrorLog → `os.Logger` + a file ring buffer.

---

## 5. Screen inventory (22 destinations, one collapsible nav rail)

The nav graph (`AppNavigation.kt`) is a `NavigationRail` (collapsible 32↔88 dp) + `NavHost`.
Start destination: `Atlas` (or `Map` on Fire-TV leanback). Deep link: military notification tap →
`map?hex=…`. iOS: `NavigationSplitView` sidebar + `NavigationStack` per column; deep link via
`UNUserNotificationCenter` response → selected-hex binding.

| Route | Screen | What it shows | Render tech |
|---|---|---|---|
| atlas | **Atlas** (landing) | 8–10 navigation tiles with live mini-stats + sparklines | layout + sparkline Canvas |
| map | **Map** | tar1090 **WebView** (live) · STARS scope · military scope | WebView + Compose Canvas overlays |
| radar | **Radar** | pure-vector PPI scope, equirectangular projection, pinch/pan, trails | Compose Canvas |
| aircraft | **Aircraft** | searchable/sortable live list + detail sheet | LazyColumn + ModalBottomSheet |
| pfd/{hex} | **PFD** | Boeing-style primary flight display (attitude/tape/HSI/VSI) | Compose Canvas ×6 |
| signal | **Signal** | RF front-end meters, RSSI box-plot, decode/CPR quality | radial meters + box-plot Canvas |
| trends | **Trends** | 7 live time-series + 12-day history bars | TimeSeriesChart Canvas |
| coverage | **Coverage** | polar coverage rose + range-by-bearing histogram | PolarRose Canvas |
| integrity | **Integrity** | DO-260B MOPS landscape (NACp/NIC/SIL scatter + histograms) | scatter/bar Canvas |
| network | **Feeds** | aggregator connectors + local services + 24 h volume | layout |
| engineroom | **Engine Room** | dual 1090/978 dashboards, 270° gauges, hardware health | CanvasGauge |
| wrench | **Wrench** | 12 named diagnostic checks (OK/WARN/FAIL/UNKNOWN) | layout |
| stats | **Home** | v6 radar instrument face + hero stat plate | RadarHero Canvas |
| alerts | **Alerts** | active emergency/military + custom rule toggles | layout + sheet |
| favorites | **Favorites** | live-now vs saved favorites | layout |
| military | **Military** | 30-day military history | layout |
| tags | **Tags** | tagged aircraft grouped by category | layout |
| today | **Unique** | unique aircraft since midnight | layout |
| diagnostics | **Diagnostics** | services / resources / SDR / gain / reboot (SSH-hint stubs) | layout |
| settings | **Settings** | connection + display + notification prefs | layout |
| onboarding | **Onboarding** | mDNS auto-discover + manual connect | layout |

---

## 6. Design system — "Hangar Luxe v6"

Dark, single theme (graphite surfaces, brushed-brass + cyan accents, bone text). Exact tokens live
in `DesignSystem/Palette.swift` & `HangarLuxe.swift`. Highlights:

- Surfaces: `Background #0A0B0F`, `CardBackground #14161D`, `CardElevated #1C1F28`.
- Accents: `Brass #C9A961` (= legacy `PlatinumGold`), `Cyan #5BE5FF` (= `ElectricBlue`),
  `BrassBright #E3C682` (= `PiSkyGreen`).
- Text (bone): `#F2EFE6 / #D8D5CC / #9C9A95`.
- Altitude bands (map/list/scope): ground `#4A4E58`, low `#3DDC97`, mid `#5BE5FF`, high `#C9A961`,
  mlat `#B89A55`. (Radar uses tar1090's variant — red→yellow→cyan→magenta→pink.)
- Type: **Rajdhani** (display), **Inter** (body), **JetBrains Mono** (data/callsigns/hex).
- Responsive: `PhoneDimens` vs `TabletDimens` (padding, grid columns, type scale) via a
  `CompositionLocal` → iOS `EnvironmentValues`.

Custom **Canvas** toolkit (the highest-effort port): `TimeSeriesChart`, `MiniTrend`, `BarHistogram`,
`BoxPlotH`, `ScatterPlot`, `RadialMeter`/`RingStat`, `PolarRose`, `CanvasGauge`, `RadarHero`,
`BrandLogo`, plus the 6 PFD instruments. All reimplemented in SwiftUI `Canvas` + `Path`; the
drawing math is documented per-component in [ANDROID_TO_IOS_MAPPING.md §Canvas](ANDROID_TO_IOS_MAPPING.md).

---

## 7. Domain logic that ports verbatim (pure Kotlin → pure Swift)

- **`AircraftClassifier`** — two-layer military classifier (deterministic hex/callsign/type tables +
  heuristic), backed by `MilitaryHexDatabase`, `AircraftTypeNames`, `AirlineDatabase`, `HexCountry`.
- **`AdsbIntegrity` / `AdsbCodes`** — DO-260B MOPS bound tables + emitter/source-type decoders.
- **`RfTelemetry`** — SNR, strong-signal %, bad-frame ratio, RF-health classifier.
- **`MessagesPerSecond`** — reset-resilient MPS accumulator.
- **`Geo`** — haversine NM + bearing.

These are copied faithfully (including the hardcoded military hex/type/airline tables — **never
paraphrased or trimmed**).
