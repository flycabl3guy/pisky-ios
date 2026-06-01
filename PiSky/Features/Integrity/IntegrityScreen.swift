import SwiftUI
import Combine

/// Integrity / MOPS — fleet-wide position-quality landscape from live aircraft.
/// Ported from `feature/integrity` (IntegrityScreen.kt + IntegrityViewModel.kt).
@MainActor @Observable
final class IntegrityViewModel {
    private(set) var aircraft: [Aircraft] = []

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true
        c.aircraftRepository.observeAircraft().receive(on: RunLoop.main).sink { [weak self] in self?.aircraft = $0 }.store(in: &bag)
    }
}

struct IntegrityScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var vm = IntegrityViewModel()

    var body: some View {
        let aircraft = vm.aircraft
        let reporting = aircraft.filter { $0.nacP != nil || $0.nic != nil }
        let v0 = aircraft.filter { $0.version == 0 }.count
        let v1 = aircraft.filter { $0.version == 1 }.count
        let v2 = aircraft.filter { $0.version == 2 }.count
        var nacpHist = [Int](repeating: 0, count: 12)
        for ac in reporting { if let v = ac.nacP, (0...11).contains(v) { nacpHist[v] += 1 } }
        var nicHist = [Int](repeating: 0, count: 12)
        for ac in reporting { if let v = ac.nic, (0...11).contains(v) { nicHist[v] += 1 } }
        let sil0 = aircraft.filter { $0.sil == 0 }.count
        let sil1 = aircraft.filter { $0.sil == 1 }.count
        let sil2 = aircraft.filter { $0.sil == 2 }.count
        let sil3 = aircraft.filter { $0.sil == 3 }.count
        let v2pct = aircraft.isEmpty ? 0 : v2 * 100 / aircraft.count

        let scatter = reporting.filter { $0.nacP != nil && $0.nic != nil }.map { ac -> ScatterPoint in
            let q = Float(min(ac.nacP!, ac.nic!)) / 11.0
            return ScatterPoint(x: Float(ac.nacP!), y: Float(ac.nic!), color: qualityColor(Double(q)), radius: 5)
        }
        let lowest = aircraft
            .filter { $0.version == 0 || ($0.nacP ?? 11) <= 5 }
            .sorted { ($0.nacP ?? 0) < ($1.nacP ?? 0) }
            .prefix(8)

        AtlasScaffold(
            title: "Integrity",
            subtitle: "\(reporting.count) reporting · DO-260B MOPS",
            accent: Palette.statusOk,
            live: !aircraft.isEmpty
        ) {
            SectionLabel(text: "Fleet Quality", accent: Palette.statusOk)
            HStack(spacing: 8) {
                StatPlate(label: "Reporting", value: "\(reporting.count)", accent: Palette.cyan)
                StatPlate(label: "DO-260B", value: "\(v2pct)%", sub: "\(v2) of \(aircraft.count)", accent: Palette.statusOk)
                StatPlate(label: "Legacy v0", value: "\(v0)",
                          accent: v0 > 0 ? Palette.signalAmberHot : Palette.statusOk,
                          valueColor: v0 > 0 ? Palette.signalAmberHot : Palette.textPrimary)
            }

            Spacer().frame(height: 10)
            // ── NACp vs NIC scatter ──
            SectionLabel(text: "Accuracy × Integrity", accent: Palette.statusOk, trailing: "NACp × NIC")
            HangarPlate(contentPadding: 14) {
                if scatter.isEmpty {
                    Text("No aircraft reporting NACp + NIC yet…").font(.inter(13)).foregroundStyle(Palette.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading) {
                        ScatterPlot(points: scatter, xMax: 11, yMax: 11,
                                    xLabel: "NACp (accuracy) →", yLabel: "↑ NIC (integrity)", height: 210, grid: 11)
                        Spacer().frame(height: 6)
                        Text("Top-right = best (tight, trustworthy). Each dot is one aircraft; colour = lower of the two.")
                            .font(.inter(10)).foregroundStyle(Palette.textMuted)
                    }
                }
            }

            Spacer().frame(height: 10)
            // ── ADS-B version mix ──
            SectionLabel(text: "ADS-B Version", accent: Palette.statusOk)
            HangarPlate(contentPadding: 14) {
                SegmentBar(segments: [
                    Segment(label: "v2 DO-260B", value: Double(v2), color: Palette.statusOk),
                    Segment(label: "v1 DO-260A", value: Double(v1), color: Palette.cyan),
                    Segment(label: "v0 legacy", value: Double(v0), color: Palette.signalAmberHot),
                ])
            }

            Spacer().frame(height: 10)
            // ── NACp histogram ──
            SectionLabel(text: "NACp — Position Accuracy", accent: Palette.statusOk, trailing: "count by code")
            HangarPlate(contentPadding: 14) {
                VStack(alignment: .leading) {
                    BarHistogram(
                        bars: (0...11).map { c in HistoBar(label: "\(c)", value: Float(nacpHist[c]), color: qualityColor(Double(c) / 11.0)) },
                        valueFormat: { String(Int($0)) }
                    )
                    Spacer().frame(height: 6)
                    Text("NACp 9 ≈ <30 m, 8 ≈ <93 m (0.05 NM). Higher = more accurate position.")
                        .font(.inter(10)).foregroundStyle(Palette.textMuted)
                }
            }

            Spacer().frame(height: 10)
            // ── NIC histogram ──
            SectionLabel(text: "NIC — Containment Radius", accent: Palette.statusOk, trailing: "count by code")
            HangarPlate(contentPadding: 14) {
                VStack(alignment: .leading) {
                    BarHistogram(
                        bars: (0...11).map { c in HistoBar(label: "\(c)", value: Float(nicHist[c]), color: qualityColor(Double(c) / 11.0)) },
                        valueFormat: { String(Int($0)) }
                    )
                    Spacer().frame(height: 6)
                    Text("NIC 8 = Rc <185 m, 7 = <370 m (0.2 NM, min for normal ATC).")
                        .font(.inter(10)).foregroundStyle(Palette.textMuted)
                }
            }

            Spacer().frame(height: 10)
            // ── SIL ──
            SectionLabel(text: "SIL — Integrity Level", accent: Palette.statusOk)
            HangarPlate(contentPadding: 14) {
                VStack(alignment: .leading) {
                    SegmentBar(segments: [
                        Segment(label: "SIL 3", value: Double(sil3), color: Palette.statusOk),
                        Segment(label: "SIL 2", value: Double(sil2), color: Palette.cyan),
                        Segment(label: "SIL 1", value: Double(sil1), color: Palette.signalAmberHot),
                        Segment(label: "SIL 0", value: Double(sil0), color: Palette.signalRed),
                    ])
                    Spacer().frame(height: 8)
                    Text("SIL 3 = chance true position exceeds Rc ≤ 1×10⁻⁷ (separation-grade).")
                        .font(.inter(10)).foregroundStyle(Palette.textMuted)
                }
            }

            // ── Lowest integrity in view ──
            if !lowest.isEmpty {
                Spacer().frame(height: 10)
                SectionLabel(text: "Lowest Integrity In View", accent: Palette.signalAmberHot)
                HangarPlate(contentPadding: 14) {
                    VStack {
                        ForEach(Array(lowest)) { ac in lowRow(ac) }
                    }
                }
            }
        }
        .task { vm.start(container) }
    }

    private func lowRow(_ ac: Aircraft) -> some View {
        let nacp = AdsbIntegrity.nacp(ac.nacP)
        return MetricRow(
            label: ac.displayCallsign,
            value: "\(AdsbIntegrity.versionShort(ac.version)) · NACp \(ac.nacP.map(String.init) ?? "—")",
            valueColor: qualityColor(Double(ac.nacP ?? 0) / 11.0),
            sub: nacp.bound
        )
    }
}
