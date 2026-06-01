import Foundation

/// ADS-B position/velocity QUALITY decoder — RTCA DO-260B MOPS. Ported verbatim from
/// `core/domain/model/AdsbIntegrity.kt`. Every bound is a published standard value; an absent field
/// returns `.unknown` (the app never fabricates a bound). `quality` is a 0…1 UI color ramp only.
struct IntegrityLevel: Equatable, Sendable {
    let code: Int?
    let metric: String   // "NACp"
    let bound: String    // "< 30 m"
    let plain: String    // one-line meaning
    let quality: Float   // 0…1 for color ramps

    var isKnown: Bool { code != nil }
    static func unknown(_ metric: String) -> IntegrityLevel {
        IntegrityLevel(code: nil, metric: metric, bound: "—", plain: "Not reported", quality: 0)
    }
}

enum AdsbIntegrity {
    private static func q(_ code: Int, _ denom: Float) -> Float { min(max(Float(code) / denom, 0), 1) }

    /// NACp 0…11 → Estimated Position Uncertainty (95% horizontal).
    static func nacp(_ code: Int?) -> IntegrityLevel {
        guard let code else { return .unknown("NACp") }
        let bp: (String, String)
        switch code {
        case 11: bp = ("< 3 m", "RTK/SBAS-grade — trustworthy to a few metres")
        case 10: bp = ("< 10 m", "Excellent GNSS fix")
        case 9:  bp = ("< 30 m", "Very good GNSS")
        case 8:  bp = ("< 92.6 m (0.05 NM)", "Good GNSS — common compliant floor")
        case 7:  bp = ("< 185 m (0.1 NM)", "Fair")
        case 6:  bp = ("< 556 m (0.3 NM)", "Coarse")
        case 5:  bp = ("< 926 m (0.5 NM)", "Coarse")
        case 4:  bp = ("< 1.0 NM", "Poor")
        case 3:  bp = ("< 2.0 NM", "Poor")
        case 2:  bp = ("< 4.0 NM", "Very poor")
        case 1:  bp = ("< 10 NM", "Nearly useless for separation")
        default: bp = ("≥ 10 NM", "No usable accuracy reported")
        }
        return IntegrityLevel(code: code, metric: "NACp", bound: bp.0, plain: bp.1, quality: q(code, 11))
    }

    /// NIC 0…11 → Rc horizontal containment radius.
    static func nic(_ code: Int?) -> IntegrityLevel {
        guard let code else { return .unknown("NIC") }
        let bp: (String, String)
        switch code {
        case 11: bp = ("Rc < 7.5 m", "Tightest integrity bound")
        case 10: bp = ("Rc < 25 m", "Very tight")
        case 9:  bp = ("Rc < 75 m", "Tight")
        case 8:  bp = ("Rc < 185 m (0.1 NM)", "Good")
        case 7:  bp = ("Rc < 370 m (0.2 NM)", "Min for normal ATC use")
        case 6:  bp = ("Rc < 926 m (0.5 NM)", "Moderate")
        case 5:  bp = ("Rc < 1.0 NM", "Loose")
        case 4:  bp = ("Rc < 2.0 NM", "Loose")
        case 3:  bp = ("Rc < 4.0 NM", "Poor")
        case 2:  bp = ("Rc < 8.0 NM", "Poor")
        case 1:  bp = ("Rc < 20 NM", "Very poor")
        default: bp = ("Rc ≥ 20 NM", "No integrity bound reported")
        }
        return IntegrityLevel(code: code, metric: "NIC", bound: bp.0, plain: bp.1, quality: q(code, 11))
    }

