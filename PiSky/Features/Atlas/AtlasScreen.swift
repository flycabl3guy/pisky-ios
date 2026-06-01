import SwiftUI
import Combine

/// Data Atlas hub — a live index of every data category the receiver exposes.
/// Ported from `feature/atlas` (AtlasScreen.kt + AtlasViewModel.kt). Tiles call
/// `onNavigate(route)` with the route strings the app shell maps to destinations.
@MainActor @Observable
final class AtlasViewModel {
    private(set) var aircraftCount = 0
    private(set) var withPosCount = 0
    private(set) var v2pct = 0
    private(set) var vitals: PiVitalsDto?
    private(set) var stats: StatsDto?
    private(set) var rolling: Rolling24hResponseDto?
    private(set) var coverage: CoverageOutline?
    private(set) var feeds: [FeedConnector] = []
    private(set) var trend: [TrendSample] = []

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private weak var container: AppContainer?
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true; container = c

        c.aircraftRepository.observeAircraft()
            .receive(on: RunLoop.main)
            .sink { [weak self] list in
                guard let self else { return }
                self.aircraftCount = list.count
                self.withPosCount = list.filter { $0.hasPosition }.count
                self.v2pct = list.isEmpty ? 0 : list.filter { $0.version == 2 }.count * 100 / list.count
            }
            .store(in: &bag)

        c.piVitals.vitals.receive(on: RunLoop.main).sink { [weak self] in self?.vitals = $0 }.store(in: &bag)
        c.piVitals.stats.receive(on: RunLoop.main).sink { [weak self] in self?.stats = $0 }.store(in: &bag)
        c.piVitals.rolling.receive(on: RunLoop.main).sink { [weak self] in self?.rolling = $0 }.store(in: &bag)
        c.piVitals.coverage.receive(on: RunLoop.main).sink { [weak self] in self?.coverage = $0 }.store(in: &bag)
        c.piVitals.feeds.receive(on: RunLoop.main).sink { [weak self] in self?.feeds = $0 }.store(in: &bag)
        c.piVitals.trend.receive(on: RunLoop.main).sink { [weak self] in self?.trend = $0 }.store(in: &bag)
    }
}

private struct AtlasTileModel: Identifiable {
    let id = UUID()
    let title: String
    let route: String
    let accent: Color
    let icon: String          // SF Symbol
    let value: String
    let sub: String
    let trend: [Float]?
}

struct AtlasScreen: View {
    let onNavigate: (String) -> Void
    @Environment(AppContainer.self) private var container
    @State private var vm = AtlasViewModel()

    private func seriesOf(_ sel: (TrendSample) -> Double?) -> [Float] {
        vm.trend.compactMap { sel($0).map { Float($0) } }
    }

    var body: some View {
        let local = vm.stats?.last1min?.local
        let snr = RfTelemetry.snrDb(signalDbfs: local?.signal, noiseDbfs: local?.noise)
        let mps = vm.vitals?.bands?.band1090?.mps
        let maxRange = vm.coverage?.maxRangeNm ?? vm.stats?.total?.maxDistanceNm ?? 0.0
        let feedsUp = vm.feeds.filter { $0.isUp }.count
        let temp = vm.vitals?.temp?.celsius
        let today = vm.rolling?.preferred.aircraftSeen ?? 0

        AtlasScaffold(
            title: "Data Atlas",
            subtitle: "\(vm.aircraftCount) aircraft live · every data category, one tap away",
            accent: Palette.brass,
            live: vm.aircraftCount > 0 || vm.stats != nil
        ) {
            SectionLabel(text: "Live Surveillance", accent: Palette.brass)
            tileRow(
                AtlasTileModel(title: "Live Map", route: "map", accent: Palette.cyan, icon: "map.fill",
                               value: "\(vm.withPosCount) with pos", sub: "\(vm.aircraftCount) tracked", trend: nil),
                AtlasTileModel(title: "Radar Scope", route: "radar", accent: Palette.statusOk, icon: "scope",
                               value: "\(vm.aircraftCount) contacts", sub: "polar PPI", trend: nil)
            )
            tileRow(
                AtlasTileModel(title: "Aircraft", route: "aircraft", accent: Palette.altHigh, icon: "airplane.departure",
                               value: "\(vm.aircraftCount) in view", sub: "list + detail", trend: nil),
                AtlasTileModel(title: "Coverage", route: "coverage", accent: Palette.brass, icon: "globe.americas.fill",
                               value: maxRange > 0 ? "\(Int(maxRange)) NM" : "—", sub: "actual outline", trend: nil)
            )

            Spacer().frame(height: 8)
            SectionLabel(text: "Signal & Health", accent: Palette.cyan)
            tileRow(
                AtlasTileModel(title: "Signal Lab", route: "signal", accent: Palette.cyan, icon: "waveform",
                               value: snr.map { String(format: "%.0f dB SNR", $0) } ?? "—",
                               sub: "RF + decode", trend: seriesOf { $0.snrDb }),
                AtlasTileModel(title: "Trends", route: "trends", accent: Palette.statusOk, icon: "chart.line.uptrend.xyaxis",
                               value: mps.map { String(format: "%.0f msg/s", $0) } ?? "—",
                               sub: "live time-series", trend: seriesOf { $0.messagesPerSec })
            )
            tileRow(
                AtlasTileModel(title: "Engine Room", route: "engineroom", accent: Palette.signalAmberHot, icon: "speedometer",
                               value: temp.map { "\(Int($0))°C" } ?? "—",
                               sub: "host + bands", trend: seriesOf { $0.cpuTempC }),
                AtlasTileModel(title: "Feeds", route: "network", accent: Palette.cyan, icon: "point.3.connected.trianglepath.dotted",
                               value: "\(feedsUp)/\(vm.feeds.count) up", sub: "aggregators", trend: nil)
            )

            Spacer().frame(height: 8)
            SectionLabel(text: "Quality & History", accent: Palette.statusOk)
            tileRow(
                AtlasTileModel(title: "Integrity", route: "integrity", accent: Palette.statusOk, icon: "checkmark.seal.fill",
                               value: "\(vm.v2pct)% DO-260B", sub: "MOPS landscape", trend: nil),
                AtlasTileModel(title: "24 h Stats", route: "stats", accent: Palette.brass, icon: "chart.bar.fill",
                               value: Fmt.grouped(today), sub: "today + records", trend: nil)
            )
        }
        .task { vm.start(container) }
    }

    private func tileRow(_ a: AtlasTileModel, _ b: AtlasTileModel) -> some View {
        HStack(spacing: 10) {
            tile(a)
            tile(b)
        }
        .padding(.bottom, 10)
    }

    private func tile(_ t: AtlasTileModel) -> some View {
        Button {
            HangarHaptics.tap()
            onNavigate(t.route)
        } label: {
            HangarPlate(tint: t.accent.opacity(0.4), contentPadding: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 7) {
                        Image(systemName: t.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(t.accent)
                        Text(t.title)
                            .font(.inter(13, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    Spacer().frame(height: 6)
                    Text(t.value)
                        .font(.psMono(21, weight: .bold))
                        .foregroundStyle(t.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(t.sub)
                        .font(.inter(10))
                        .foregroundStyle(Palette.textMuted)
                    if let tr = t.trend, tr.count >= 2 {
                        Spacer().frame(height: 4)
                        MiniTrend(values: tr, color: t.accent, height: 22)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 124)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
