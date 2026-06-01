# Android → iOS component mapping

Every Android/Kotlin/Compose dependency and pattern in PiSky, with the iOS/Swift equivalent the
port uses. Decisions that lose fidelity are flagged and detailed in [PORTING_NOTES.md](PORTING_NOTES.md).

## Platform & language

| Android | iOS port | Notes |
|---|---|---|
| Kotlin 2.1 | Swift 5.10 | |
| `data class` | `struct` | value semantics, `Equatable`/`Hashable` synthesized |
| `sealed class` | `enum` with associated values | e.g. `AltitudeValue` |
| `enum class` (with members) | `enum` (+ computed props) | |
| `Int / Long / Double / Float` | `Int / Int64 / Double / Float` | JSON ints → `Int`; cumulative msg counts → `Int64` |
| nullable `T?` | `Optional<T>` | identical semantics |
| `?:` / `?.` / `let{}` | `??` / `?.` / `if let` / `map{}` | |
| `companion object` | `static` / `enum` namespace | |
| `object Foo` (singleton) | `enum Foo` (static-only) or a `let shared` | |
| coroutines `suspend` | `async`/`await` | |
| `Flow<T>` / `StateFlow<T>` | `AsyncStream<T>` + `@Observable` `@Published`-style props | hot state → observable property; cold stream → `AsyncStream` |
| `MutableStateFlow` | stored property on an `@Observable` class | |
| `viewModelScope.launch` | `Task { }` tied to view lifecycle | cancel on `.onDisappear` |
| `Mutex` | `actor` isolation | repositories become `actor`s |
| `kotlin.math` (`atan2`,`sin`,`hypot`) | `Foundation` (`atan2`,`sin`,`hypot`) | identical |
| `Math.toRadians/Degrees` | `*.pi/180` / `*180/.pi` (helper) | |
| `"%,d".format(n)` | `n.formatted(.number.grouping(.automatic))` | grouped integers |
| `java.time.Instant` | `Date` + `ISO8601DateFormatter` | rolling-24h timestamps are ISO strings |

## Frameworks & libraries

| Android library | iOS equivalent | Fidelity |
|---|---|---|
| Jetpack **Compose** | **SwiftUI** | full |
| Compose **Material3** theme | SwiftUI + custom design system | full (single dark theme) |
| Compose **Canvas** / `DrawScope` | SwiftUI **`Canvas`** + `Path`/`GraphicsContext` | full; math ported line-for-line |
| **Hilt** DI (`@HiltViewModel`, `@Module`) | lightweight **`AppContainer`** injected via `@Environment` | full (manual DI) |
| AndroidX **ViewModel** | `@Observable` class (`ObservableObject` pre-iOS17) | full |
| `collectAsStateWithLifecycle` | `@Observable` + `.task`/`.onReceive` | full |
| Navigation-Compose `NavHost` | `NavigationSplitView` + `NavigationStack` | full (rail → sidebar) |
| **Room** | **SwiftData** (`@Model`, `ModelContainer`, `@Query`) | full; composite keys → unique-constraint + upsert |
| **DataStore** Preferences | **UserDefaults** wrapper (`@AppStorage`-style) | full |
| (password in DataStore, plaintext) | **Keychain** | upgrade — secrets leave UserDefaults |
| **WorkManager** periodic | **BGTaskScheduler** (`BGProcessingTask`) | reduced cadence — see PORTING_NOTES |
| foreground **Service** | foreground `Task` poll loop + `BGAppRefreshTask` | **major gap** — no indefinite background; see PORTING_NOTES |
| **NotificationManager** + channels | **UNUserNotificationCenter** + `UNNotificationCategory` | full; "channels" → categories/threads + interruption levels |
| `PendingIntent` deep link | `UNNotificationResponse` → selected-hex binding | full |
| **Retrofit** + **OkHttp** | **URLSession** + `async` + a thin `APIClient` | full |
| `kotlinx.serialization` (`@SerialName`) | `Codable` (`CodingKeys`) | full; lenient decode via `decodeIfPresent` + defaults |
| retrofit `@Streaming` (stats.prom) | `URLSession.bytes` / `data` + line parse | full |
| **Coil** (image loading) | `AsyncImage` | n/a — PiSky draws everything; no remote images |
| **OSMdroid** (raster tiles) | dropped | replaced by WebView/MapKit — see PORTING_NOTES |
| **MapLibre Native** (vector) | **WKWebView (tar1090)** primary; **MapKit** fallback | dead code in source; see PORTING_NOTES |
| `WebView` + `@JavascriptInterface` | **WKWebView** + `WKScriptMessageHandler` + `WKUserScript` | full — the Map ports cleanly |
| Android **NSD** mDNS | **NWBrowser** (Network framework, `_http._tcp`) | full (+ local-network permission) |
| **Timber** | **`os.Logger`** | full |
| `Build.VERSION.SDK_INT` checks | `if #available(iOS …)` | |
| variable fonts (API 26+) | bundled static/variable `.ttf` in `Resources/Fonts` | full |
| Compose `HapticFeedback` | `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator` | full |
| Fire-TV leanback / D-pad / TV remote | dropped (no tvOS target) | see PORTING_NOTES |

