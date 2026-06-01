import Foundation

/// Wire shape of L2's `/pi-rolling-24h.json` — `Rolling24hStatsDto.kt`. Canonical surface count is
/// `todayCentral` (local readsb, CDT-midnight reset). Falls back to `today` then `rolling24h`.
struct Rolling24hResponseDto: Decodable, Sendable {
    let todayCentral: Rolling24hDto?
    let today: Rolling24hDto?
    let rolling24h: Rolling24hDto?
    let recent: [RecentDayDto]
    let militaryHistory: [MilitaryHistoryEntryDto]

    enum CodingKeys: String, CodingKey {
        case todayCentral
        case today
        case rolling24h
        case recent
        case militaryHistory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        todayCentral = try c.decodeIfPresent(Rolling24hDto.self, forKey: .todayCentral)
        today = try c.decodeIfPresent(Rolling24hDto.self, forKey: .today)
        rolling24h = try c.decodeIfPresent(Rolling24hDto.self, forKey: .rolling24h)
        recent = try c.decodeIfPresent([RecentDayDto].self, forKey: .recent) ?? []
        militaryHistory = try c.decodeIfPresent([MilitaryHistoryEntryDto].self, forKey: .militaryHistory) ?? []
    }

    /// Preferred block: todayCentral → today → rolling24h → empty.
    var preferred: Rolling24hDto { todayCentral ?? today ?? rolling24h ?? .empty }
}

/// One day of the rolling-24h aggregator's `recent[]` history block.
struct RecentDayDto: Decodable, Sendable {
    let dateUtc: String
    let dateEpoch: Int64
    let aircraftSeen: Int
    let adsbSeen: Int
    let uatSeen: Int
    let mlatSeen: Int
    let otherSeen: Int
    let positionsLogged: Int64

    enum CodingKeys: String, CodingKey {
        case dateUtc
        case dateEpoch
        case aircraftSeen
        case adsbSeen
        case uatSeen
        case mlatSeen
        case otherSeen
        case positionsLogged
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dateUtc = try c.decodeIfPresent(String.self, forKey: .dateUtc) ?? ""
        dateEpoch = try c.decodeIfPresent(Int64.self, forKey: .dateEpoch) ?? 0
        aircraftSeen = try c.decodeIfPresent(Int.self, forKey: .aircraftSeen) ?? 0
        adsbSeen = try c.decodeIfPresent(Int.self, forKey: .adsbSeen) ?? 0
        uatSeen = try c.decodeIfPresent(Int.self, forKey: .uatSeen) ?? 0
        mlatSeen = try c.decodeIfPresent(Int.self, forKey: .mlatSeen) ?? 0
        otherSeen = try c.decodeIfPresent(Int.self, forKey: .otherSeen) ?? 0
        positionsLogged = try c.decodeIfPresent(Int64.self, forKey: .positionsLogged) ?? 0
    }
}

/// One row of the L2 aggregator's military rolling-24h history. Hex is always present;
/// callsign/registration filled in when readsb populated them within the 24h window.
struct MilitaryHistoryEntryDto: Decodable, Sendable {
    let hex: String
    let callsign: String?
    let registration: String?
    let type: String?
    let band: String?
    let firstSeenMs: Int64
    let lastSeenMs: Int64

    enum CodingKeys: String, CodingKey {
        case hex
        case callsign
        case registration
        case type
        case band
        case firstSeenMs
        case lastSeenMs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hex = try c.decode(String.self, forKey: .hex)
        callsign = try c.decodeIfPresent(String.self, forKey: .callsign)
        registration = try c.decodeIfPresent(String.self, forKey: .registration)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        band = try c.decodeIfPresent(String.self, forKey: .band)
        firstSeenMs = try c.decodeIfPresent(Int64.self, forKey: .firstSeenMs) ?? 0
        lastSeenMs = try c.decodeIfPresent(Int64.self, forKey: .lastSeenMs) ?? 0
    }
}

struct Rolling24hDto: Decodable, Sendable {
    let aircraftSeen: Int
    let adsbSeen: Int
    let uatSeen: Int
    let mlatSeen: Int
    let otherSeen: Int
    let militarySeen: Int
    let messagesReceived: Int64
    let positionsLogged: Int64
    let windowStartUtc: String
    let windowEndUtc: String
    let lastUpdatedUtc: String

    enum CodingKeys: String, CodingKey {
        case aircraftSeen
        case adsbSeen
        case uatSeen
        case mlatSeen
        case otherSeen
        case militarySeen
        case messagesReceived
        case positionsLogged
        case windowStartUtc
        case windowEndUtc
        case lastUpdatedUtc
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aircraftSeen = try c.decodeIfPresent(Int.self, forKey: .aircraftSeen) ?? 0
        adsbSeen = try c.decodeIfPresent(Int.self, forKey: .adsbSeen) ?? 0
        uatSeen = try c.decodeIfPresent(Int.self, forKey: .uatSeen) ?? 0
        mlatSeen = try c.decodeIfPresent(Int.self, forKey: .mlatSeen) ?? 0
        otherSeen = try c.decodeIfPresent(Int.self, forKey: .otherSeen) ?? 0
        militarySeen = try c.decodeIfPresent(Int.self, forKey: .militarySeen) ?? 0
        messagesReceived = try c.decodeIfPresent(Int64.self, forKey: .messagesReceived) ?? 0
        positionsLogged = try c.decodeIfPresent(Int64.self, forKey: .positionsLogged) ?? 0
        windowStartUtc = try c.decodeIfPresent(String.self, forKey: .windowStartUtc) ?? ""
        windowEndUtc = try c.decodeIfPresent(String.self, forKey: .windowEndUtc) ?? ""
        lastUpdatedUtc = try c.decodeIfPresent(String.self, forKey: .lastUpdatedUtc) ?? ""
    }

    private init() {
        aircraftSeen = 0; adsbSeen = 0; uatSeen = 0; mlatSeen = 0; otherSeen = 0
        militarySeen = 0; messagesReceived = 0; positionsLogged = 0
        windowStartUtc = ""; windowEndUtc = ""; lastUpdatedUtc = ""
    }

    /// All-zero default — mirrors Kotlin's `Rolling24hDto()` fallback in `preferred`.
    static let empty = Rolling24hDto()
}
