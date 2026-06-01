import Foundation

/// UserDefaults-backed cache of the latest Pi-sourced rolling-24h stats for offline fallback —
/// port of the DataStore-backed `StatsCache`. 11 keys ↔ `Rolling24hStats`. Dates are stored as
/// epoch-seconds (`Int64`), matching the Kotlin `Instant.epochSecond` round-trip.
@MainActor
final class StatsCache {
    private let defaults: UserDefaults

    private enum Key {
        static let aircraft  = "stats_24h_aircraft"
        static let adsb      = "stats_24h_adsb"
        static let uat       = "stats_24h_uat"
        static let mlat      = "stats_24h_mlat"
        static let other     = "stats_24h_other"
        static let military  = "stats_24h_military"
        static let messages  = "stats_24h_messages"
        static let positions = "stats_24h_positions"
        static let winStart  = "stats_24h_win_start"
        static let winEnd    = "stats_24h_win_end"
        static let updated   = "stats_24h_updated"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Atomic-ish save of the current snapshot.
    func save(_ stats: Rolling24hStats) {
        defaults.set(stats.aircraftSeen, forKey: Key.aircraft)
        defaults.set(stats.adsbSeen, forKey: Key.adsb)
        defaults.set(stats.uatSeen, forKey: Key.uat)
        defaults.set(stats.mlatSeen, forKey: Key.mlat)
        defaults.set(stats.otherSeen, forKey: Key.other)
        defaults.set(stats.militarySeen, forKey: Key.military)
        defaults.set(stats.messagesReceived, forKey: Key.messages)
        defaults.set(stats.positionsLogged, forKey: Key.positions)
        defaults.set(Int64(stats.windowStart.timeIntervalSince1970), forKey: Key.winStart)
        defaults.set(Int64(stats.windowEnd.timeIntervalSince1970), forKey: Key.winEnd)
        defaults.set(Int64(stats.lastUpdated.timeIntervalSince1970), forKey: Key.updated)
    }

    /// Latest cached stats, or `.empty` if no cache (updated == 0).
    func load() -> Rolling24hStats {
        let updated = int64(Key.updated)
        if updated == 0 { return .empty }
        return Rolling24hStats(
            aircraftSeen: int(Key.aircraft),
            adsbSeen: int(Key.adsb),
            uatSeen: int(Key.uat),
            mlatSeen: int(Key.mlat),
            otherSeen: int(Key.other),
            militarySeen: int(Key.military),
            messagesReceived: int64(Key.messages),
            positionsLogged: int64(Key.positions),
            windowStart: Date(timeIntervalSince1970: TimeInterval(int64(Key.winStart))),
            windowEnd: Date(timeIntervalSince1970: TimeInterval(int64(Key.winEnd))),
            lastUpdated: Date(timeIntervalSince1970: TimeInterval(updated))
        )
    }

    private func int(_ k: String) -> Int { defaults.integer(forKey: k) }
    private func int64(_ k: String) -> Int64 {
        (defaults.object(forKey: k) as? NSNumber)?.int64Value ?? Int64(defaults.integer(forKey: k))
    }
}