    /// SIL 0…3 → probability the true position lies outside Rc.
    static func sil(_ code: Int?, silType: String?) -> IntegrityLevel {
        guard let code else { return .unknown("SIL") }
        let per: String
        switch silType?.lowercased() {
        case "persample": per = " per sample"
        case "perhour":   per = " per hour"
        default:          per = ""
        }
        let bp: (String, String)
        switch code {
        case 3: bp = ("≤ 1×10⁻⁷\(per)", "Required for separation — violated ≤ 1 in 10M")
        case 2: bp = ("≤ 1×10⁻⁵\(per)", "One in 100,000")
        case 1: bp = ("≤ 1×10⁻³\(per)", "One in 1,000 — weak")
        default: bp = ("Unknown", "No integrity guarantee")
        }
        return IntegrityLevel(code: code, metric: "SIL", bound: bp.0, plain: bp.1, quality: q(code, 3))
    }

    /// NACv 0…4 → horizontal velocity error (95%).
    static func nacv(_ code: Int?) -> IntegrityLevel {
        guard let code else { return .unknown("NACv") }
        let bp: (String, String)
        switch code {
        case 4: bp = ("< 0.3 m/s", "Best velocity accuracy")
        case 3: bp = ("< 1 m/s (1.9 kt)", "Very good")
        case 2: bp = ("< 3 m/s (5.8 kt)", "Good")
        case 1: bp = ("< 10 m/s (19 kt)", "Coarse")
        default: bp = ("≥ 10 m/s", "No usable velocity accuracy")
        }
        return IntegrityLevel(code: code, metric: "NACv", bound: bp.0, plain: bp.1, quality: q(code, 4))
    }

    /// SDA 0…3 → system design assurance (undetected-fault probability / flight hour).
    static func sda(_ code: Int?) -> IntegrityLevel {
        guard let code else { return .unknown("SDA") }
        let bp: (String, String)
        switch code {
        case 3: bp = ("Hazardous · ≤ 1×10⁻⁷/h", "Misleading data extremely improbable by design")
        case 2: bp = ("Major · ≤ 1×10⁻⁵/h", "Typical certified GPS+ADS-B install")
        case 1: bp = ("Minor · ≤ 1×10⁻³/h", "Low design assurance")
        default: bp = ("Unknown", "No assurance level reported")
        }
        return IntegrityLevel(code: code, metric: "SDA", bound: bp.0, plain: bp.1, quality: q(code, 3))
    }

    /// GVA 0…2 → geometric (GNSS) vertical accuracy (95%).
    static func gva(_ code: Int?) -> IntegrityLevel {
        guard let code else { return .unknown("GVA") }
        let bp: (String, String)
        switch code {
        case 2: bp = ("< 45 m", "Good geometric-altitude accuracy")
        case 1: bp = ("< 150 m", "Coarse geometric-altitude accuracy")
        default: bp = ("≥ 150 m", "No usable geometric-altitude accuracy")
        }
        return IntegrityLevel(code: code, metric: "GVA", bound: bp.0, plain: bp.1, quality: q(code, 2))
    }

    /// NICbaro 0/1 → barometric-altitude cross-check.
    static func nicBaro(_ code: Int?) -> IntegrityLevel {
        guard let code else { return .unknown("NICbaro") }
        return code >= 1
            ? IntegrityLevel(code: 1, metric: "NICbaro", bound: "Cross-checked",
                             plain: "Baro altitude passed an integrity cross-check", quality: 1)
            : IntegrityLevel(code: 0, metric: "NICbaro", bound: "Not checked",
                             plain: "Pressure altitude unverified", quality: 0.2)
    }

    static func versionName(_ v: Int?) -> String {
        switch v {
        case 0: return "DO-260 (v0, legacy)"
        case 1: return "DO-260A (v1)"
        case 2: return "DO-260B (v2)"
        case nil: return "—"
        default: return "v\(v!) (reserved)"
        }
    }

    static func versionShort(_ v: Int?) -> String {
        switch v {
        case 0: return "v0"; case 1: return "v1"; case 2: return "v2"
        case nil: return "—"; default: return "v\(v!)"
        }
    }
}
