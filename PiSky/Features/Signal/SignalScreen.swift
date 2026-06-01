import SwiftUI
import Combine

/// Signal Lab — RF front-end + decode-quality. Reads the full readsb stats.json
/// (all windows), pi-vitals, and the prom RSSI quartiles via the shared telemetry hub.
/// Ported from `feature/signal` (SignalScreen.kt + SignalViewModel.kt).
@MainActor @Observable
final class SignalViewModel {
    enum Window: String, CaseIterable, Identifiable {
        case m1, m5, m15, total
        var id: String { rawValue }
        var label: String {
            switch self {
            case .m1: return "1 min"; case .m5: return "5 min"; case .m15: return "15 min"; case .total: return "Total"
            }
        }
    }

    private(set) var stats: StatsDto?
    private(set) var vitals: PiVitalsDto?
    private(set) var prom: PromMetrics?
    var window: Window = .m1

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true
        c.piVitals.stats.receive(on: RunLoop.main).sink { [weak self] in self?.stats = $0 }.store(in: &bag)
        c.piVitals.vitals.receive(on: RunLoop.main).sink { [weak self] in self?.vitals = $0 }.store(in: &bag)
        c.piVitals.prom.receive(on: RunLoop.main).sink { [weak self] in self?.prom = $0 }.store(in: &bag)
    }

    func block(_ s: StatsDto?) -> StatsPeriodDto? {
        switch window {
        case .m1: return s?.last1min
        case .m5: return s?.last5min
        case .m15: return s?.last15min
        case .total: return s?.total
        }
    }
}

private func fmtInt(_ n: Int64) -> String { Fmt.grouped(n) }
private func fmtInt(_ n: Int) -> String { Fmt.grouped(n) }
private func fmt1(_ d: Double?) -> String { d.map { String(format: "%.1f", $0) } ?? "—" }

private func signalColor(_ s: Double?) -> Color {
    guard let s else { return Palette.textMuted }
    if s > -3.0 { return Palette.signalRed }       // clipping / overload
    if s < -25.0 { return Palette.signalAmberHot }  // weak
    return Palette.statusOk
}
private func snrColor(_ snr: Double?) -> Color {
    guard let snr else { return Palette.textMuted }
    if snr >= 20 { return Palette.statusOk }
    if snr >= 10 { return Palette.signalAmberHot }
    return Palette.signalRed
}

