import SwiftUI
import Combine

// readsb supported tuner-gain steps (the RTL-SDR gain table) — `GAIN_VALUES` in Kotlin.
private let GAIN_VALUES: [String] = [
    "0.0", "0.9", "1.4", "2.7", "3.7", "7.7", "8.7", "12.5", "14.4", "15.7",
    "16.6", "19.7", "20.7", "22.9", "25.4", "28.0", "29.7", "32.8", "33.8",
    "36.4", "37.2", "38.6", "40.2", "42.1", "43.4", "43.9", "44.5", "48.0", "49.6",
]

// MARK: - DiagnosticsViewModel

/// Port of `DiagnosticsViewModel.kt`. Synthesizes a `PiStatusDto` from the shared telemetry hub
/// (`container.piVitals`) via `PiStatusSynthesizer`. Control actions (restart / gain / reboot) are
/// stubs — PiAware native has no control endpoint, so they surface an SSH-hint string
/// (PORTING_NOTES §5). Refresh fans out to `refreshVitalsOnce()` + `refreshStatsOnce()`.
@MainActor @Observable
final class DiagnosticsViewModel {

    private(set) var status: PiStatusDto?
    private(set) var lastError: String?
    private(set) var isRefreshing = false
    private(set) var actionBusy: String?

    private(set) var mlatLiveCount = 0
    private(set) var liveAircraftCount = 0

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private weak var container: AppContainer?
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true; container = c

        // Synthesize PiStatusDto whenever vitals/stats change. Connection mode supplies the
        // "connection error" surface (PiAware native has no separate vitals-error channel).
        Publishers.CombineLatest3(
            c.piVitals.vitals,
            c.piVitals.stats,
            c.aircraftRepository.observeConnectionMode()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] vitals, stats, mode in
            guard let self else { return }
            self.isRefreshing = false
            if let vitals {
                self.status = PiStatusSynthesizer.synthesize(vitals: vitals, stats: stats)
                self.lastError = nil
            } else {
                self.status = nil
                self.lastError = (mode == .error) ? "No response from receiver." : self.lastError
            }
        }
        .store(in: &bag)

        c.aircraftRepository.observeAircraft()
            .receive(on: RunLoop.main)
            .sink { [weak self] list in
                self?.liveAircraftCount = list.count
                self?.mlatLiveCount = list.filter { $0.isMlat }.count
            }
            .store(in: &bag)
    }

    func refresh() {
        guard let c = container else { return }
        isRefreshing = true
        Task {
            await c.piVitals.refreshVitalsOnce()
            await c.piVitals.refreshStatsOnce()
        }
    }

    func restartService(_ service: String) {
        lastError = "Service control unavailable on PiAware native — use SSH: " +
            "sudo systemctl restart \(service)"
    }

    func setGain(dongle: String, gain: String) {
        lastError = "Gain control unavailable on PiAware native — edit " +
            "/boot/firmware/piaware-config.txt (rtlsdr-gain) and restart readsb."
    }

    func reboot() {
        lastError = "Reboot button unavailable on PiAware native — use SSH: sudo reboot"
    }
}

// MARK: - DiagnosticsScreen

