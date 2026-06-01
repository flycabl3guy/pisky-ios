import SwiftUI
import Combine

/// `HomeViewModel` — port of `HomeViewModel.kt`. Implements the headline state the v6 HomeScreen
/// consumes (allAircraft / liveStats / closestAircraft / peakRangeTodayMi / militaryToday /
/// rolling24hStats / currentMaxRangeMi + connection status). The long-tail derivations
/// (airlineCounts / hourlyData / countriesToday / liveExtremes / privacyCounts / categoriesLive /
/// emergencyAircraft / trend snapshots) are stubbed with TODOs — the v6 layout doesn't render them
/// (those cards were removed from HomeScreen 2026-05-16), so they're left for a later pass.
@MainActor @Observable
final class HomeViewModel {
    private(set) var allAircraft: [Aircraft] = []
    private(set) var liveStats: LiveStats?
    private(set) var receiverStats: ReceiverStats?
    private(set) var connectionMode: ConnectionMode = .disconnected
    private(set) var closestAircraft: Aircraft?
    private(set) var militaryToday: [UniqueAircraft] = []
    private(set) var rolling24hStats: Rolling24hStats = .empty
    private(set) var currentMaxRangeMi: Double = 0
    /// Monotonic daily peak range (mi), resets at local midnight (mirrors `trackPeakRangeToday`).
    private(set) var peakRangeTodayMi: Double = 0
    /// Receiver host string for the status pill (`192.168.1.207:8088`).
    private(set) var host: String = "—"

    // Derived status — LIVE when the connection mode is live, OFFLINE on error, else STALE.
    var statusKind: StatusKind {
        switch connectionMode {
        case .websocket, .pollingHttp: return .live
        case .error, .disconnected:    return .offline
        case .connecting:              return .stale
        }
    }
    var visibleCount: Int { liveStats?.aircraftTotal ?? allAircraft.count }
    var peakRangeNm: Double { peakRangeTodayMi / 1.15078 }
    var currentRangeNm: Double { currentMaxRangeMi / 1.15078 }

    // ── Stubs (TODO): long-tail derivations not rendered by the v6 layout ──────
    // TODO(port): airlineCounts, hourlyData/peakHour, countriesToday, liveExtremes,
    //   privacyCounts, categoriesLive, emergencyAircraft, airlines/visible 1h-delta snapshots,
    //   uniqueToday, dailyCount, tagsToday. Re-add with their HomeScreen cards if those tiles return.

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private weak var container: AppContainer?
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    @ObservationIgnored private var peakDate = ""
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true
        container = c
        peakDate = Self.today()

        c.aircraftRepository.observeAircraft()
            .receive(on: RunLoop.main)
            .sink { [weak self] list in
                guard let self else { return }
                self.allAircraft = list
                self.closestAircraft = list
                    .filter { $0.hasPosition && $0.distanceNm != nil && !$0.isOnGround }
                    .min { $0.distanceNm! < $1.distanceNm! }
                let maxMi = (list.compactMap(\.distanceNm).max() ?? 0) * 1.15078
                self.currentMaxRangeMi = maxMi
                self.updatePeak(maxMi)
            }
            .store(in: &bag)

        c.aircraftRepository.observeLiveStats()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.liveStats = $0 }
            .store(in: &bag)
        c.aircraftRepository.observeReceiverStats()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.receiverStats = $0 }
            .store(in: &bag)
        c.aircraftRepository.observeConnectionMode()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.connectionMode = $0 }
            .store(in: &bag)

        // militaryToday — filter today's unique list to confirmed military, newest first.
        c.aircraftRepository.observeUniqueToday()
            .receive(on: RunLoop.main)
            .sink { [weak self] list in
                self?.militaryToday = list.filter(\.isMilitary).sorted { $0.firstSeenMs > $1.firstSeenMs }
            }
            .store(in: &bag)

        c.statsRepository.observe24hStats()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.rolling24hStats = $0 }
            .store(in: &bag)

        // Host string + start live updates on config.
        c.connectionRepository.observeConfig()
            .receive(on: RunLoop.main)
            .sink { [weak self] config in
                self?.host = "\(config.hostname):\(config.port)"
                if !config.hostname.isEmpty { c.aircraftRepository.startLiveUpdates(config: config) }
            }
            .store(in: &bag)

        startStatsRefresh()
    }

    /// Pull 24h stats from the Pi on startup, then every 15 s; back off on failure
    /// (port of `startStatsRefresh`).
    private func startStatsRefresh() {
        statsTask?.cancel()
        statsTask = Task { [weak self, container] in
            var failures = 0
            while !Task.isCancelled {
                do {
                    _ = try await container?.statsRepository.refresh24hStats()
                    failures = 0
                    try? await Task.sleep(for: .seconds(15))
                } catch {
                    failures += 1
                    let backoff = min(Double(failures) * 10, 60)
                    try? await Task.sleep(for: .seconds(backoff))
                }
                _ = self
            }
        }
    }

    private func updatePeak(_ currentMi: Double) {
        let now = Self.today()
        if now != peakDate { peakDate = now; peakRangeTodayMi = currentMi }
        else if currentMi > peakRangeTodayMi { peakRangeTodayMi = currentMi }
    }

    private static func today() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Fmt.us
        return f.string(from: Date())
    }

    deinit { statsTask?.cancel() }
}
