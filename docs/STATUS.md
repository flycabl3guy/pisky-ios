# PiSky iOS — port status & handoff

**State: code-complete across every layer; not yet compiled.** The whole Android app (19 Kotlin
modules, ~29 K LOC) has been ported to a native SwiftUI iOS project — **110 Swift files, ~17.1 K
lines**. It has NOT been through a Swift compiler (this was authored on Windows; iOS builds require
Xcode/macOS). Expect a **compile-fix iteration pass on the Mac** — see §3.

## 1. What's in the project

| Layer | Files | Status |
|---|---|---|
| **Docs** | `docs/` ×5 | Architecture report, Android→iOS mapping, porting notes, build contract, this file |
| **Scaffold** | `project.yml`, `Info.plist`, `README`, `.gitignore` | XcodeGen spec; ATS/local-network/BGTask configured |
| **DesignSystem** | 12 files | Hangar Luxe palette/type/dimens/tokens + Canvas toolkit (HangarPlate, AtlasHud, charts, meters, PolarRose, PremiumButton, BrandLogo, haptics) |
| **Domain** | 21 files | Models (verbatim field-for-field), enums, **classifier + data tables verified entry-by-entry** (78 type names, 160 airlines, 292 mil-DB entries, 63 country ranges), RF telemetry, DO-260B integrity decoders, repo protocols |
| **Network** | 15 files | Codable DTOs (every `@SerialName` key preserved), `actor APIClient` (URLSession), DTO→domain mappers, Prometheus parser, status/chain synthesizers |
| **Data** | 16 files | SwiftData persistence, UserDefaults prefs + **Keychain** for the password, repository implementations (polling, dedupe, daily logging, notifications), `PiVitalsRepository` telemetry hub, mil-CSV repo, `UNUserNotificationCenter` manager, `NWBrowser` mDNS, ErrorLog, **AppContainer** wiring |
| **App shell** | 4 files | `PiSkyApp`, `AppContainer`, `RootView`, `AppNavigation` (NavigationSplitView sidebar; deep-link to map) |
| **Features** | 42 files | **All 22 screens** + view models: Atlas, Map (WKWebView + Canvas scope), Radar, Aircraft (+detail sheet), PFD (6 instruments), Signal, Trends, Coverage, Integrity, Feeds, Engine Room, Wrench, Home, Alerts, Favorites, Military, Tags, Unique, Diagnostics, Settings, Onboarding |

## 2. Faithfulness

- Domain logic + all hardcoded tables ported **verbatim** (no trimming) and diff-verified against
  the Kotlin by the porting agent.
- Every DTO JSON key, default, and the lenient-decode behavior preserved.
- Canvas drawing math (radar projection, PFD attitude/tapes/HSI/VSI, gauges, polar rose, charts)
  reproduced from the Kotlin formulas.
- The deliberate Android decisions are kept: `trustedDbFlags = nil` (ignore unreliable enrich
  dbFlags), distance via `r_dst`/`r_dir` with haversine fallback, ADS-B-wins dedupe, COWDEN
  fallback coords, the 12 Wrench checks, the Diagnostics SSH-hint stubs.

## 3. Before the first Mac build (required)

1. `brew install xcodegen`
2. Drop the three font families into `PiSky/Resources/Fonts/` (Rajdhani, Inter, JetBrains Mono) and
   list them under `UIAppFonts` — OR accept the system-font fallback (the type helpers degrade
   gracefully).
3. Copy `us_military_aircraft.csv` from the Android `core/data/assets/` (or wherever the asset lives)
   into `PiSky/Resources/` — `AircraftTypeRepository` loads it from the bundle (degrades to empty
   if absent, so the app still runs; military enrichment is just thinner).
4. `xcodegen generate && open PiSky.xcodeproj`
5. Set **DEVELOPMENT_TEAM** (Signing & Capabilities) and add the **Background Modes** capability
   (Background fetch + processing). Local Network is driven by the Info.plist keys.
6. **Build and fix.** A 110-file project written without a compiler will have residual issues —
   mostly minor API/signature mismatches across the independently-authored layers. Work the compiler
   errors top-down; the type contracts are consistent by design (one `AppContainer` surface, one VM
   convention, shared component signatures), so fixes should be local.

## 4. Seams already reconciled

- `MdnsDiscovery.discover()` → `AnyPublisher<DiscoveryResult, Never>` (was `AsyncStream<String>`) to
  match both Settings consumers.
- `AlertsViewModel` rule toggles → backing-store + `setRuleX(_:)` + publisher sync (was treating the
  read-only publishers as mutable properties).
- `SettingsViewModel` `Float`↔`Double` mismatches on `logDepth`/`trailLength` (publishers + setters).

## 5. Known limitations / deliberate stubs (documented, not bugs)

- **Background real-time alerts** are not guaranteed when the app is backgrounded — iOS has no
  foreground-service equivalent. Foreground = full 1 Hz polling; background = best-effort
  `BGAppRefreshTask` + the hourly `BGProcessingTask`. (PORTING_NOTES §1.)
- **Map**: WKWebView (tar1090, 1:1) is the primary backend + an in-app Canvas **Scope** mode. The
  retired native MapLibre vector basemap is **not** ported (MapLibre-iOS or MapKit is the documented
  future option). (PORTING_NOTES §2.)
- **Fire-TV / leanback / TV-remote** mode dropped (no tvOS target). (PORTING_NOTES §3.)
- **Home** screen implements the headline state the v6 layout renders; long-tail derivations
  (airlineCounts/hourlyData/countriesToday/liveExtremes/…) are a marked `TODO(port)` block.
- **Diagnostics** restart/gain/reboot surface SSH-hint strings (no control endpoint — same as
  Android).
- **Behavior to verify:** `AircraftScreen` row-tap currently both pushes the PFD (via the nav
  callback) and presents the detail sheet — pick one on the Mac (the Android list-tap went to PFD;
  the detail sheet is the natural long-press / secondary action).

## 6. Layout

See `README.md`. Source mirrors the Android module layering as folder groups in one app target.
