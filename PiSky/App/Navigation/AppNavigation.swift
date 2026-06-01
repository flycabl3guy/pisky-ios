import SwiftUI

/// The main shell. Android used a collapsible `NavigationRail` + `NavHost`; on iOS this is a
/// `NavigationSplitView` (sidebar adapts to a slide-over menu on compact iPhones). Each destination
/// gets its own `NavigationStack` so per-section pushes (Aircraft → PFD) work. The deep-link
/// (military-notification tap → map+hex) is driven by `container.pendingMapHex`.
struct AppNavigation: View {
    @Environment(AppContainer.self) private var container

    @State private var selection: Destination? = .atlas
    @State private var aircraftPath = NavigationPath()
    @State private var mapHex: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Surveillance") {
                    row(.atlas); row(.map); row(.radar); row(.aircraft); row(.stats)
                }
                Section("Signal & Health") {
                    row(.signal); row(.trends); row(.coverage); row(.integrity)
                    row(.feeds); row(.engine); row(.wrench)
                }
                Section("Watch") {
                    row(.alerts); row(.favorites); row(.military); row(.tags)
                }
                Section("System") {
                    row(.diagnostics); row(.settings)
                }
            }
            .navigationTitle("PiSky")
            .listStyle(.sidebar)
            .tint(Palette.brass)
        } detail: {
            detailView(for: selection ?? .atlas)
        }
        .onChange(of: container.pendingMapHex) { _, hex in
            if let hex {
                mapHex = hex
                selection = .map
                container.pendingMapHex = nil
            }
        }
    }

    private func row(_ d: Destination) -> some View {
        Label(d.title, systemImage: d.symbol).tag(d)
    }

    @ViewBuilder
    private func detailView(for d: Destination) -> some View {
        switch d {
        case .atlas:
            NavigationStack { AtlasScreen(onNavigate: { route in selectByRoute(route) }) }
        case .map:
            NavigationStack { MapScreen(initialSelectHex: mapHex) }
        case .radar:
            NavigationStack { RadarScreen() }
        case .aircraft:
            NavigationStack(path: $aircraftPath) {
                AircraftScreen(onAircraftSelected: { hex in aircraftPath.append(hex) })
                    .navigationDestination(for: String.self) { hex in PfdScreen(hex: hex) }
            }
        case .signal:      NavigationStack { SignalScreen() }
        case .trends:      NavigationStack { TrendsScreen() }
        case .coverage:    NavigationStack { CoverageScreen() }
        case .integrity:   NavigationStack { IntegrityScreen() }
        case .feeds:       NavigationStack { NetworkScreen() }
        case .engine:      NavigationStack { EngineRoomScreen() }
        case .wrench:      NavigationStack { WrenchScreen() }
        case .stats:       NavigationStack { HomeScreen(onNavigateToSettings: { selection = .settings }) }
        case .alerts:      NavigationStack { AlertsScreen() }
        case .favorites:   NavigationStack { FavoritesScreen() }
        case .military:    NavigationStack { MilitaryScreen() }
        case .tags:        NavigationStack { TagsScreen() }
        case .diagnostics: NavigationStack { DiagnosticsScreen() }
        case .settings:    NavigationStack { SettingsScreen() }
        }
    }

    /// Atlas tiles call back with the same route strings the Android `AtlasScreen.onNavigate` used.
    private func selectByRoute(_ route: String) {
        switch route {
        case "map":        selection = .map
        case "radar":      selection = .radar
        case "aircraft":   selection = .aircraft
        case "signal":     selection = .signal
        case "trends":     selection = .trends
        case "coverage":   selection = .coverage
        case "integrity":  selection = .integrity
        case "network":    selection = .feeds
        case "engineroom": selection = .engine
        case "wrench":     selection = .wrench
        case "stats":      selection = .stats
        default: break
        }
    }
}

/// Nav destinations — the iOS analog of `navTabs` in AppNavigation.kt, with SF Symbols for the
/// Material icons. (`Unique`/`PFD`/`Onboarding` are reached contextually, not from the sidebar.)
enum Destination: Hashable, Identifiable {
    case atlas, map, radar, aircraft, signal, trends, coverage, integrity,
         feeds, engine, wrench, stats, alerts, favorites, military, tags,
         diagnostics, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .atlas: "Atlas";        case .map: "Map";          case .radar: "Radar"
        case .aircraft: "Aircraft";  case .signal: "Signal";    case .trends: "Trends"
        case .coverage: "Coverage";  case .integrity: "Integrity"; case .feeds: "Feeds"
        case .engine: "Engine";      case .wrench: "Wrench";     case .stats: "Stats"
        case .alerts: "Alerts";      case .favorites: "Favorites"; case .military: "Military"
        case .tags: "Tags";          case .diagnostics: "Diagnostics"; case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .atlas: "square.grid.2x2.fill"
        case .map: "map.fill"
        case .radar: "scope"
        case .aircraft: "airplane"
        case .signal: "waveform"
        case .trends: "chart.line.uptrend.xyaxis"
        case .coverage: "globe.americas.fill"
        case .integrity: "checkmark.seal.fill"
        case .feeds: "point.3.connected.trianglepath.dotted"
        case .engine: "speedometer"
        case .wrench: "wrench.and.screwdriver.fill"
        case .stats: "chart.bar.fill"
        case .alerts: "bell.badge.fill"
        case .favorites: "heart.fill"
        case .military: "shield.lefthalf.filled"
        case .tags: "tag.fill"
        case .diagnostics: "cross.case.fill"
        case .settings: "gearshape.fill"
        }
    }
}
