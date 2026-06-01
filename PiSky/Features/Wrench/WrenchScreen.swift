import SwiftUI
import Combine

/// Wrench · Diagnostics — diagnostic suite for verifying a fresh PiAware install.
/// Read-only; observes the centralized telemetry hub (pi-vitals 5 s + stats.json 10 s).
/// Ported from `feature/wrench` (WrenchScreen.kt + WrenchViewModel.kt).
@MainActor @Observable
final class WrenchViewModel {
    private(set) var vitals: PiVitalsDto?
    private(set) var stats: StatsDto?
    private(set) var lastError: String?
    private(set) var isInitialLoad = true

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private weak var container: AppContainer?
    private var started = false

    // Latest raw error signals (combined into lastError like the Kotlin combine()).
    private var vErr: String?
    private var sErr: String?

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true; container = c
        c.piVitals.vitals.receive(on: RunLoop.main).sink { [weak self] in self?.vitals = $0; self?.recompute() }.store(in: &bag)
        c.piVitals.stats.receive(on: RunLoop.main).sink { [weak self] in self?.stats = $0; self?.recompute() }.store(in: &bag)
        c.piVitals.vitalsError.receive(on: RunLoop.main).sink { [weak self] in self?.vErr = $0; self?.recompute() }.store(in: &bag)
        c.piVitals.statsError.receive(on: RunLoop.main).sink { [weak self] in self?.sErr = $0; self?.recompute() }.store(in: &bag)
    }

    private func recompute() {
        // Show error only when sustained (data null + error present).
        if vitals == nil, let v = vErr { lastError = "vitals: \(v)" }
        else if stats == nil, let s = sErr { lastError = "stats: \(s)" }
        else { lastError = nil }
        isInitialLoad = vitals == nil && stats == nil && vErr == nil && sErr == nil
    }

    func refresh() {
        Task {
            await container?.piVitals.refreshVitalsOnce()
            await container?.piVitals.refreshStatsOnce()
        }
    }
}

/// Diagnostic verdict for one rule check.
enum Verdict { case ok, warn, fail, unknown }

/// A named check with a verdict + a short human-readable detail.
struct WrenchCheck: Identifiable {
    let id = UUID()
    let name: String
    let verdict: Verdict
    let detail: String
}

