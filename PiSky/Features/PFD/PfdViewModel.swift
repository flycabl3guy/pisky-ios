import SwiftUI
import Combine

/// Drives the per-aircraft PFD screen. Takes the target `hex`, finds the
/// matching aircraft in the live feed, and accumulates a short rolling history
/// of (timestamp, track) tuples so the HSI can derive a turn rate.
///
/// Roll/pitch are NOT broadcast over ADS-B, so attitude is *derived* in the
/// view (flight-path angle from VS/GS, bank from broadcast roll or a
/// coordinated-turn estimate off this turn rate).
///
/// Ports `feature/pfd/PfdViewModel.kt`. Follows the contract VM convention but
/// `start` is initialized with a `hex` per the PfdScreen(hex:) call site.
@MainActor @Observable
final class PfdViewModel {

    private(set) var hex: String = ""
    private(set) var aircraft: Aircraft?
    private(set) var turnRateDegSec: Double = 0.0

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private weak var container: AppContainer?
    private var started = false

    /// One (timestamp, track) sample. `ts` is seconds (monotonic-ish wall clock,
    /// matching the Kotlin `System.currentTimeMillis()/1000` usage).
    private struct TrackSample { let ts: TimeInterval; let track: Double }
    @ObservationIgnored private var trackHistory: [TrackSample] = []

    func start(_ c: AppContainer, hex: String) {
        guard !started else { return }
        started = true
        container = c
        self.hex = hex.lowercased()

        c.aircraftRepository.observeAircraft()
            .receive(on: RunLoop.main)
            .sink { [weak self] list in
                guard let self else { return }
                let match = list.first { $0.hex.caseInsensitiveCompare(self.hex) == .orderedSame }
                self.aircraft = match
                self.ingestTrack(match?.track)
            }
            .store(in: &bag)
    }

    /// Append the latest track sample and recompute the rolling turn rate.
    /// Mirrors the Kotlin `init` collector: ignore nil track, keep ≤30 samples.
    private func ingestTrack(_ track: Double?) {
        guard let track else { return }
        let now = Date().timeIntervalSince1970
        trackHistory.append(TrackSample(ts: now, track: track))
        while trackHistory.count > 30 { trackHistory.removeFirst() }
        turnRateDegSec = Self.computeTurnRate(trackHistory)
    }

    /// First-to-last track delta over elapsed time, with ±180° wrap handling.
    private static func computeTurnRate(_ history: [TrackSample]) -> Double {
        guard history.count >= 2, let first = history.first, let last = history.last else { return 0.0 }
        let dtSec = last.ts - first.ts
        if dtSec < 1.0 { return 0.0 }
        var delta = last.track - first.track
        while delta >  180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        return delta / dtSec
    }
}
