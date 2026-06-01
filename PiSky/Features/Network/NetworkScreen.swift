import SwiftUI
import Combine

/// Feeds & Network — outbound aggregator connectors, local services, throughput.
/// Ported from `feature/network` (NetworkScreen.kt + NetworkViewModel.kt).
@MainActor @Observable
final class NetworkViewModel {
    private(set) var feeds: [FeedConnector] = []
    private(set) var stats: StatsDto?
    private(set) var vitals: PiVitalsDto?
    private(set) var rolling: Rolling24hResponseDto?

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true
        c.piVitals.feeds.receive(on: RunLoop.main).sink { [weak self] in self?.feeds = $0 }.store(in: &bag)
        c.piVitals.stats.receive(on: RunLoop.main).sink { [weak self] in self?.stats = $0 }.store(in: &bag)
        c.piVitals.vitals.receive(on: RunLoop.main).sink { [weak self] in self?.vitals = $0 }.store(in: &bag)
        c.piVitals.rolling.receive(on: RunLoop.main).sink { [weak self] in self?.rolling = $0 }.store(in: &bag)
    }
}

private func humanBytes(_ n: Int64) -> String {
    if n >= 1_000_000_000 { return String(format: "%.2f GB", Double(n) / 1_000_000_000.0) }
    if n >= 1_000_000 { return String(format: "%.1f MB", Double(n) / 1_000_000.0) }
    if n >= 1_000 { return String(format: "%.1f KB", Double(n) / 1_000.0) }
    return "\(n) B"
}

private func humanBytesRate(_ bps: Double) -> String {
    if bps >= 1_000_000 { return String(format: "%.1f MB/s", bps / 1_000_000.0) }
    if bps >= 1_000 { return String(format: "%.0f KB/s", bps / 1_000.0) }
    return String(format: "%.0f B/s", bps)
}

private func feedUptime(_ sec: Double) -> String {
    let s = Int64(sec)
    if s <= 0 { return "down" }
    if s >= 86_400 { return "\(s / 86_400)d \((s % 86_400) / 3_600)h" }
    if s >= 3_600 { return "\(s / 3_600)h \((s % 3_600) / 60)m" }
    if s >= 60 { return "\(s / 60)m" }
    return "\(s)s"
}

struct NetworkScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var vm = NetworkViewModel()

    var body: some View {
        let feeds = vm.feeds
        let up = feeds.filter { $0.isUp }.count
        let remoteTotal = vm.stats?.total?.remote
        let outRate: Double? = {
            guard let r = vm.stats?.last1min?.remote, let dur = vm.stats?.last1min?.durationSec, dur > 0 else { return nil }
            return Double(r.bytesOut) / dur
        }()

        AtlasScaffold(
            title: "Feeds & Network",
            subtitle: feeds.isEmpty ? "querying connectors…" : "\(up) / \(feeds.count) aggregator feeds up",
            accent: Palette.cyan,
            live: !feeds.isEmpty || vm.stats != nil
        ) {
            // ── Throughput ──
            SectionLabel(text: "Throughput", accent: Palette.cyan)
            HangarPlate(contentPadding: 16) {
                VStack(alignment: .leading) {
                    HStack {
                        BigStat(value: outRate.map { humanBytesRate($0) } ?? "—", label: "uplink rate", accent: Palette.cyan)
                        Spacer()
                        BigStat(value: vm.stats?.last1min?.messagesValid.map { Fmt.grouped($0) } ?? "—",
                                label: "msgs / min", valueColor: Palette.textPrimary, accent: Palette.brass)
                    }
                    Spacer().frame(height: 12)
                    MetricRow(label: "Total uplink (all-time)", value: humanBytes(remoteTotal?.bytesOut ?? 0), valueColor: Palette.cyan)
                    MetricRow(label: "Total downlink (MLAT/remote in)", value: humanBytes(remoteTotal?.bytesIn ?? 0))
                    MetricRow(label: "Remote messages accepted", value: Fmt.grouped(remoteTotal?.modes ?? 0))
                }
            }

            Spacer().frame(height: 10)
            // ── Aggregator feeds ──
            SectionLabel(text: "Aggregator Feeds", accent: Palette.cyan, trailing: "outbound connectors")
            HangarPlate(contentPadding: 14) {
                if feeds.isEmpty {
                    Text("No connector telemetry (stats.prom unavailable).").font(.inter(13)).foregroundStyle(Palette.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack {
                        ForEach(feeds.sorted { $0.secondsConnected > $1.secondsConnected }) { f in feedRow(f) }
                    }
                }
            }

            Spacer().frame(height: 10)
            // ── Local services ──
            SectionLabel(text: "Local Services", accent: Palette.cyan)
            if let s = vm.vitals?.services {
                HangarPlate(contentPadding: 14) {
                    VStack {
                        serviceRow("readsb decoder", up: s.readsb || s.dump1090Fa)
                        serviceRow("piaware → FlightAware", up: s.piawareToFa)
                        serviceRow("dump978 (UAT)", up: s.dump978Fa)
                        serviceRow("skyaware978", up: s.skyaware978)
                    }
                }
            } else {
                Text("Service telemetry unavailable").font(.inter(12)).foregroundStyle(Palette.textMuted)
            }

            // ── 24h volume ──
            if let r = vm.rolling?.preferred {
                Spacer().frame(height: 10)
                SectionLabel(text: "24 h Volume", accent: Palette.brass)
                HStack(spacing: 8) {
                    StatPlate(label: "Messages", value: Fmt.grouped(r.messagesReceived), accent: Palette.brass)
                    StatPlate(label: "Positions", value: Fmt.grouped(r.positionsLogged), accent: Palette.statusOk)
                }
            }
        }
        .task { vm.start(container) }
    }

    private func feedRow(_ f: FeedConnector) -> some View {
        HStack {
            if f.isUp {
                LiveDot(color: Palette.statusOk, size: 9)
            } else {
                Circle().fill(Palette.signalRed).frame(width: 9, height: 9)
            }
            Spacer().frame(width: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(f.displayName).font(.inter(14, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                Text("\(f.host):\(f.port)").font(.psMono(10)).foregroundStyle(Palette.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(feedUptime(f.secondsConnected))
                .font(.psMono(12, weight: .medium))
                .foregroundStyle(f.isUp ? Palette.statusOk : Palette.signalRed)
        }
        .padding(.vertical, 6)
    }

    private func serviceRow(_ name: String, up: Bool) -> some View {
        HStack {
            Circle().fill(up ? Palette.statusOk : Palette.signalRed).frame(width: 9, height: 9)
            Spacer().frame(width: 10)
            Text(name).font(.inter(14)).foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(up ? "active" : "down")
                .font(.inter(12, weight: .medium))
                .foregroundStyle(up ? Palette.statusOk : Palette.signalRed)
        }
        .padding(.vertical, 6)
    }
}
