import Foundation

/// Wire shape of `/data/chain_status.json` on pisky-api — `ChainStatusDto.kt`. No longer fetched
/// directly (endpoint retired); synthesized by `ChainStatusSynthesizer`. Each stage's `details` is
/// a free-form JSON object — the Pi shapes it per stage kind; the app reads the fields it needs.
struct ChainStatusDto: Decodable, Sendable {
    let ts: Double
    let site: String?
    let stages: [ChainStageDto]

    enum CodingKeys: String, CodingKey {
        case ts, site, stages
    }

    init(ts: Double = 0.0, site: String? = nil, stages: [ChainStageDto] = []) {
        self.ts = ts
        self.site = site
        self.stages = stages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ts = try c.decodeIfPresent(Double.self, forKey: .ts) ?? 0.0
        site = try c.decodeIfPresent(String.self, forKey: .site)
        stages = try c.decodeIfPresent([ChainStageDto].self, forKey: .stages) ?? []
    }
}

struct ChainStageDto: Decodable, Sendable {
    let name: String
    let kind: String
    let status: String
    /// Free-form per-stage detail map. Mirrors Kotlin's `JsonObject?`.
    let details: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case name, kind, status, details
    }

    init(name: String, kind: String, status: String, details: [String: JSONValue]? = nil) {
        self.name = name
        self.kind = kind
        self.status = status
        self.details = details
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(String.self, forKey: .kind)
        status = try c.decode(String.self, forKey: .status)
        details = try c.decodeIfPresent([String: JSONValue].self, forKey: .details)
    }

    // Typed detail accessors — port of ChainStageDto.detail{Double,Long,Int,String,Bool}.
    func detailDouble(_ key: String) -> Double? { details?[key]?.doubleValue }
    func detailLong(_ key: String) -> Int64? { details?[key]?.int64Value }
    func detailInt(_ key: String) -> Int? { detailLong(key).map(Int.init) }
    func detailString(_ key: String) -> String? {
        guard let el = details?[key], !el.isNull else { return nil }
        return el.stringValue
    }
    func detailBool(_ key: String) -> Bool? { details?[key]?.boolValue }
}

/// Minimal recursive JSON value — covers what `details` carries (null/bool/number/string and,
/// for completeness, nested arrays/objects). Used in place of kotlinx's `JsonElement`.
enum JSONValue: Decodable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let d = try? c.decode(Double.self) {
            self = .number(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            self = .null
        }
    }

    var isNull: Bool { self == .null }

    var doubleValue: Double? {
        switch self {
        case .number(let d): return d
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    var int64Value: Int64? {
        switch self {
        case .number(let d): return Int64(d)
        case .string(let s): return Int64(s)
        default: return nil
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let d):
            // Mirror kotlinx contentOrNull: numbers render without a trailing ".0" when integral.
            if d == d.rounded() && abs(d) < 9.007199254740992e15 { return String(Int64(d)) }
            return String(d)
        case .bool(let b): return String(b)
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}
