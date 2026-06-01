import Foundation

/// readsb `outline.json` — the receiver's actual coverage polygon — `OutlineDto.kt`.
/// Shape: `{ "actualRange": { "last24h": { "points": [[lat, lon, altFt], ...] } } }`.
struct OutlineDto: Decodable, Sendable {
    let actualRange: ActualRangeDto?

    enum CodingKeys: String, CodingKey {
        case actualRange
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        actualRange = try c.decodeIfPresent(ActualRangeDto.self, forKey: .actualRange)
    }
}

struct ActualRangeDto: Decodable, Sendable {
    let last24h: RangeWindowDto?

    enum CodingKeys: String, CodingKey {
        case last24h
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        last24h = try c.decodeIfPresent(RangeWindowDto.self, forKey: .last24h)
    }
}

struct RangeWindowDto: Decodable, Sendable {
    /// Each point is a 3-element array `[latitude, longitude, altitudeFeet]`.
    let points: [[Double]]

    enum CodingKeys: String, CodingKey {
        case points
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = try c.decodeIfPresent([[Double]].self, forKey: .points) ?? []
    }
}
