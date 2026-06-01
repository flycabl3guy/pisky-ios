# iOS build contract (read before writing any Data-layer or Feature code)

This pins the conventions every implementation agent must follow so the parallel work compiles
together. Target **iOS 17**, Swift 5.10, SwiftUI + Observation + Combine. No third-party deps.

## 1. AppContainer — the DI surface (referenced by the app shell and every screen)

`AppContainer` is `@MainActor @Observable final class` (the Data-layer agent writes it).
It MUST expose exactly this surface:

```swift
@MainActor @Observable final class AppContainer {
    let aircraftRepository: AircraftRepository      // protocol (Domain/Repositories/Repositories.swift)
    let connectionRepository: ConnectionRepository  // protocol
    let tagRepository: TagRepository                // protocol
    let statsRepository: StatsRepository            // protocol (Domain/Repositories/StatsRepository.swift)
    let piVitals: PiVitalsRepository                // CONCRETE telemetry hub (Data layer)
    let preferences: AppPreferences                 // CONCRETE (UserDefaults wrapper)
    let aircraftTypes: AircraftTypeRepository       // CONCRETE (bundled mil CSV + OTA)
    let notifications: NotificationManager          // CONCRETE
    let mdns: MdnsDiscovery                          // CONCRETE (NWBrowser)

    var pendingMapHex: String?                      // deep-link target (notification tap → Map). Mutable.

    init()
    func bootstrap() async                          // request notif auth; load config; start live updates + piVitals polling
    func handleScenePhase(_ phase: ScenePhase)      // .active → resume poll loop; .background → stop (see PORTING_NOTES §1)
}
```

Screens read it via `@Environment(AppContainer.self) private var container`.

## 2. View-model convention (ALL view models follow this exactly)

```swift
import SwiftUI
import Combine

@MainActor @Observable
final class FooViewModel {
    // Observable state = plain stored properties (the @Observable macro tracks them).
    private(set) var items: [Aircraft] = []
    var query: String = ""                       // two-way-bound props are non-private

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private weak var container: AppContainer?
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }            // idempotent — called from .task on every appear
        started = true; container = c
        c.aircraftRepository.observeAircraft()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.items = $0 }
            .store(in: &bag)
    }

    // Intents fire async work via Task:
    func toggleFavorite(_ hex: String, isFav: Bool) {
        Task { isFav ? await container?.aircraftRepository.removeFavorite(hex: hex)
                     : await container?.aircraftRepository.addFavorite(hex: hex) }
    }
}
```

Screen view convention:

```swift
struct FooScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var vm = FooViewModel()
    var body: some View {
        @Bindable var vm = vm                     // enables $vm.query bindings for TextField/Toggle
        AtlasScaffold(title: "Foo", live: true) { /* content */ }
            .task { vm.start(container) }
    }
}
```

- Polling/refresh loops in a VM: `Task { while !Task.isCancelled { …; try? await Task.sleep(for: .seconds(n)) } }` started in `start(_:)`; the Task is stored and cancelled in `deinit`.
- Debounce (e.g. 150 ms search): use Combine `.debounce(for: .milliseconds(150), scheduler: RunLoop.main)` on a `CurrentValueSubject`, or `.onChange` + a debounce Task.
- Screens that consume telemetry use `container.piVitals` publishers (vitals/stats/prom/feeds/rolling/coverage/receiver/trend, all `AnyPublisher<…, Never>`).

## 3. Design system available (DesignSystem/)

- Colors: `Palette.background/.cardBackground/.cardElevated/.brass/.brassBright/.cyan/.cyanDim/.textPrimary/.textSecondary/.textMuted/.statusOk/.statusWarn/.statusError/.altGround/.altLow/.altMid/.altHigh/.altMlat`, plus `Palette.altitudeBand(altFt:onGround:isMlat:emergency:)`, `Palette.radarAltitude(_:)`, `qualityColor(_:)`. `Color(hex:alpha:)`.
- Type: `PSText.displayLarge/headlineMedium/titleMedium/bodyMedium/labelLarge/labelMedium/labelSmall` (apply `.tracking(PSText.Tracking.label)` where the Kotlin set letter-spacing). `Font.psMono(_:weight:)`, `.rajdhani`, `.inter`.
- Tokens: `HangarLuxe.Radius/.Elevation/.Motion/.Glass/.Sweep`.
- Dimensions: `@Environment(\.dimens) var dimens` → `dimens.screenPadding/.cardPadding/.statsColumns/...`.

## 4. Component toolkit available (DesignSystem/Components/)

