import SwiftUI
import Combine

/// `RadarViewModel` — port of `RadarViewModel.kt`. Pure-vector PPI state: live aircraft, the
/// receiver position, per-aircraft FIFO trails, selection, and the three display toggles. Kicks off
/// `startLiveUpdates` itself so navigating directly to Radar doesn't hit the "no data" state.
@MainActor @Observable
final class RadarViewModel {
    private(set) var aircraft: [Aircraft] = []
    private(set) var receiver: ReceiverStats?
    /// Per-aircraft trail buffer keyed by hex; oldest-first, capped at `trailLen`.
    private(set) var trails: [String: [TrailPoint]] = [:]
    private(set) var selectedHex: String?

    var showTrails = true
    var showLabels = true
    var showRings = true

    static let trailLen = 60   // ~60 samples × 1 Hz ≈ 1 minute of trail

    struct TrailPoint: Equatable { let lat: Double; let lon: Double }

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private weak var container: AppContainer?
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true
        container = c

        c.aircraftRepository.observeAircraft()
            .receive(on: RunLoop.main)
            .sink { [weak self] list in
                self?.aircraft = list
                self?.accumulateTrails(list)
            }
            .store(in: &bag)
        c.aircraftRepository.observeReceiverStats()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.receiver = $0 }
            .store(in: &bag)

        // Idempotent: ensure the live pipeline is running for the latest config.
        Task {
            let cfg = await c.connectionRepository.getConfig()
            if !cfg.hostname.isEmpty { c.aircraftRepository.startLiveUpdates(config: cfg) }
        }
    }

    func selectAircraft(_ hex: String?) { selectedHex = hex }
    func toggleTrails() { showTrails.toggle() }
    func toggleLabels() { showLabels.toggle() }
    func toggleRings() { showRings.toggle() }
    func clearTrails() { trails.removeAll() }

    /// Append a new position per aircraft when it changes; drop aircraft no longer present;
    /// keep the deque ≤ `trailLen` (ported from the Android `aircraft.collect { … }` block).
    private func accumulateTrails(_ list: [Aircraft]) {
        var current = trails
        var seen = Set<String>()
        for a in list {
            guard let lat = a.latitude, let lon = a.longitude else { continue }
            seen.insert(a.hex)
            var deque = current[a.hex] ?? []
            if let last = deque.last, last.lat == lat, last.lon == lon {
                // unchanged — skip
            } else {
                deque.append(TrailPoint(lat: lat, lon: lon))
                if deque.count > Self.trailLen { deque.removeFirst(deque.count - Self.trailLen) }
            }
            current[a.hex] = deque
        }
        for key in current.keys where !seen.contains(key) { current.removeValue(forKey: key) }
        trails = current
    }
}
