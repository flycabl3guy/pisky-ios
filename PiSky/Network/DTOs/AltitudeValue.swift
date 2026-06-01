import Foundation

/// `alt_baro` on the wire is either an integer (feet) or the string `"ground"`.
/// Ported from `AltitudeValue` + `AltitudeValueSerializer.kt`.
///
/// Kotlin's serializer: if the JSON is the string `"ground"` → `.ground`, otherwise
/// decode an int (falling back to `0` when not parseable as an int). Mirrored here.
enum AltitudeValue: Decodable, Equatable, Sendable {
    case feet(Int)
    case ground

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self), s == "ground" {
            self = .ground
            return
        }
        // Kotlin uses `json.intOrNull ?: 0` — coerce a Double (e.g. 12000.0) or
        // any non-"ground" value down to an Int, defaulting to 0.
        if let i = try? container.decode(Int.self) {
            self = .feet(i)
        } else if let d = try? container.decode(Double.self) {
            self = .feet(Int(d))
        } else {
            self = .feet(0)
        }
    }

    /// Feet value when airborne; `nil` when on the ground. Convenience for the mapper.
    var feetValue: Int? {
        if case let .feet(v) = self { return v }
        return nil
    }

    var isGround: Bool { self == .ground }
}