## DI mapping (Hilt → AppContainer)

Hilt `@Singleton` graph → a single `AppContainer` (reference type) built at launch, holding the
`APIClient`, the SwiftData `ModelContainer`, preference stores, the two polling repository actors,
the mil-DB repo, and the notification manager. Injected into the view tree via
`.environment(container)`; view models are created in views with the container passed to their
initializers (replacing `hiltViewModel()`).

## Concurrency mapping

- `AircraftRepository` / `PiVitalsRepository` → **`actor`** types exposing `AsyncStream` for live
  data and `async` methods for one-shots. The poll loops are detached `Task`s with `Task.sleep`.
- Reset-resilient MPS / trend ring buffer → plain value types mutated inside the actor.
- View models are `@MainActor @Observable` classes that subscribe to the streams.

## Canvas drawing reference (drawing math to reproduce)

All custom graphics reimplement in SwiftUI `Canvas`. Coordinate math is preserved exactly:

- **PolarRose / Coverage / Home radar / PPI**: north-up, `angle = (bearing − 90)°`,
  `point = (cx + r·cosθ, cy + r·sinθ)`; range rings dashed; altitude-colored polygon w/ radial
  gradient fill.
- **Radar (feature:radar)**: equirectangular projection centered on receiver —
  `dx = (lon−c.lon)·60·cos(c.lat)/nmPerPx`, `dy = −(lat−c.lat)·60/nmPerPx`; pinch = zoom nm/width
  (20–4000), drag = pan in degrees; trails = 60-sample FIFO with fading alpha; aircraft = heading-
  rotated triangle, altitude-banded.
- **RadialMeter / CanvasGauge**: 270° arc from 135°, `needleθ = 135° + 270°·pct`,
  tip `r·0.92`, base `r·0.18`; glow stroke at 1.7–1.9× width; threshold coloring (supports inverted
  for SNR where low = bad).
- **TimeSeriesChart**: `span=(max−min)·1.12`, `py = h·(1−(v−min)/span)`, `px = w·i/(n−1)`; triple
  stroke (glow/mid/sharp) + gradient area fill + tap crosshair.
- **BoxPlotH**: `fx(v)=((v−axisMin)/span)·w`; whisker min→max, box Q1→Q3 (0.55·h), median line,
  hollow mean circle.
- **PFD AttitudeIndicator**: FPA pitch `atan2(vs/60, gs·1.68781)`; bank = roll or coordinated-turn
  estimate `atan(ω·V/g)` clamped ±67°; rotate sky/ground/ladder by −bank; fixed bank-scale arc.
- **PFD tapes**: altitude 0.5 px/ft (±400 ft window, major/100 minor/20), speed 5 px/kt (±50 kt),
  VSI log scale `y = sign·ln(1+|fpm|/100)/ln(1+6000/100)·h/2`.
- **PFD HSI**: track-up, rose rotated by −track, decade labels counter-rotated upright, magenta
  heading bug, turn-rate triangle (amber > 3.5°/s).
