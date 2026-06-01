import Foundation

/// Decoders for readsb's `category` (emitter category) and `type` (message-source address-type).
/// Ported from `core/domain/model/AdsbCodes.kt`. Meanings per RTCA DO-260B §2.2.3.2.5.2.
enum AdsbCodes {

    /// ADS-B emitter category code ("A3") → human label.
    static func emitterCategory(_ code: String?) -> String {
        switch code?.uppercased() {
        case "A0", "B0", "C0", "D0", nil, "": return "—"
        case "A1": return "Light (< 15,500 lb)"
        case "A2": return "Small (15.5k–75k lb)"
        case "A3": return "Large (75k–300k lb)"
        case "A4": return "High-vortex large (B757)"
        case "A5": return "Heavy (≥ 300,000 lb)"
        case "A6": return "High performance"
        case "A7": return "Rotorcraft"
        case "B1": return "Glider / sailplane"
        case "B2": return "Lighter-than-air"
        case "B3": return "Parachutist"
        case "B4": return "Ultralight / hang-glider"
        case "B6": return "UAV / drone"
        case "B7": return "Space vehicle"
        case "C1": return "Emergency vehicle"
        case "C2": return "Service vehicle"
        case "C3": return "Point obstacle"
        case "C4": return "Cluster obstacle"
        case "C5": return "Line obstacle"
        default:   return "Reserved (\(code ?? "—"))"
        }
    }

    /// Short label for compact chips.
    static func emitterCategoryShort(_ code: String?) -> String {
        switch code?.uppercased() {
        case "A1": return "Light"; case "A2": return "Small"; case "A3": return "Large"
        case "A4": return "B757";  case "A5": return "Heavy"; case "A6": return "Hi-Perf"; case "A7": return "Rotor"
        case "B1": return "Glider"; case "B2": return "LTA"; case "B3": return "Chute"; case "B4": return "Ultralite"
        case "B6": return "UAV"; case "B7": return "Space"
        case "C1": return "Emerg"; case "C2": return "Service"; case "C3", "C4", "C5": return "Obstacle"
        default:   return "—"
        }
    }

    /// Message-source `type` → label + trust tier (0 = low … 3 = highest) + hasPosition.
    struct SourceType { let label: String; let trust: Int; let hasPosition: Bool }

    static func sourceType(_ type: String?) -> SourceType {
        switch type?.lowercased() {
        case "adsb_icao":      return SourceType(label: "ADS-B (ICAO)", trust: 3, hasPosition: true)
        case "adsb_icao_nt":   return SourceType(label: "ADS-B non-transponder", trust: 3, hasPosition: true)
        case "adsr_icao":      return SourceType(label: "ADS-R (relayed)", trust: 2, hasPosition: true)
        case "adsb_other":     return SourceType(label: "ADS-B (anon/PIA)", trust: 3, hasPosition: true)
        case "adsr_other":     return SourceType(label: "ADS-R (non-ICAO)", trust: 2, hasPosition: true)
        case "tisb_icao":      return SourceType(label: "TIS-B (ICAO)", trust: 1, hasPosition: true)
        case "tisb_other":     return SourceType(label: "TIS-B (non-ICAO)", trust: 1, hasPosition: true)
        case "tisb_trackfile": return SourceType(label: "TIS-B (radar)", trust: 1, hasPosition: true)
        case "adsc":           return SourceType(label: "ADS-C (satellite)", trust: 2, hasPosition: true)
        case "mlat":           return SourceType(label: "MLAT", trust: 2, hasPosition: true)
        case "mode_s":         return SourceType(label: "Mode S (no position)", trust: 0, hasPosition: false)
        case "mode_ac":        return SourceType(label: "Mode A/C", trust: 0, hasPosition: false)
        case "other":          return SourceType(label: "Other", trust: 0, hasPosition: false)
        default:               return SourceType(label: "Unknown", trust: 0, hasPosition: false)
        }
    }

    /// Friendly label for `aircraft_count_by_type` / `position_count_by_type` keys.
    static func typeKeyLabel(_ key: String) -> String {
        switch key {
        case "adsb_icao":      return "ADS-B"
        case "adsb_icao_nt":   return "ADS-B NT"
        case "adsr_icao":      return "ADS-R"
        case "tisb_icao":      return "TIS-B"
        case "tisb_other":     return "TIS-B oth"
        case "tisb_trackfile": return "TIS-B trk"
        case "adsc":           return "ADS-C"
        case "mlat":           return "MLAT"
        case "mode_s":         return "Mode S"
        case "mode_ac":        return "Mode A/C"
        case "adsb_other":     return "ADS-B anon"
        case "adsr_other":     return "ADS-R oth"
        case "other":          return "Other"
        case "unknown":        return "Unknown"
        default:               return key
        }
    }
}