/// Pure derivation: turns raw DTOs into the troubleshooter's verdict list.
/// Ported faithfully from `deriveChecks()` — the canonical decision logic (12 checks).
func deriveChecks(vitals: PiVitalsDto?, stats: StatsDto?) -> [WrenchCheck] {
    var out: [WrenchCheck] = []

    // Service health — from pi-vitals.services
    let svc = vitals?.services
    out.append(WrenchCheck(
        name: "piaware → FlightAware",
        verdict: { switch svc?.piawareToFa { case true: return .ok; case false: return .fail; default: return .unknown } }(),
        detail: svc?.piawareToFa == true ? "uplink alive" : "no uplink to FA"
    ))

    // 1090 decoder — readsb OR dump1090_fa via decoderActive.
    let decoderName = svc?.readsb == true ? "readsb" : "dump1090-fa"
    let decoderUp = svc?.decoderActive == true
    out.append(WrenchCheck(
        name: "1090 decoder (\(decoderName))",
        verdict: svc == nil ? .unknown : (decoderUp ? .ok : .fail),
        detail: decoderUp ? "active" : "inactive — 1090 reception will fail"
    ))
    out.append(WrenchCheck(
        name: "dump978-fa decoder (UAT)",
        verdict: { switch svc?.dump978Fa { case true: return .ok; case false: return .warn; default: return .unknown } }(),
        detail: svc?.dump978Fa == true ? "active" : "inactive — UAT band offline (optional)"
    ))

    // RTL-SDR enumeration via pi-vitals.sdr.iface_count.
    let ifaces = vitals?.sdr?.ifaceCount ?? 0
    out.append(WrenchCheck(
        name: "RTL-SDR enumeration",
        verdict: ifaces >= 2 ? .ok : (ifaces == 1 ? .warn : .fail),
        detail: "\(ifaces) RTL-SDR dongle\(ifaces == 1 ? "" : "s") detected"
    ))

    // 1090 band MPS sanity
    let b1090 = vitals?.bands?.band1090
    let mps1090 = b1090?.mps
    out.append(WrenchCheck(
        name: "1090 MHz traffic",
        verdict: { if mps1090 == nil { return .unknown }; return mps1090! < 5.0 ? .warn : .ok }(),
        detail: {
            if mps1090 == nil { return "warming up — sample again in 5 s" }
            if mps1090! < 5.0 { return String(format: "%.1f mps — very low, check antenna", mps1090!) }
            return String(format: "%.0f mps · %d aircraft", mps1090!, b1090?.aircraftCount ?? 0)
        }()
    ))

    // 978 band visibility (UAT)
    let b978 = vitals?.bands?.band978
    let avail978 = b978?.available == true
    out.append(WrenchCheck(
        name: "978 MHz UAT",
        verdict: { if !avail978 { return .warn }; return (b978?.messagesCumulative ?? 0) < 1 ? .warn : .ok }(),
        detail: avail978 ? "\(b978?.messagesCumulative ?? 0) cumulative msgs · \(b978?.aircraftCount ?? 0) aircraft"
                         : "decoder offline / no /skyaware978 endpoint"
    ))

    // Receiver overload — samples_dropped > 0 in last minute
    let local = stats?.last1min?.local
    let statsLoading = stats == nil
    let dropped = local?.samplesDropped ?? 0
    out.append(WrenchCheck(
        name: "Receiver overload",
        verdict: statsLoading ? .unknown : (dropped > 0 ? .fail : .ok),
        detail: statsLoading ? "loading stats…" : (dropped > 0 ? "samples_dropped=\(dropped) — USB or CPU saturation" : "no samples dropped")
    ))

    // Clipping — true overload requires BOTH a hot peak AND sustained strong-signal rate.
    let peak = local?.peakSignal
    let msgsValid = stats?.last1min?.messagesValid ?? 0
    let strongCount = local?.strongSignals ?? 0
    let strongPct: Double? = msgsValid > 0 ? Double(strongCount) * 100.0 / Double(msgsValid) : nil
    let hotPeak = peak != nil && peak! > -3.0
    let sustainedStrong = (strongPct ?? 0.0) > 5.0
    out.append(WrenchCheck(
        name: "Clipping check",
        verdict: {
            if statsLoading { return .unknown }
            if peak == nil { return .unknown }
            return (hotPeak && sustainedStrong) ? .warn : .ok
        }(),
        detail: {
            if statsLoading { return "loading stats…" }
            guard let peak else { return "peak not reported" }
            if hotPeak && sustainedStrong {
                return String(format: "peak %.1f dBFS, %.1f%% strong msgs — receiver overloaded", peak, strongPct ?? 0.0)
            }
            if hotPeak {
                return String(format: "peak %.1f dBFS (single flyover spike, %.2f%% strong msgs OK)", peak, strongPct ?? 0.0)
            }
            return String(format: "peak %.1f dBFS clean (%.2f%% strong msgs)", peak, strongPct ?? 0.0)
        }()
    ))

    // SNR
    let snr = RfTelemetry.snrDb(signalDbfs: local?.signal, noiseDbfs: local?.noise)
    out.append(WrenchCheck(
        name: "Signal-to-noise",
        verdict: {
            if statsLoading { return .unknown }
            guard let snr else { return .unknown }
            return snr < 8.0 ? .warn : .ok
        }(),
        detail: {
            if statsLoading { return "loading stats…" }
            guard let snr else { return "signal/noise not reported" }
            return String(format: "%.1f dB", snr)
        }()
    ))

    // Throttle / voltage events
    let throttledOk = vitals?.throttledOk
    out.append(WrenchCheck(
        name: "Pi power / throttle",
        verdict: { switch throttledOk { case true: return .ok; case false: return .fail; default: return .unknown } }(),
        detail: {
            switch throttledOk {
            case true: return "throttled=\(vitals?.throttled ?? "—") (clean)"
            case false: return "throttled=\(vitals?.throttled ?? "—") — power or thermal event seen"
            default: return "—"
            }
        }()
    ))

    // Pi temp
    let tempF = vitals?.temp?.fahrenheit
    out.append(WrenchCheck(
        name: "CPU temperature",
        verdict: {
            guard let tempF else { return .unknown }
            if tempF >= 167 { return .fail }
            if tempF >= 149 { return .warn }
            return .ok
        }(),
        detail: tempF.map { String(format: "%.1f°F", $0) } ?? "—"
    ))

    // Runtime gain — top-level readsb gain preferred, legacy fallback.
    let gain = stats?.gainDb ?? local?.gainDb
    let gainHigh = gain != nil && gain! > 49.0
    let gainLow = gain != nil && gain! < 20.0
    func peakStr() -> String { peak.map { String(format: "%.1f dBFS", $0) } ?? "?" }
    out.append(WrenchCheck(
        name: "1090 gain control",
        verdict: {
            if statsLoading { return .unknown }
            if gainHigh && sustainedStrong { return .warn }
            if gainLow { return .warn }
            return .ok
        }(),
        detail: {
            if statsLoading { return "loading stats…" }
            guard let gain else { return "auto-managed (gain_db not reported)" }
            if gainHigh && sustainedStrong {
                return String(format: "%.1f dB ceiling · peak %@ · %.1f%% strong — overload, attenuate", gain, peakStr(), strongPct ?? 0.0)
            }
            if gainHigh {
                return String(format: "%.1f dB ceiling · peak %@ · %.2f%% strong (clean — antenna headroom)", gain, peakStr(), strongPct ?? 0.0)
            }
            if gainLow {
                return String(format: "%.1f dB · peak %@ · low — check antenna/coax", gain, peakStr())
            }
            return String(format: "%.1f dB · peak %@ · %.2f%% strong (nominal)", gain, peakStr(), strongPct ?? 0.0)
        }()
    ))

    return out
}

