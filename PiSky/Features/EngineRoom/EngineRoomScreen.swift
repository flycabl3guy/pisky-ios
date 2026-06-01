import SwiftUI
import Combine

/// Engine Room — mission-critical telemetry surface. Two band-scoped dashboards
/// (1090 / 978) on a tab strip + a cross-band hardware-health card.
/// Ported from `feature/engineroom` (EngineRoomScreen.kt / EngineRoomViewModel.kt / CanvasGauge.kt).
@MainActor @Observable
final class EngineRoomViewModel {
    enum Band: String, CaseIterable, Identifiable {
        case band1090, band978
        var id: String { rawValue }
        var label: String { self == .band1090 ? "1090 MHz" : "978 MHz" }
    }

    private(set) var vitals: PiVitalsDto?
    private(set) var liveStats: LiveStats?
    private(set) var lastError: String?
    private(set) var warming = true
    var activeBand: Band = .band1090

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true
        c.piVitals.vitals.receive(on: RunLoop.main).sink { [weak self] v in
            guard let self else { return }
            self.vitals = v
            self.warming = (v?.bands?.band1090?.mps == nil)
        }.store(in: &bag)
        c.piVitals.vitalsError.receive(on: RunLoop.main).sink { [weak self] err in
            self?.lastError = err.map { "vitals: \($0)" }
        }.store(in: &bag)
        c.aircraftRepository.observeLiveStats().receive(on: RunLoop.main).sink { [weak self] in self?.liveStats = $0 }.store(in: &bag)
    }

    func selectBand(_ b: Band) { activeBand = b }
}

/// UI-side projection of one band's snapshot.
struct BandView {
    let band: EngineRoomViewModel.Band
    let mps: Double?
    let mpsNote: String?
    let messagesCumulative: Int64
    let aircraftCount: Int
    let signalDbfs: Double?
    let noiseDbfs: Double?
    let snrDb: Double?
    let strongSignals: Int?
    let rfHealth: RfHealth
}

/// Combines pi-vitals + liveStats into a per-band view. Ported from `deriveBandView`.
func deriveBandView(_ band: EngineRoomViewModel.Band, vitals: PiVitalsDto?, liveStats: LiveStats?) -> BandView {
    let b: PiBandDto? = band == .band1090 ? vitals?.bands?.band1090 : vitals?.bands?.band978
    // LiveStats reflects the dump1090-fa decoder — only attach it to 1090.
    let ls = band == .band1090 ? liveStats : nil
    let snr = RfTelemetry.snrDb(signalDbfs: ls?.signalDbfs, noiseDbfs: ls?.noiseDbfs)
    let strongPct: Double? = {
        guard let ls, ls.messagesLastMinute > 0 else { return nil }
        return Double(ls.strongSignals) * 100.0 / Double(ls.messagesLastMinute)
    }()
    let health: RfHealth = ls != nil
        ? RfTelemetry.classify(samplesDropped: 0, peakSignalDbfs: ls?.signalDbfs, snrDb: snr, badRatio: nil, strongSignalPct: strongPct)
        : .unknown
    let mpsNote: String? = {
        if b == nil { return "band not present" }
        if !(b!.available) { return "decoder offline" }
        if b!.mps == nil { return "warming up — sample again" }
        return nil
    }()
    return BandView(
        band: band,
        mps: b?.mps,
        mpsNote: mpsNote,
        messagesCumulative: b?.messagesCumulative ?? 0,
        aircraftCount: b?.aircraftCount ?? 0,
        signalDbfs: ls?.signalDbfs,
        noiseDbfs: ls?.noiseDbfs,
        snrDb: snr,
        strongSignals: ls?.strongSignals,
        rfHealth: health
    )
}

private func colorForSignal(_ dbfs: Double) -> Color {
    if dbfs > -3.0 { return Palette.statusError }
    if dbfs > -10.0 { return Palette.statusOk }
    if dbfs > -20.0 { return Palette.statusWarn }
    return Palette.textSecondary
}

/// RfHealth → display label + color (the iOS RfHealth enum has no .label color map).
private func rfHealthDisplay(_ h: RfHealth) -> (label: String, color: Color) {
    switch h {
    case .strong:                  return ("Strong", Palette.statusOk)
    case .ok:                      return ("OK", Palette.statusOk)
    case .weak:                    return ("Weak", Palette.statusWarn)
    case .noisy:                   return ("Noisy", Palette.statusWarn)
    case .nearClipping:            return ("Near clipping", Palette.statusError)
    case .overloadUsb:             return ("USB overload", Palette.statusError)
    case .unknown:                 return ("Unknown", Palette.textMuted)
    }
}

