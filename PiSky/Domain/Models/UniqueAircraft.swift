import Foundation

/// Lightweight unique-aircraft record — `UniqueAircraft.kt`.
struct UniqueAircraft: Identifiable, Equatable, Sendable {
    let hex: String
    var type: String?
    var callsign: String?
    var registration: String?
    var firstSeenMs: Int64
    var isMilitary: Bool = false

    var id: String { hex }
}

/// Today / yesterday unique counts — `DailyCount.kt`.
struct DailyCount: Equatable, Sendable {
    var today: Int
    var yesterday: Int
    static let zero = DailyCount(today: 0, yesterday: 0)
}

/// One row of L2's rolling-24h military history — `MilitaryHistoryEntry.kt`.
struct MilitaryHistoryEntry: Identifiable, Equatable, Sendable {
    let hex: String
    var callsign: String?
    var registration: String?
    var type: String?
    var band: String?
    var firstSeenMs: Int64
    var lastSeenMs: Int64

    var id: String { hex }
}