- `HangarPlate { content }` (+ `.hangarPlate()` modifier) — glass card.
- `AtlasScaffold(title:subtitle:accent:live:actions:content:)` — page shell (scrolling).
- `SectionLabel(_:accent:trailing:)`, `BigStat(value:label:unit:valueColor:accent:)`, `StatPlate(label:value:sub:accent:valueColor:)`, `MetricRow(label:value:valueColor:sub:)`, `LinearMeter(fraction:label:valueText:color:height:)`, `SegmentBar(segments:[Segment]…)` (`Segment(value:color:label:)`), `LiveDot(size:color:)`, `AtlasChip(text:color:)`.
- Charts: `TimeSeriesChart(values:[Float], label:unit:color:height:valueFormat:invertY:)`, `MiniTrend(values:[Float], color:height:)`, `BarHistogram(bars:[HistoBar], …)` (`HistoBar(label:value:color:)`), `BoxPlotH(min:q1:median:q3:max:avg:axisMin:axisMax:unit:color:)`, `ScatterPlot(points:[ScatterPoint], xMax:yMax:xLabel:yLabel:height:grid:)` (`ScatterPoint(x:y:color:radius:)`).
- Meters: `RadialMeter(value:min:max:label:unit:diameter:color:valueText:)`, `RingStat(fraction:centerText:label:diameter:color:)`.
- `PolarRose(points:[RosePoint], ringLabels:[String], accent:liveDots:)` (`RosePoint(bearingDeg:rangeFraction:color:)`).
- `PremiumButton(action:text:variant:icon:enabled:…)` (`PremiumButtonVariant.primary/.secondary/.ghost/.danger`, `icon` is an SF Symbol name), `PremiumIconButton(action:icon:…)`.
- `BrandLogo(size:animate:)`, `BetaBadge(color:label:)`, `HangarHaptics.tap()/.toggle()/.select()/.reject()/.tick()`.
- EngineRoom's 270° gauge: reuse `RadialMeter` (same geometry) or the dedicated gauge if one is added.

## 5. Screen + view-model names (the app shell calls these — match EXACTLY)

| View (initializer) | View model |
|---|---|
| `AtlasScreen(onNavigate: (String) -> Void)` | `AtlasViewModel` |
| `MapScreen(initialSelectHex: String?)` | `MapViewModel` |
| `RadarScreen()` | `RadarViewModel` |
| `AircraftScreen(onAircraftSelected: (String) -> Void)` | `AircraftViewModel` |
| `PfdScreen(hex: String)` | `PfdViewModel` |
| `SignalScreen()` | `SignalViewModel` |
| `TrendsScreen()` | `TrendsViewModel` |
| `CoverageScreen()` | `CoverageViewModel` |
| `IntegrityScreen()` | `IntegrityViewModel` |
| `NetworkScreen()` | `NetworkViewModel` |
| `EngineRoomScreen()` | `EngineRoomViewModel` |
| `WrenchScreen()` | `WrenchViewModel` |
| `HomeScreen(onNavigateToSettings: () -> Void)` | `HomeViewModel` |
| `AlertsScreen()` | `AlertsViewModel` |
| `FavoritesScreen()` | `FavoritesViewModel` |
| `MilitaryScreen()` | `MilitaryViewModel` |
| `TagsScreen()` | `TagsViewModel` |
| `UniqueAircraftScreen()` | `UniqueAircraftViewModel` |
| `DiagnosticsScreen()` | `DiagnosticsViewModel` |
| `SettingsScreen()` | `SettingsViewModel` |
| `OnboardingScreen(onConnected: () -> Void)` | `ConnectionViewModel` |

Shared sub-views (define once, in the Aircraft feature): `AircraftDetailSheet`, `EmergencyBanner`,
`AltitudeSparkline`. Other features reuse `AircraftDetailSheet` via the same module.

## 6. Domain + Network references

- Domain models: `Aircraft` (note `operatorName`, not `operator`; `.isMilitary/.isInteresting/.isPia/.isLadd/.hasPosition/.displayCallsign/.typeDescription/.altitudeDisplay/.speedDisplay/.verticalRateDisplay/.routeDisplay`), `Emergency`, `LiveStats`, `ReceiverStats`, `Rolling24hStats`, `UniqueAircraft`, `DailyCount`, `MilitaryHistoryEntry`, `AircraftTag`, `TagCategory`, `ConnectionConfig`, `ConnectionMode`, `CoverageOutline`, `FeedConnector`, `TrendSample`, `AircraftClassification`/`ClassificationLevel`.
- Logic: `AdsbIntegrity.nacp/nic/sil/nacv/sda/gva/nicBaro/versionName/versionShort`, `AdsbCodes.emitterCategory/sourceType`, `RfTelemetry.snrDb/strongSignalPct/classify` (`RfHealth`), `AircraftClassifier.classify(…)`, `AircraftTypeNames.decode(_:)`, `Geo.haversineNm/bearingDeg`, `Fmt.grouped/compact/uptime`, `Double.radians/.degrees`.
- Network DTOs consumed by telemetry screens (read the files in `PiSky/Network/DTOs/` for exact field names): `PiVitalsDto` (temp/load/mem/disk/sdr/services/bands), `StatsDto` (+`StatsPeriodDto`/`LocalStatsDto`/`CprDto`), `PromMetrics`, `Rolling24hResponseDto` (`.preferred`), `PiStatusDto` (Diagnostics, via `PiStatusSynthesizer.synthesize(vitals:stats:)`), `ChainStatusDto` (via `ChainStatusSynthesizer`).

## 7. Rules

- Port the Kotlin screen's layout, sections, sort/filter logic, and polling cadence faithfully.
- Use `Canvas`/`Path` for all custom drawing (radar/PFD/gauges/charts already exist in the toolkit;
  PFD instruments are NEW and the PFD agent builds them).
- No `print`; use `os.Logger` if logging is needed.
- Every file compiles against the contracts above — do not invent new container properties, repo
  methods, or component names. If something's missing, add a small local helper rather than a new
  global API.
