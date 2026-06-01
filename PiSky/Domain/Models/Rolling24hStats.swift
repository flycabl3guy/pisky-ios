import Foundation

/// Rolling 24-hour statistics (Pi-authoritative, cached locally) — `Rolling24hStats.kt`.
/// `Instant` → `Date`; the "empty" sentinel uses the Unix epoch.
struct Rolling24hStats: Equatable, Sendable {
    var aircraftSeen: Int
    var adsbSeen: Int
    var uatSeen: Int
    var mlatSeen: Int
    var otherSeen: Int
    var militarySeen: Int
    var messagesReceived: Int64
    var positionsLogged: Int64
    var windowStart: Date
    var windowEnd: Date
    var lastUpdated: Date

    private var ageSeconds: Int { max(0, Int(Date().timeIntervalSince(lastUpdated))) }

    /// True if the Pi hasn't updated in > 5 minutes.
    var isStale: Bool { Date().timeIntervalSince(lastUpdated) > 300 }
    /// True if the cache is older than 24 h — data is meaningless at this point.
    var isExpired: Bool { Date().timeIntervalSince(lastUpdated) > 24 * 3600 }

    /// "just now" / "2 min ago" / "3 h ago" / "1 d ago".
    var ageDisplay: String {
        let s = Int(Date().timeIntervalSince(lastUpdated))
        switch s {
        case ..<60:    return "just now"
        case ..<3600:  return "\(s / 60) min ago"
        case ..<86400: return "\(s / 3600) h ago"
        default:       return "\(s / 86400) d ago"
        }
    }

    var isEmpty: Bool { lastUpdated.timeIntervalSince1970 == 0 }

    static let empty = Rolling24hStats(
        aircraftSeen: 0, adsbSeen: 0, uatSeen: 0, mlatSeen: 0, otherSeen: 0, militarySeen: 0,
        messagesReceived: 0, positionsLogged: 0,
        windowStart: Date(timeIntervalSince1970: 0),
        windowEnd: Date(timeIntervalSince1970: 0),
        lastUpdated: Date(timeIntervalSince1970: 0)
    )
}