private func verdictColor(_ v: Verdict) -> Color {
    switch v {
    case .ok: return Palette.statusOk
    case .warn: return Palette.statusWarn
    case .fail: return Palette.statusError
    case .unknown: return Palette.textMuted
    }
}

struct WrenchScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var vm = WrenchViewModel()

    var body: some View {
        let checks = deriveChecks(vitals: vm.vitals, stats: vm.stats)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Wrench · Diagnostics").font(.inter(20, weight: .semibold)).foregroundStyle(Palette.brass)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { vm.refresh() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 18)).foregroundStyle(Palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                summaryBanner(checks)

                if let err = vm.lastError {
                    diagCard(border: Palette.statusError) {
                        Text("Connection error").font(.inter(14, weight: .semibold)).foregroundStyle(Palette.statusError)
                        Text(err).font(.inter(12)).foregroundStyle(Palette.textSecondary)
                    }
                }

                ForEach(checks) { c in checkRow(c) }

                diagCard {
                    Text("Sources").font(.inter(14, weight: .semibold)).foregroundStyle(Palette.brass)
                    Spacer().frame(height: 4)
                    Text("/pi-vitals.json (Pi companion, 5 s timer) + /skyaware/data/stats.json (readsb, 10 s)")
                        .font(.psMono(11)).foregroundStyle(Palette.textMuted)
                }

                Spacer().frame(height: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Palette.background.ignoresSafeArea())
        .task { vm.start(container) }
    }

    private func summaryBanner(_ checks: [WrenchCheck]) -> some View {
        let ok = checks.filter { $0.verdict == .ok }.count
        let warn = checks.filter { $0.verdict == .warn }.count
        let fail = checks.filter { $0.verdict == .fail }.count
        let unkn = checks.filter { $0.verdict == .unknown }.count
        let overall: Verdict = fail > 0 ? .fail : (warn > 0 ? .warn : (ok == 0 ? .unknown : .ok))
        let label: String
        let color: Color
        switch overall {
        case .ok: label = "Healthy"; color = Palette.statusOk
        case .warn: label = "Issues found"; color = Palette.statusWarn
        case .fail: label = "Action needed"; color = Palette.statusError
        case .unknown: label = "Waiting for data"; color = Palette.textMuted
        }
        return diagCard(border: color) {
            HStack {
                Circle().fill(color).frame(width: 12, height: 12)
                Spacer().frame(width: 10)
                Text(label).font(.inter(16, weight: .semibold)).foregroundStyle(color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                countChip("OK", ok, Palette.statusOk)
                Spacer().frame(width: 6)
                countChip("⚠", warn, Palette.statusWarn)
                Spacer().frame(width: 6)
                countChip("✕", fail, Palette.statusError)
                Spacer().frame(width: 6)
                countChip("?", unkn, Palette.textMuted)
            }
        }
    }

    private func countChip(_ label: String, _ n: Int, _ c: Color) -> some View {
        Text("\(label)  \(n)")
            .font(.inter(11, weight: .semibold)).foregroundStyle(c)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(c.opacity(0.15))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(c.opacity(0.45), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func checkRow(_ c: WrenchCheck) -> some View {
        let color = verdictColor(c.verdict)
        let border = c.verdict == .ok ? HangarLuxe.Glass.border : color.opacity(0.5)
        return diagCard(border: border) {
            HStack(alignment: .center) {
                Circle().fill(color).frame(width: 10, height: 10)
                Spacer().frame(width: 10)
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.name).font(.inter(14, weight: .medium)).foregroundStyle(Palette.textPrimary)
                    Text(c.detail).font(.psMono(12)).foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(verdictLabel(c.verdict))
                    .font(.inter(11, weight: .bold)).foregroundStyle(color)
            }
        }
    }

    private func verdictLabel(_ v: Verdict) -> String {
        switch v {
        case .ok: return "OK"; case .warn: return "WARN"; case .fail: return "FAIL"; case .unknown: return "—"
        }
    }

    private func diagCard<Content: View>(border: Color = HangarLuxe.Glass.border, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
