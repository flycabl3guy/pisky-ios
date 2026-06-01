import Foundation

/// PiSky OTA military database response — `MilDbResponseDto.kt`. Endpoint is gone on PiAware
/// native (returns 404); callers treat that as "no DB". version/count/aircraft are required by the
/// Kotlin DTO, but kept lenient here so a partial body never throws.
struct MilDbResponseDto: Decodable, Sendable {
    let version: String
    let count: Int
    let aircraft: [MilDbEntryDto]

    enum CodingKeys: String, CodingKey {
        case version
        case count
        case aircraft
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        aircraft = try c.decodeIfPresent([MilDbEntryDto].self, forKey: .aircraft) ?? []
    }
}

struct MilDbEntryDto: Decodable, Sendable {
    let hex: String
    let desc: String?
    let ownOp: String?
    let type: String?
    let reg: String?

    enum CodingKeys: String, CodingKey {
        case hex = "h"
        case desc = "d"
        case ownOp = "o"
        case type = "t"
        case reg = "r"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hex = try c.decode(String.self, forKey: .hex)
        desc = try c.decodeIfPresent(String.self, forKey: .desc)
        ownOp = try c.decodeIfPresent(String.self, forKey: .ownOp)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        reg = try c.decodeIfPresent(String.self, forKey: .reg)
    }
}
