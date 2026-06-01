import Foundation

/// Wire shape of `skyaware/data/receiver.json` — `ReceiverDto` in ReceiverDto.kt.
struct ReceiverDto: Decodable, Sendable {
    let version: String
    let refresh: Int
    let history: Int
    let lat: Double?
    let lon: Double?
    let antenna: String?

    enum CodingKeys: String, CodingKey {
        case version
        case refresh
        case history
        case lat
        case lon
        case antenna
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? "unknown"
        refresh = try c.decodeIfPresent(Int.self, forKey: .refresh) ?? 1000
        history = try c.decodeIfPresent(Int.self, forKey: .history) ?? 0
        lat = try c.decodeIfPresent(Double.self, forKey: .lat)
        lon = try c.decodeIfPresent(Double.self, forKey: .lon)
        antenna = try c.decodeIfPresent(String.self, forKey: .antenna)
    }
}
