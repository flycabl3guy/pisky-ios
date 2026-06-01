import SwiftUI
import Combine

/// Coverage — actual range polygon + live traffic projected polar.
/// Ported from `feature/coverage` (CoverageScreen.kt + CoverageViewModel.kt).
@MainActor @Observable
final class CoverageViewModel {
    private(set) var coverage: CoverageOutline?
    private(set) var stats: StatsDto?
    private(set) var aircraft: [Aircraft] = []

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true
        c.piVitals.coverage.receive(on: RunLoop.main).sink { [weak self] in self?.coverage = $0 }.store(in: &bag)
        c.piVitals.stats.receive(on: RunLoop.main).sink { [weak self] in self?.stats = $0 }.store(in: &bag)
        c.aircraftRepository.observeAircraft().receive(on: RunLoop.main).sink { [weak self] in self?.aircraft = $0 }.store(in: &bag)
    }
}

private func altColor(_ ft: Int) -> Color {
    if ft < 10_000 { return Palette.altLow }
    if ft < 25_000 { return Palette.altMid }
    return Palette.altHigh
}
/// Null altitude must read as unknown (muted), not confidently "< 10k ft".
private func altColorOrUnknown(_ ft: Int?) -> Color { ft == nil ? Palette.textMuted : altColor(ft!) }

private let SECTORS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
private func sectorOf(_ bearing: Double) -> Int {
    Int(((bearing.truncatingRemainder(dividingBy: 360) + 22.5) / 45.0)) % 8
}

struct CoverageScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var vm = CoverageViewModel()

    var body: some View {
        let positioned = vm.aircraft.filter { $0.hasPosition && $0.distanceNm != nil && $0.bearingDeg != nil }
        let liveMax = positioned.compactMap { $0.distanceNm }.max() ?? 0.0
        let statsMax = vm.stats?.total?.maxDistanceNm ?? 0.0
        let cov = vm.coverage ?? CoverageOutline(points: [])
        let maxRange = max(cov.maxRangeNm, liveMax, statsMax, 50.0)
        // Cap rings AND normalizer together at 8×50 = 400 NM so labels/radius never diverge.
        let rings = min(max(Int(ceil(maxRange / 50.0)), 1), 8)
        let ringMax = Double(rings) * 50.0
        let ringLabels = (1...rings).map { String($0 * 50) }

        let rosePoints = cov.points.map {
            RosePoint(bearingDeg: $0.bearingDeg, rangeFraction: Float($0.rangeNm / ringMax), color: altColor($0.altFt))
        }
        let liveDots = positioned.map {
            RosePoint(bearingDeg: $0.bearingDeg!, rangeFraction: Float($0.distanceNm! / ringMax),
                      color: altColorOrUnknown($0.altitudeBaro))
        }

        AtlasScaffold(
            title: "Coverage",
            subtitle: "\(Int(maxRange)) NM max · \(positioned.count) live with position",
            accent: Palette.brass,
            live: vm.coverage != nil
        ) {
            SectionLabel(text: "Actual Coverage", accent: Palette.brass, trailing: "24 h outline + live")
            HangarPlate(contentPadding: 16) {
                if cov.isEmpty && liveDots.isEmpty {
                    Text("Awaiting coverage outline…").font(.inter(13)).foregroundStyle(Palette.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading) {
                        PolarRose(points: rosePoints, ringLabels: ringLabels, accent: Palette.brass, liveDots: liveDots)
                        Spacer().frame(height: 10)
                        HStack(spacing: 8) {
                            AtlasChip(text: "< 10k ft", color: Palette.altLow)
                            AtlasChip(text: "10–25k", color: Palette.altMid)
                            AtlasChip(text: "> 25k", color: Palette.altHigh)
                            Text("rings = 50 NM").font(.inter(10)).foregroundStyle(Palette.textMuted)
                        }
                    }
                }
            }

            Spacer().frame(height: 10)
            HStack(spacing: 8) {
                StatPlate(label: "Max range", value: "\(Int(cov.maxRangeNm))", sub: "NM (24 h)", accent: Palette.brass)
                StatPlate(label: "Peak (run)", value: "\(Int(statsMax))", sub: "NM · since restart", accent: Palette.altHigh)
                StatPlate(label: "Live", value: "\(positioned.count)", sub: "with position", accent: Palette.cyan)
            }

            if let p = cov.maxRangePoint {
                Spacer().frame(height: 10)
                SectionLabel(text: "Furthest Contact (24 h)", accent: Palette.brass)
                HangarPlate(contentPadding: 14) {
                    VStack {
                        MetricRow(label: "Range", value: "\(Int(p.rangeNm)) NM")
                        MetricRow(label: "Bearing", value: "\(Int(p.bearingDeg))°")
                        MetricRow(label: "Altitude", value: "\(Fmt.grouped(p.altFt)) ft")
                    }
                }
            }

            // ── Range by sector ──
            if !cov.points.isEmpty {
                Spacer().frame(height: 10)
                SectionLabel(text: "Range by Bearing", accent: Palette.brass, trailing: "best per sector")
                let bySector = bestRangePerSector(cov.points)
                HangarPlate(contentPadding: 14) {
                    BarHistogram(
                        bars: SECTORS.enumerated().map { i, s in HistoBar(label: s, value: Float(bySector[i]), color: Palette.brass) },
                        valueFormat: { String(Int($0)) }
                    )
                }
            }
        }
        .task { vm.start(container) }
    }

    /// Best (max) decoded range, in NM, per 45° compass sector.
    private func bestRangePerSector(_ points: [CoveragePoint]) -> [Int] {
        var out = [Int](repeating: 0, count: 8)
        for pt in points {
            let s = sectorOf(pt.bearingDeg)
            let r = Int(pt.rangeNm)
            if r > out[s] { out[s] = r }
        }
        return out
    }
}
