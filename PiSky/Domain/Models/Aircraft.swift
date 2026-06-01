import Foundation

/// Source band — `DataSource` in Aircraft.kt.
enum DataSource: String, Codable, Sendable { case adsb1090, uat978 }

/// Emergency status — `Emergency` in Aircraft.kt. Derived from readsb's `emergency` string with a
/// squawk fallback (7500/7600/7700) for sources that only emit the raw code.
enum Emergency: String, Codable, Sendable, CaseIterable {
    case none, general, lifeguard, minfuel, nordo, unlawful, downed, reserved

    static func from(_ value: String?, squawk: String? = nil) -> Emergency {
        let byField: Emergency
        switch value?.lowercased() {
        case "general":   byField = .general
        case "lifeguard": byField = .lifeguard
        case "minfuel":   byField = .minfuel
        case "nordo":     byField = .nordo
        case "unlawful":  byField = .unlawful
        case "downed":    byField = .downed
        case "reserved":  byField = .reserved
        default:          byField = .none
        }
        if byField != .none { return byField }
        switch squawk?.trimmingCharacters(in: .whitespaces) {
        case "7500": return .unlawful
        case "7600": return .nordo
        case "7700": return .general
        default:     return .none
        }
    }
}

/// Domain aircraft — ported field-for-field from `core/domain/model/Aircraft.kt` (61 fields).
///
/// `operator` is a Swift keyword, so the Android `operator` field is named `operatorName` here.
/// Enrichable fields are `var` so the repository can layer in favorite/classification/route after
/// the initial decode (the Android mapper sets them at construction or via `.copy()`).
struct Aircraft: Identifiable, Equatable, Sendable {
    let hex: String
    var callsign: String?
    var registration: String?
    var type: String?
    var category: String?
    var squawk: String?
    var emergency: Emergency
    var latitude: Double?
    var longitude: Double?
    var altitudeBaro: Int?
    var altitudeGeom: Int?
    var groundSpeed: Double?
    var indicatedAirSpeed: Int?
    var trueAirSpeed: Int?
    var mach: Double?
    var track: Double?
    var trackRate: Double?
    var roll: Double?
    var verticalRate: Int?
    var geomRate: Int?
    var magHeading: Double?
    var trueHeading: Double?
    var navAltitudeMcp: Int?
    var navAltitudeFms: Int?
    var navHeading: Double?
    var navQnh: Double?
    var nic: Int?
    var nacP: Int?
    var nacV: Int?
    var sil: Int?
    var version: Int?
    var rc: Int?
    var nicBaro: Int?
    var silType: String?
    var gva: Int?
    var sda: Int?
    var rssi: Double?
    var seen: Double
    var seenPos: Double?
    var messages: Int
    var distanceNm: Double?
    var bearingDeg: Double?
    var isOnGround: Bool
    var isMlat: Bool
    var isTisb: Bool
    var isFavorite: Bool = false
    var dataSource: DataSource = .adsb1090
    var dbFlags: Int?
    var description: String?
    var operatorName: String?
    var year: String?
    var navModes: [String] = []
    var routeFrom: String?
    var routeTo: String?
    var classification: AircraftClassification = .unknown

    var id: String { hex }

    /// "KORD → KLAX" when both endpoints are enriched, else nil.
    var routeDisplay: String? {
        if let f = routeFrom, !f.isEmpty, let t = routeTo, !t.isEmpty { return "\(f) → \(t)" }
        return nil
    }

    /// Strict: only confirmed military (level == .military). LIKELY_MILITARY is excluded to keep
    /// GA/corporate false positives off the military views.
    var isMilitary: Bool { classification.level == .military }
    var isInteresting: Bool { (dbFlags ?? 0) & 0x02 != 0 }
    var isPia: Bool { (dbFlags ?? 0) & 0x04 != 0 }
    var isLadd: Bool { (dbFlags ?? 0) & 0x08 != 0 }
    var hasPosition: Bool { latitude != nil && longitude != nil }

    var displayCallsign: String {
        if let cs = callsign?.trimmingCharacters(in: .whitespaces), !cs.isEmpty { return cs }
        return hex.uppercased()
    }

    /// Human-readable type, falling back through enriched desc → military name → ICAO decode → raw.
    var typeDescription: String {
        if let d = description, !d.isEmpty { return d }
        if let m = classification.militaryName, !m.isEmpty { return m }
        if let decoded = AircraftTypeNames.decode(type), !decoded.isEmpty { return decoded }
        if isMilitary { return "Military Aircraft" }
        return type ?? "Unknown Aircraft"
    }

    var altitudeDisplay: String {
        if isOnGround { return "Ground" }
        if let a = altitudeBaro { return "\(Fmt.grouped(a)) ft" }
        return "—"
    }

    var speedDisplay: String {
        guard let gs = groundSpeed else { return "—" }
        return "\(Int(gs * 1.15078)) mph"
    }

    var verticalRateDisplay: String {
        guard let vr = verticalRate else { return "—" }
        if vr > 64  { return "↑ \(Fmt.grouped(vr)) fpm" }
        if vr < -64 { return "↓ \(Fmt.grouped(abs(vr))) fpm" }
        return "→ Level"
    }
}