struct SignalScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var vm = SignalViewModel()

    var body: some View {
        @Bindable var vm = vm
        let stats = vm.stats
        let block = vm.block(stats)
        let local = block?.local
        let signal = local?.signal
        let noise = local?.noise
        let snr = RfTelemetry.snrDb(signalDbfs: signal, noiseDbfs: noise)
        let strongPct: Double? = {
            guard let local, let block, block.messagesValid > 0 else { return nil }
            return Double(local.strongSignals) * 100.0 / Double(block.messagesValid)
        }()

        let sub: String = {
            var s = "gain \(fmt1(stats?.gainDb)) dB  ·  ppm \(fmt1(stats?.estimatedPpm))"
            if let t = vm.vitals?.temp?.celsius { s += "  ·  \(Int(t))°C" }
            return s
        }()

        AtlasScaffold(
            title: "Signal Lab",
            subtitle: sub,
            accent: Palette.cyan,
            live: stats != nil,
            actions: {
                HStack(spacing: 4) {
                    ForEach(SignalViewModel.Window.allCases) { w in
                        let sel = w == vm.window
                        Button {
                            HangarHaptics.select()
                            vm.window = w
                        } label: {
                            Text(w.label)
                                .font(.inter(10, weight: sel ? .bold : .regular))
                                .foregroundStyle(sel ? Palette.cyan : Palette.textMuted)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background((sel ? Palette.cyan.opacity(0.18) : Palette.outline.opacity(0.25)))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        ) {
            if stats == nil {
                Text("Connecting to receiver…").font(.inter(13)).foregroundStyle(Palette.textMuted)
            } else {
                content(block: block, local: local, signal: signal, noise: noise, snr: snr, strongPct: strongPct)
            }
        }
        .task { vm.start(container) }
    }

    @ViewBuilder
    private func content(block: StatsPeriodDto?, local: LocalStatsDto?,
                         signal: Double?, noise: Double?, snr: Double?, strongPct: Double?) -> some View {
        // ── RF hero meters ──
        SectionLabel(text: "RF Front-End", accent: Palette.cyan)
        HangarPlate(contentPadding: 14) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    RadialMeter(value: Float(signal ?? -30.0), min: -30, max: 0, label: "Signal", unit: "dBFS",
                                diameter: 116, color: signalColor(signal), valueText: fmt1(signal))
                    Spacer()
                    RadialMeter(value: Float(snr ?? 0.0), min: 0, max: 40, label: "SNR", unit: "dB",
                                diameter: 116, color: snrColor(snr), valueText: fmt1(snr))
                    Spacer()
                    RadialMeter(value: Float(strongPct ?? 0.0), min: 0, max: 50, label: "Strong", unit: "%",
                                diameter: 116, color: Palette.cyan,
                                valueText: strongPct.map { String(format: "%.1f", $0) } ?? "—")
                    Spacer()
                }
                Spacer().frame(height: 8)
                let peak = local?.peakSignal
                if let peak, peak > -3.0 {
                    Text("⚠ Peak \(fmt1(peak)) dBFS — near clipping; consider lowering gain")
                        .font(.inter(11)).foregroundStyle(Palette.signalRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Peak \(fmt1(peak)) dBFS · noise floor \(fmt1(noise)) dBFS")
                        .font(.inter(11)).foregroundStyle(Palette.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        Spacer().frame(height: 6)
        // ── RSSI distribution (prom quartiles) ──
        SectionLabel(text: "RSSI Distribution", accent: Palette.cyan, trailing: "live aircraft")
        if let p = vm.prom {
            HangarPlate(contentPadding: 14) {
                VStack(alignment: .leading) {
                    BoxPlotH(min: p.rssiMin, q1: p.rssiQ1, median: p.rssiMedian, q3: p.rssiQ3,
                             max: p.rssiMax, avg: p.rssiAvg, axisMin: -35, axisMax: 0, unit: "dBFS", color: Palette.cyan)
                    Spacer().frame(height: 6)
                    Text("Per-aircraft RSSI spread — box = middle 50% (Q1–Q3), line = median, ○ = mean. Closer to 0 = stronger.")
                        .font(.inter(10)).foregroundStyle(Palette.textMuted)
                }
            }
        } else {
            Text("RSSI quartiles unavailable").font(.inter(12)).foregroundStyle(Palette.textMuted)
        }

        Spacer().frame(height: 6)
        // ── Decode quality ──
        SectionLabel(text: "Decode Quality", accent: Palette.cyan, trailing: vm.window.label)
        HangarPlate(contentPadding: 14) {
            VStack(alignment: .leading) {
                if let l = local, let block {
                    let accepted = l.acceptedTotal
                    let cleanPct = accepted > 0 ? Double(l.acceptedClean) / Double(accepted) : 1.0
                    LinearMeter(fraction: cleanPct, label: "Clean decode rate (no bit-correction needed)",
                                valueText: String(format: "%.1f%%", cleanPct * 100), color: Palette.statusOk)
                    Spacer().frame(height: 12)
                    SegmentBar(segments: [
                        Segment(label: "clean", value: Double(l.acceptedClean), color: Palette.statusOk),
                        Segment(label: "1-bit corrected", value: Double(l.acceptedCorrected), color: Palette.cyan),
                    ])
                    Spacer().frame(height: 12)
                    MetricRow(label: "Valid messages", value: fmtInt(block.messagesValid), valueColor: Palette.statusOk)
                    MetricRow(label: "Accepted clean", value: fmtInt(l.acceptedClean), valueColor: Palette.statusOk)
                    MetricRow(label: "1-bit corrected", value: fmtInt(l.acceptedCorrected), valueColor: Palette.cyan)
                    Spacer().frame(height: 10)
                    Text("Demodulator throughput — raw candidates are mostly RF noise; a large rejected count is normal and healthy, not a fault.")
                        .font(.inter(10)).foregroundStyle(Palette.textMuted)
                    Spacer().frame(height: 4)
                    MetricRow(label: "Mode-S candidates", value: fmtInt(l.modes), sub: "all demodulated (incl. noise)")
                    MetricRow(label: "Rejected · bad CRC", value: fmtInt(l.bad), valueColor: Palette.textMuted,
                              sub: "noise that didn't checksum — expected")
                    MetricRow(label: "Rejected · unknown ICAO", value: fmtInt(l.unknownIcao), valueColor: Palette.textMuted,
                              sub: "valid CRC but not a tracked aircraft")
                }
            }
        }

        Spacer().frame(height: 6)
        // ── CPR position decode ──
        SectionLabel(text: "Position Decode (CPR)", accent: Palette.cyan, trailing: vm.window.label)
        HangarPlate(contentPadding: 14) {
            VStack(alignment: .leading) {
                if let c = block?.cpr {
                    SegmentBar(segments: [
                        Segment(label: "global ok", value: Double(c.globalOk), color: Palette.statusOk),
                        Segment(label: "local ok", value: Double(c.localOk), color: Palette.cyan),
                        Segment(label: "skipped", value: Double(c.globalSkipped + c.localSkipped), color: Palette.signalAmberHot),
                        Segment(label: "bad", value: Double(c.globalBad), color: Palette.signalRed),
                    ])
                    Spacer().frame(height: 12)
                    LinearMeter(fraction: c.globalOkRatio, label: "Global CPR success",
                                valueText: String(format: "%.2f%%", c.globalOkRatio * 100), color: Palette.statusOk)
                    Spacer().frame(height: 10)
                    MetricRow(label: "Airborne CPR", value: fmtInt(c.airborne))
                    MetricRow(label: "Global bad", value: fmtInt(c.globalBad),
                              valueColor: c.globalBad > 0 ? Palette.signalRed : Palette.textPrimary)
                    MetricRow(label: "Bad range / speed", value: "\(c.globalBadRange) / \(c.globalBadSpeed)",
                              sub: "elevated values hint at noise or spoofing")
                    MetricRow(label: "Local rx-relative", value: fmtInt(c.localReceiverRelative))
                }
            }
        }

        Spacer().frame(height: 6)
        // ── Sampler / front end ──
        SectionLabel(text: "Sampler & Tuner", accent: Palette.cyan)
        HStack(spacing: 8) {
            StatPlate(label: "Gain", value: fmt1(vm.stats?.gainDb), sub: "dB", accent: Palette.brass)
            StatPlate(label: "PPM", value: fmt1(vm.stats?.estimatedPpm), sub: "freq error")
            let dropped = local?.samplesDropped ?? 0
            StatPlate(label: "Dropped", value: fmtInt(dropped), sub: "samples",
                      accent: dropped > 0 ? Palette.signalRed : Palette.statusOk,
                      valueColor: dropped > 0 ? Palette.signalRed : Palette.textPrimary)
        }

        Spacer().frame(height: 12)
        // ── Demod phase histogram ──
        SectionLabel(text: "Demodulator Phase", accent: Palette.cyan, trailing: "best-phase bins")
        HangarPlate(contentPadding: 14) {
            VStack(alignment: .leading) {
                let bp = local?.bestPhase ?? []
                if bp.count >= 2 {
                    BarHistogram(bars: bp.enumerated().map { i, v in
                        HistoBar(label: "φ\(i + 1)", value: Float(v), color: Palette.cyan)
                    }, valueFormat: { Fmt.grouped(Int($0)) })
                    Spacer().frame(height: 6)
                    Text("Spread across phase bins = healthy demodulation; a single dominant bin can mean a tuning/ppm issue.")
                        .font(.inter(10)).foregroundStyle(Palette.textMuted)
                } else {
                    Text("Phase histogram not available").font(.inter(12)).foregroundStyle(Palette.textMuted)
                }
            }
        }
    }
}
