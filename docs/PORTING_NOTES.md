# Porting notes — features that can't port 1:1, and their iOS alternatives

Per the port brief: *"Explain any feature that cannot be directly ported and provide an iOS
alternative."* The brief's hard rules are kept where physics/JSON allow; where an Android capability
has no iOS equivalent, the substitute is documented here.

---

## 1. Background tracking — the biggest behavioral difference

**Android:** `TrackingService` is a *foreground service* (`START_STICKY`, persistent notification)
that polls the receiver at 1 Hz **forever**, even with the screen off / app backgrounded, firing
emergency/military alerts in real time.

**iOS reality:** there is no equivalent. A foreground app may poll freely, but once backgrounded iOS
suspends it within seconds. There is no API for indefinite 1 Hz network polling in the background.

**iOS alternative (implemented):**
- **Foreground:** identical 1 Hz live poll loop while the app is active (`scenePhase == .active`).
- **Background refresh:** `BGAppRefreshTask` (best-effort, OS-scheduled, typically minutes apart) +
  `BGProcessingTask` (`com.pisky.mobile.hourlytally`) for the hourly tally summary — the analog of
  `HourlyTallyWorker`. These cannot guarantee 1 Hz; they do one fetch + post catch-up notifications.
- **Real-time alerts off-screen** (emergency/military squawks) are therefore **not guaranteed** when
  backgrounded. Documented as a platform limitation. A future option is a small server-side push
  (the Pi already runs scripts) → APNs, but that needs an APNs key and a push relay and is out of
  scope for a LAN-only sideload.

---

## 2. Maps — three Android backends, two of them retired/native

**Android source has three map paths:** OSMdroid raster (retired), MapLibre Native vector (retired,
dead code kept for rollback), and the **tar1090 `WebView`** (the live default). Plus two pure-Compose
"scope" overlays (STARS-style + military).

**Port decision:**
- **tar1090 WebView → `WKWebView`** — ports **1:1** and is the primary Map. Same browser engine,
  same URL (`http://192.168.1.207:8088/`), same JS bridge (`@JavascriptInterface` →
  `WKScriptMessageHandler`), same injected overlay (range rings + airport markers via `WKUserScript`),
  same localStorage seeding. This is the recommended, highest-fidelity path.
- **MapLibre Native vector basemap → not ported initially.** It is dead code in the Android source.
  If a native vector map is wanted later, **MapLibre-iOS** is the drop-in (same style JSON + layer
  API + per-feature color expressions); **MapKit** is the zero-dependency alternative but loses the
  CartoDB Dark Matter styling and needs per-aircraft `MKAnnotation`s (heavier at 500+ targets).
- **OSMdroid raster → dropped** (already retired on Android).
- **Compose scope overlays → SwiftUI `Canvas`** — the STARS/PPI scope ports faithfully (projection
  math in ANDROID_TO_IOS_MAPPING.md). On iOS this is delivered as the standalone **Radar** screen
  (`feature:radar`), which is already a pure-vector scope and the cleanest Canvas port.

Net: Map = WebView (live) + Radar (native Canvas scope). The retired native vector basemap is left
as a documented future option, not built.

---

## 3. Fire-TV / Android-TV (leanback) mode

**Android:** detects `FEATURE_LEANBACK`, auto-onboards, hides the nav rail, lands on a full-screen
scope, and binds the TV remote FF/REW/channel keys to map zoom (`RemoteInputBus`).

**iOS:** no tvOS target in scope; iPhone/iPad have no D-pad. **Dropped.** `RemoteInputBus` and the
leanback branch are not ported. (If an Apple-TV build is ever wanted it's a separate target; the
domain/network/data layers would be reused unchanged.)

---

## 4. mDNS auto-discovery

**Android:** `NsdManager` resolving `_http._tcp` for piaware/readsb/tar1090/flightaware names.

**iOS:** **`NWBrowser`** (Network framework) browsing `_http._tcp`, gated behind the
`NSLocalNetworkUsageDescription` permission + `NSBonjourServices` declaration (both already in
`Info.plist`). Functionally equivalent; first run shows the local-network permission prompt.

---

## 5. Diagnostics control actions (restart/gain/reboot)

**Android:** these are already **stubs** — PiAware-native has no control endpoint, so the buttons
surface an SSH hint string. **Ported as-is** (same SSH-hint behavior). No iOS-specific loss.

---

## 6. Notifications

**Android:** three channels (emergency/military/rules, HIGH/HIGH/DEFAULT) + an hourly-tally channel;
military uses a full-screen intent to wake the device.

**iOS (UNUserNotificationCenter):**
- Channels → **categories + thread identifiers**; importance → **interruption levels**
  (`.timeSensitive` for emergency/military, `.active` for rules, `.passive` for the hourly tally).
- Full-screen intent has no iOS analog; `.timeSensitive` + a critical-sounding alert is the closest
  (true `.critical` alerts need a special entitlement Apple grants case-by-case — not pursued for a
  sideload).
- Dedup sets (`notifiedMilitaryHexes`, `notifiedRuleKeys`) port unchanged.

---

## 7. Storage specifics

- **Room composite primary keys** (`daily_aircraft[date,hex]`, `flight_trail[hex,ts_ms]`) → SwiftData
  has no composite `@Attribute(.unique)`; modeled as a single derived unique id (`"\(date)|\(hex)"`)
  plus the component fields, with upsert-by-id. Same query semantics.
- **Destructive migration** (Room `fallbackToDestructiveMigration`) → SwiftData lightweight migration;
  if the schema is incompatible the store is reset (same "data is disposable cache" posture).
- **DataStore → UserDefaults**, but the **connection password moves to Keychain** (it was plaintext
  in DataStore on Android — this is a deliberate security upgrade, not a regression).

---

## 8. Minor / cosmetic

- **Variable fonts** (Rajdhani/Inter/JetBrains Mono) — bundle the `.ttf`s in `Resources/Fonts` and
  register via `UIAppFonts`; SwiftUI `Font.custom`. (Font files are not copied from the Android repo
  automatically — drop them in before the first build; the design system falls back to system
  monospaced/rounded if a family is missing.)
- **`material-icons-extended`** → **SF Symbols** (mapped per nav tab in `AppNavigation.swift`).
- **Edge-to-edge / splash** → SwiftUI `.ignoresSafeArea` + `UILaunchScreen` (Info.plist).
- **`%,d` / locale formatting** → `FormatStyle`; locale assumed `en_US` to match the source.

---

## What you must do on a Mac before first build

1. `brew install xcodegen`
2. Drop the three font families into `PiSky/Resources/Fonts/` (or accept system-font fallback).
3. Copy `us_military_aircraft.csv` from the Android `core/data/assets/` into `PiSky/Resources/`
   (the build references it; see Data layer).
4. `xcodegen generate && open PiSky.xcodeproj`
5. Set your **DEVELOPMENT_TEAM** (Signing & Capabilities) — required to install on the 11 Pro Max.
6. Add capabilities: **Background Modes** (Background fetch + Background processing) and
   **Push** is *not* required (no APNs). Local Network is driven by the Info.plist keys.
7. Build & run on the device (free 7-day provisioning works for personal install; a paid account
   removes the weekly re-sign).
