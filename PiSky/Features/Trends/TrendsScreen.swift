import SwiftUI
import Combine

/// Trends — live telemetry ring buffer + daily aircraft history.
/// Ported from `feature/trends` (TrendsScreen.kt + TrendsViewModel.kt).
@MainActor @Observable
final class TrendsViewModel {
    private(set) var trend: [TrendSample] = []
    private(set) var rolling: Rolling24hResponseDto?

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true
        c.piVitals.trend.receive(on: RunLoop.main).sink { [weak self] in self?.trend = $0 }.store(in: &bag)
        c.piVitals.rolling.receive(on: RunLoop.main).sink { [weak self] in self?.rolling = $0 }.store(in: &bag)
    }

    func series(_ sel: (TrendSample) -> Double?) -> [Float] {
        trend.compactMap { sel($0).map { Float($0) } }
    }
}

private func compactTrends(_ n: Int64) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000.0) }
    if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000.0) }
    return "\(n)"
}

private func dayLabel(_ dateUtc: String) -> String {
    let parts = dateUtc.prefix(10).split(separator: "-")
    if parts.count == 3 {
        let m = Int(parts[1]).map(String.init) ?? String(parts[1])
        let d = Int(parts[2]).map(String.init) ?? String(parts[2])
        return "\(m)/\(d)"
    }
    return String(dateUtc.prefix(5))
}

struct TrendsScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var vm = TrendsViewModel()

    var body: some View {
        AtlasScaffold(
            title: "Trends",
            subtitle: "live \(vm.trend.count) samples · ~30 min window",
            accent: Palette.cyan,
            live: !vm.trend.isEmpty
        ) {
            // ── 24h headline ──
            if let r = vm.rolling?.preferred {
                SectionLabel(text: "Rolling 24 h", accent: Palette.brass)
                HStack(spacing: 8) {
                    StatPlate(label: "Aircraft", value: Fmt.grouped(r.aircraftSeen), accent: Palette.cyan)
                    StatPlate(label: "Messages", value: compactTrends(r.messagesReceived), accent: Palette.brass)
                    StatPlate(label: "Positions", value: compactTrends(r.positionsLogged), accent: Palette.statusOk)
                }
                Spacer().frame(height: 12)
            }

            // ── Live time-series ──
            SectionLabel(text: "Live Telemetry", accent: Palette.cyan, trailing: "\(vm.trend.count) pts")
            if vm.trend.count < 2 {
                HangarPlate(contentPadding: 16) {
                    Text("Accumulating live samples… charts populate within ~20 s.")
                        .font(.inter(13)).foregroundStyle(Palette.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                chartCard("Aircraft tracked", "count", vm.series { $0.aircraftTotal.map(Double.init) }, Palette.cyan)
                chartCard("Messages / sec", "msg/s", vm.series { $0.messagesPerSec }, Palette.brass) { String(Int($0.rounded())) }
                chartCard("Signal level", "dBFS", vm.series { $0.signalDbfs }, Palette.statusOk) { String(format: "%.1f", $0) }
                chartCard("Signal-to-noise", "dB", vm.series { $0.snrDb }, Palette.cyan) { String(format: "%.1f", $0) }
                chartCard("Max range", "NM", vm.series { $0.maxRangeNm }, Palette.brass) { String(format: "%.0f", $0) }
                chartCard("CPU temperature", "°C", vm.series { $0.cpuTempC }, Palette.statusOk) { String(format: "%.1f", $0) }
                chartCard("CPU load (1m)", "load", vm.series { $0.cpuLoad1m }, Palette.cyan) { String(format: "%.2f", $0) }
            }

            // ── Daily history ──
            if let recent = vm.rolling?.recent, !recent.isEmpty {
                Spacer().frame(height: 6)
                SectionLabel(text: "Daily History", accent: Palette.brass, trailing: "unique aircraft / day")
                HangarPlate(contentPadding: 14) {
                    let days = Array(recent.sorted { $0.dateEpoch < $1.dateEpoch }.suffix(12))
                    BarHistogram(
                        bars: days.map { HistoBar(label: dayLabel($0.dateUtc), value: Float($0.aircraftSeen), color: Palette.brass) },
                        valueFormat: { Fmt.grouped(Int($0)) }
                    )
                }
            }
        }
        .task { vm.start(container) }
    }

    @ViewBuilder
    private func chartCard(_ label: String, _ unit: String, _ values: [Float], _ color: Color,
                           fmt: @escaping (Float) -> String = { String(Int($0.rounded())) }) -> some View {
        HangarPlate(contentPadding: 14) {
            TimeSeriesChart(values: values, label: label, unit: unit, color: color, valueFormat: fmt)
        }
        Spacer().frame(height: 10)
    }
}