/// Port of `DiagnosticsScreen.kt` — read-only Pi telemetry on glass cards.
struct DiagnosticsScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var vm = DiagnosticsViewModel()
    @State private var showRebootConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // Header
                HStack {
                    Text("Pi Diagnostics")
                        .font(.inter(22, weight: .semibold))
                        .foregroundStyle(Palette.brass)
                    Spacer()
                    if vm.isRefreshing {
                        ProgressView().progressViewStyle(.circular).tint(Palette.cyan)
                    }
                    Button { vm.refresh() } label: {
                        Image(systemName: "arrow.clockwise").foregroundStyle(Palette.textSecondary)
                    }
                }

                if let err = vm.lastError {
                    DiagCard(borderColor: Palette.statusError) {
                        Text("Connection error")
                            .font(.inter(14, weight: .semibold))
                            .foregroundStyle(Palette.statusError)
                        Text(err)
                            .font(.inter(12))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }

                if let s = vm.status {
                    servicesCard(s)
                    systemCard(s)
                    rtlSdrCard(s)
                    signalCard(s)
                    mlatCard
                    gainCard(s)
                    powerCard
                    Spacer().frame(height: 8)
                } else if vm.lastError == nil {
                    DiagCard {
                        Text("Waiting for first response…")
                            .font(.inter(14))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Palette.background.ignoresSafeArea())
        .task { vm.start(container) }
        .alert("Reboot Pi?", isPresented: $showRebootConfirm) {
            Button("Reboot", role: .destructive) { vm.reboot() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Pi will be offline for about 60 seconds.")
        }
    }

    // ── Services ────────────────────────────────────────────────────────────
    private func servicesCard(_ s: PiStatusDto) -> some View {
        DiagCard {
            SectionTitle("Services")
            ServiceRow(name: "piaware", svc: s.piaware,
                       busy: vm.actionBusy == "piaware") { vm.restartService("piaware") }
            ServiceRow(name: "readsb", svc: s.decoder,
                       busy: vm.actionBusy == "readsb") { vm.restartService("readsb") }
            ServiceRow(name: "dump978-fa", svc: s.dump978,
                       busy: vm.actionBusy == "dump978-fa") { vm.restartService("dump978-fa") }
        }
    }

    // ── System ──────────────────────────────────────────────────────────────
    private func systemCard(_ s: PiStatusDto) -> some View {
        let r = s.resources
        return DiagCard {
            SectionTitle("System")
            if r.cpuPercent > 0.0 {
                StatRow("CPU", String(format: "%.1f%%", r.cpuPercent), colorForPct(r.cpuPercent))
            }
            if r.memTotalMb > 0 {
                StatRow("RAM",
                        String(format: "%d MB / %d MB (%.1f%%)", r.memUsedMb, r.memTotalMb, r.memPercent),
                        colorForPct(r.memPercent))
            }
            if r.diskFreeGb > 0.0 || r.diskPercent > 0.0 {
                StatRow("Disk",
                        String(format: "%.1f GB free (%.1f%% used)", r.diskFreeGb, r.diskPercent),
                        colorForPct(r.diskPercent))
            }
            StatRow("Temp",
                    String(format: "%.1f °C  /  %.1f °F", s.temp.celsius, s.temp.fahrenheit),
                    colorForTemp(s.temp.celsius))
            let loadAvg = r.loadAvg.prefix(3).map { String(format: "%.2f", $0) }.joined(separator: "  ")
            if !loadAvg.isEmpty {
                StatRow("Load", loadAvg, Palette.textPrimary)
            }
            if !s.throttle.flags.isEmpty {
                StatRow("Throttle", s.throttle.flags.joined(separator: ", "), Palette.statusError)
            } else {
                StatRow("Throttle", "ok", Palette.statusOk)
            }
        }
    }

    // ── RTL-SDR ──────────────────────────────────────────────────────────────
    private func rtlSdrCard(_ s: PiStatusDto) -> some View {
        DiagCard {
            SectionTitle("RTL-SDR")
            StatRow("Detected", s.rtlsdr.detected ? "yes" : "NO",
                    s.rtlsdr.detected ? Palette.statusOk : Palette.statusError)
            if !s.rtlsdr.device.isEmpty {
                Text(s.rtlsdr.device)
                    .font(.psMono(12))
                    .foregroundStyle(Palette.textMuted)
            }
        }
    }

    // ── Signal · readsb ───────────────────────────────────────────────────────
    private func signalCard(_ s: PiStatusDto) -> some View {
        let d = s.decoderStats
        return DiagCard {
            SectionTitle("Signal · readsb")
            StatRow("Aircraft", "\(d.aircraft)", Palette.textPrimary)
            StatRow("Messages (window)", "\(d.messages)", Palette.textPrimary)
            StatRow("Signal", String(format: "%.1f dBFS", d.signalDbfs), colorForSignal(d.signalDbfs))
            StatRow("Peak", String(format: "%.1f dBFS", d.peakSignalDbfs), colorForSignal(d.peakSignalDbfs))
            StatRow("Noise", String(format: "%.1f dBFS", d.noiseDbfs), Palette.textPrimary)
            StatRow("Strong", "\(d.strongSignals) (>−3 dBFS)",
                    d.strongSignals > 100 ? Palette.statusWarn : Palette.textPrimary)
        }
    }

    // ── MLAT note ──────────────────────────────────────────────────────────────
    private var mlatCard: some View {
        DiagCard {
            SectionTitle("MLAT")
            Text("FlightAware MLAT vitals are now in Stats → Pulse → FlightAware. " +
                 "ADSBx MLAT is disabled per current rig config.")
                .font(.inter(14))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    // ── Gain ──────────────────────────────────────────────────────────────────
    private func gainCard(_ s: PiStatusDto) -> some View {
        DiagCard {
            SectionTitle("Gain")
            GainPicker(label: "1090", current: s.gain1090,
                       busy: vm.actionBusy == "gain1090") { vm.setGain(dongle: "1090", gain: $0) }
            Spacer().frame(height: 8)
            GainPicker(label: "978", current: s.gain978,
                       busy: vm.actionBusy == "gain978") { vm.setGain(dongle: "978", gain: $0) }
        }
    }

    // ── Power ───────────────────────────────────────────────────────────────────
    private var powerCard: some View {
        DiagCard {
            SectionTitle("Power")
            Button { showRebootConfirm = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "power").font(.system(size: 18))
                    Text("Reboot Pi").font(.inter(14, weight: .medium))
                }
                .foregroundStyle(Palette.statusError)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Palette.statusError.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Reusable bits

private struct DiagCard<Content: View>: View {
    var borderColor: Color = Palette.glassBorder
    @ViewBuilder var content: () -> Content
    init(borderColor: Color = Palette.glassBorder, @ViewBuilder content: @escaping () -> Content) {
        self.borderColor = borderColor
        self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Palette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.inter(14, weight: .semibold))
            .foregroundStyle(Palette.brass)
            .padding(.bottom, 2)
    }
}

private struct ServiceRow: View {
    let name: String
    let svc: ServiceDto
    let busy: Bool
    let onRestart: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(svc.active ? Palette.statusOk : Palette.statusError)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.inter(14, weight: .medium)).foregroundStyle(Palette.textPrimary)
                Text("\(svc.state)\(svc.enabled ? "" : " · disabled")")
                    .font(.psMono(10))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button(action: onRestart) {
                if busy {
                    ProgressView().progressViewStyle(.circular).tint(Palette.cyan)
                        .frame(width: 14, height: 14)
                } else {
                    Text("Restart")
                        .font(.psMono(10))
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Palette.outline, lineWidth: 1)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    let valueColor: Color
    init(_ label: String, _ value: String, _ valueColor: Color) {
        self.label = label; self.value = value; self.valueColor = valueColor
    }
    var body: some View {
        HStack {
            Text(label)
                .font(.inter(12))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.psMono(14))
                .foregroundStyle(valueColor)
            Spacer()
        }
    }
}

private struct GainPicker: View {
    let label: String
    let current: String
    let busy: Bool
    let onPick: (String) -> Void

    private var currentIdx: Int {
        guard let v = Float(current) else { return -1 }
        return GAIN_VALUES.firstIndex { Float($0) == v } ?? -1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(label) MHz")
                    .font(.inter(12))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 80, alignment: .leading)
                Text("\(current) dB")
                    .font(.psMono(14, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                if busy {
                    ProgressView().progressViewStyle(.circular).tint(Palette.cyan)
                        .frame(width: 14, height: 14)
                }
            }
            HStack(spacing: 6) {
                GainButton(text: "−", bold: true,
                           enabled: !busy && currentIdx > 0) {
                    if currentIdx > 0 { onPick(GAIN_VALUES[currentIdx - 1]) }
                }
                GainButton(text: "max", enabled: !busy) { onPick("max") }
                GainButton(text: "auto", enabled: !busy) { onPick("auto") }
                GainButton(text: "+", bold: true,
                           enabled: !busy && currentIdx >= 0 && currentIdx < GAIN_VALUES.count - 1) {
                    if currentIdx >= 0 && currentIdx < GAIN_VALUES.count - 1 {
                        onPick(GAIN_VALUES[currentIdx + 1])
                    }
                }
            }
        }
    }
}

private struct GainButton: View {
    let text: String
    var bold: Bool = false
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.psMono(11, weight: bold ? .bold : .medium))
                .foregroundStyle(enabled ? Palette.textPrimary : Palette.textMuted.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Palette.outline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// ── Color thresholds (verbatim from Kotlin) ─────────────────────────────────────

private func colorForPct(_ pct: Double) -> Color {
    switch pct {
    case 90...:  return Palette.statusError
    case 70...:  return Palette.statusWarn
    default:     return Palette.statusOk
    }
}

private func colorForTemp(_ celsius: Double) -> Color {
    switch celsius {
    case 75...:  return Palette.statusError
    case 65...:  return Palette.statusWarn
    default:     return Palette.statusOk
    }
}

private func colorForSignal(_ dbfs: Double) -> Color {
    switch dbfs {
    case let x where x > -3.0:  return Palette.statusError
    case let x where x > -10.0: return Palette.statusOk
    case let x where x > -20.0: return Palette.statusWarn
    default:                    return Palette.textSecondary
    }
}