struct EngineRoomScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var vm = EngineRoomViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                vm.lastError.map { err in
                    Text(err).font(.psMono(12)).foregroundStyle(Palette.statusError)
                }
                bandTabStrip
                let view = deriveBandView(vm.activeBand, vitals: vm.vitals, liveStats: vm.liveStats)
                bandPanel(view)
                hardwareHealthCard(vm.vitals)
                Spacer().frame(height: 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Palette.background.ignoresSafeArea())
        .task { vm.start(container) }
    }

    private var header: some View {
        HStack {
            Text("Engine Room").font(.inter(20, weight: .semibold)).foregroundStyle(Palette.brass)
                .frame(maxWidth: .infinity, alignment: .leading)
            let pillColor: Color = vm.lastError != nil ? Palette.statusError : (vm.vitals == nil ? Palette.textMuted : Palette.statusOk)
            let pillLabel: String = {
                if vm.lastError != nil { return "ERR" }
                if vm.vitals == nil { return "WAITING" }
                return vm.warming ? "WARMING" : "LIVE"
            }()
            Text(pillLabel)
                .font(.inter(10, weight: .bold)).tracking(1)
                .foregroundStyle(pillColor)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(pillColor.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(pillColor.opacity(0.45), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var bandTabStrip: some View {
        HStack(spacing: 4) {
            ForEach(EngineRoomViewModel.Band.allCases) { b in
                let selected = b == vm.activeBand
                let ac = b == .band1090 ? (vm.vitals?.bands?.band1090?.aircraftCount ?? 0)
                                        : (vm.vitals?.bands?.band978?.aircraftCount ?? 0)
                Button {
                    HangarHaptics.select()
                    vm.selectBand(b)
                } label: {
                    HStack {
                        Text(b.label)
                            .font(.inter(14, weight: selected ? .bold : .medium))
                            .foregroundStyle(selected ? Palette.brass : Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(ac)")
                            .font(.psMono(11))
                            .foregroundStyle(selected ? Palette.brass : Palette.textMuted)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background(selected ? Palette.brass.opacity(0.18) : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(selected ? Palette.brass.opacity(0.45) : Color.clear, lineWidth: selected ? 1 : 0))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(4)
        .background(Palette.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(HangarLuxe.Glass.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func bandPanel(_ view: BandView) -> some View {
        engineCard("\(view.band.label) · Telemetry") {
            HStack(spacing: 8) {
                TelemetryGauge(label: "MPS", value: view.mps, min: 0,
                               max: view.band == .band1090 ? 1500 : 50, unit: "msg/s",
                               valueText: view.mps.map { $0 >= 100 ? String(format: "%.0f", $0) : String(format: "%.1f", $0) } ?? "—")
                // SNR — inverted thresholds (lower is worse), 1090 only.
                TelemetryGauge(label: "SNR", value: view.snrDb, min: 0, max: 30, unit: "dB",
                               warnAt: 8, errorAt: 4, invertThresholds: true,
                               valueText: view.snrDb.map { String(format: "%.1f", $0) } ?? "—")
                TelemetryGauge(label: "Aircraft", value: Double(view.aircraftCount), min: 0,
                               max: view.band == .band1090 ? 200 : 20, unit: "live",
                               valueText: "\(view.aircraftCount)")
            }
            Spacer().frame(height: 8)

            statRow("Cumulative msgs", Fmt.grouped(view.messagesCumulative), Palette.textPrimary)
            if let s = view.signalDbfs { statRow("Signal", String(format: "%.1f dBFS", s), colorForSignal(s)) }
            if let n = view.noiseDbfs { statRow("Noise", String(format: "%.1f dBFS", n), Palette.textPrimary) }
            if let strong = view.strongSignals {
                statRow("Strong (>−3 dBFS)", "\(strong)", strong > 100 ? Palette.statusWarn : Palette.textPrimary)
            }
            if view.band == .band978 {
                statRow("Signal/SNR", "— (978 stats not proxied)", Palette.textMuted)
            }
            if let note = view.mpsNote { statRow("MPS state", note, Palette.textMuted) }

            Spacer().frame(height: 6)
            let h = rfHealthDisplay(view.rfHealth)
            HStack {
                Circle().fill(h.color).frame(width: 12, height: 12)
                Spacer().frame(width: 8)
                Text("RF: \(h.label)").font(.inter(14, weight: .semibold)).foregroundStyle(h.color)
            }
        }
    }

    private func hardwareHealthCard(_ s: PiVitalsDto?) -> some View {
        engineCard("Hardware · Pi 4") {
            if let s {
                if let t = s.temp {
                    let color: Color = t.fahrenheit >= 167 ? Palette.statusError : (t.fahrenheit >= 149 ? Palette.statusWarn : Palette.statusOk)
                    statRow("CPU temp", String(format: "%.1f °F  /  %.1f °C", t.fahrenheit, t.celsius), color)
                }
                if let l = s.load {
                    statRow("Load avg", String(format: "%.2f  %.2f  %.2f", l.load1m, l.load5m, l.load15m), Palette.textPrimary)
                }
                if let m = s.mem {
                    let pct = m.percentUsed
                    let color: Color = pct >= 90 ? Palette.statusError : (pct >= 75 ? Palette.statusWarn : Palette.statusOk)
                    statRow("RAM", String(format: "%d / %d MB  (%.0f%%)", m.usedMb, m.totalMb, pct), color)
                }
                if let d = s.disk {
                    let pct = d.percentUsed
                    let color: Color = pct >= 90 ? Palette.statusError : (pct >= 80 ? Palette.statusWarn : Palette.statusOk)
                    statRow("Disk", String(format: "%.1f GB free  (%.0f%% used)", d.freeGb, pct), color)
                }
                if let up = s.uptimeSec { statRow("Uptime", Fmt.uptime(up), Palette.textPrimary) }
                if let u = s.sdr {
                    statRow("SDR ifaces", "\(u.ifaceCount)", u.ifaceCount > 0 ? Palette.statusOk : Palette.statusError)
                }
                if !s.throttledOk { statRow("Throttle", s.throttled, Palette.statusError) }
                if let svc = s.services {
                    statRow("FA uplink", svc.piawareToFa ? "connected" : "down", svc.piawareToFa ? Palette.statusOk : Palette.statusError)
                }
            } else {
                Text("Waiting for /pi-vitals.json…").font(.inter(13)).foregroundStyle(Palette.textMuted)
            }
        }
    }

    private func engineCard<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.inter(14, weight: .semibold)).foregroundStyle(Palette.brass)
            Spacer().frame(height: 2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(HangarLuxe.Glass.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func statRow(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        HStack(alignment: .center) {
            Text(label).font(.inter(12)).foregroundStyle(Palette.textSecondary).frame(width: 120, alignment: .leading)
            Text(value).font(.psMono(14)).foregroundStyle(valueColor)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - TelemetryGauge

/// 270° arc gauge with sweep-angle fill, threshold-color needle and value text.
/// Canvas port of `feature/engineroom/CanvasGauge.kt`. `warnAt`/`errorAt` are upper-bound
/// thresholds (nil = no danger zone); `invertThresholds` flips them for "lower is worse" metrics.
struct TelemetryGauge: View {
    let label: String
    let value: Double?
    let min: Double
    let max: Double
    let unit: String
    var warnAt: Double? = nil
    var errorAt: Double? = nil
    var invertThresholds: Bool = false
    var valueText: String? = nil

    private var pct: Double {
        guard let v = value, max > min else { return 0 }
        return Swift.min(Swift.max((v - min) / (max - min), 0), 1)
    }

    private var needleColor: Color {
        guard let v = value else { return Palette.textMuted }
        if warnAt == nil && errorAt == nil { return Palette.brass }
        if invertThresholds {
            if let e = errorAt, v < e { return Palette.statusError }
            if let w = warnAt, v < w { return Palette.statusWarn }
            return Palette.statusOk
        } else {
            if let e = errorAt, v >= e { return Palette.statusError }
            if let w = warnAt, v >= w { return Palette.statusWarn }
            return Palette.statusOk
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Canvas { ctx, size in drawGauge(ctx, size: size) }
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                VStack(spacing: 0) {
                    Text(valueText ?? value.map { formatGaugeValue($0) } ?? "—")
                        .font(.psMono(22, weight: .bold)).foregroundStyle(Palette.textPrimary)
                    Text(unit).font(.inter(10)).foregroundStyle(Palette.textMuted)
                }
            }
            Text(label).font(.inter(12, weight: .medium)).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func drawGauge(_ ctx: GraphicsContext, size: CGSize) {
        let cx = size.width / 2
        let cy = size.height * 0.65   // anchor below center → headroom for value text
        let r = (Swift.min(size.width, size.height) / 2) * 0.85
        let stroke = Swift.max(r * 0.13, 6)
        let startAngle = 135.0
        let sweep = 270.0

        let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        // track
        ctx.stroke(arcPath(rect: rect, start: startAngle, sweep: sweep),
                   with: .color(HangarLuxe.Glass.border), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
        // active arc
        let activeSweep = sweep * pct
        if activeSweep > 0 {
            ctx.stroke(arcPath(rect: rect, start: startAngle, sweep: activeSweep),
                       with: .color(needleColor), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
        }
        // needle
        let needleAngle = (startAngle + activeSweep) * .pi / 180
        let tip = CGPoint(x: cx + r * 0.92 * cos(needleAngle), y: cy + r * 0.92 * sin(needleAngle))
        let base = CGPoint(x: cx + r * 0.18 * cos(needleAngle + .pi), y: cy + r * 0.18 * sin(needleAngle + .pi))
        var needle = Path(); needle.move(to: base); needle.addLine(to: tip)
        ctx.stroke(needle, with: .color(needleColor), style: StrokeStyle(lineWidth: stroke * 0.45, lineCap: .round))
        // hub
        ctx.fill(circlePath(center: CGPoint(x: cx, y: cy), r: stroke * 0.55), with: .color(needleColor))
        ctx.fill(circlePath(center: CGPoint(x: cx, y: cy), r: stroke * 0.28), with: .color(.black))
    }

    private func formatGaugeValue(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.0f", v) }
        if v >= 100 { return String(format: "%.0f", v) }
        if v >= 10 { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }
}
