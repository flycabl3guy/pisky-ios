import Foundation

// ════════════════════════════════════════════════════════════════════════════
// FINAL Swift `classify` signature (for the DTO→domain mapper to call):
//
//   AircraftClassifier.classify(
//       hex: String,
//       callsign: String?,
//       type: String?,
//       category: String?,
//       registration: String?,
//       dbFlags: Int?,
//       squawk: String?,
//       isInMilCsv: Bool = false,
//       milCsvName: String? = nil,
//       desc: String? = nil,
//       ownOp: String? = nil
//   ) -> AircraftClassification
//
// ════════════════════════════════════════════════════════════════════════════

/// Two-layer military aircraft classification engine.
/// Verbatim port of `core/domain/model/AircraftClassifier.kt`.
///
/// **Layer 1 — Deterministic (fast path):** O(1) lookups that return immediately
/// with high-confidence results. Safe to run inline during DTO→domain mapping.
///
/// **Layer 2 — Heuristic (scored):** Weighted scoring of multiple signals.
/// Runs in the same call but only reached if Layer 1 doesn't match.
///
/// Thread-safe: all data is in immutable statics.
enum AircraftClassifier {

    // ════════════════════════════════════════════════════════════════════
    // PUBLIC API
    // ════════════════════════════════════════════════════════════════════

    /// Classify a single aircraft. Called once per aircraft per poll cycle.
    /// All parameters come directly from AircraftDto / readsb JSON fields.
    ///
    /// - Parameter isInMilCsv: true if the hex was found in us_military_aircraft.csv asset.
    ///   This is resolved by the type repository and passed in at the mapping layer.
    static func classify(
        hex: String,
        callsign: String?,
        type: String?,
        category: String?,
        registration: String?,
        dbFlags: Int?,
        squawk: String?,
        isInMilCsv: Bool = false,
        milCsvName: String? = nil,
        desc: String? = nil,
        ownOp: String? = nil
    ) -> AircraftClassification {

        // ── Layer 1: Deterministic (any hit → immediate return) ─────

        // Edge case: PIA (Privacy ICAO Address) — rotating hex, skip hex-range checks
        let isPia = dbFlags != nil && (dbFlags! & 4) != 0
        // Edge case: non-ICAO hex (TIS-B relayed) — hex starts with ~, skip range checks
        let isNonIcao = hex.hasPrefix("~")

        // R1: readsb dbFlags bit 0 = military (Mictronics DB, ~180K entries)
        // Still trust dbFlags mil bit even for PIA — readsb resolves the real identity
        if let flags = dbFlags, (flags & 1) != 0 {
            return AircraftClassification(
                level: .military,
                confidence: 1.0,
                source: .readsbDbFlags,
                militaryName: desc?.nilIfBlank
                    ?? MilitaryHexDatabase.resolveName(hex: hex, callsign: callsign, type: type),
                militaryUnit: ownOp?.nilIfBlank
            )
        }

        // R2: Exact known hex code (curated DB in MilitaryHexDatabase)
        if let hexName = MilitaryHexDatabase.lookupHex(hex) {
            return AircraftClassification(
                level: .military,
                confidence: 1.0,
                source: .hexExactMatch,
                militaryName: hexName
            )
        }

        // If readsb gave us dbFlags and bit 0 is NOT set, it actively says "not military".
        // Trust that over CSV/OTA lookups (prevents LADD/privacy aircraft false positives).
        let readsbSaysNotMil = dbFlags != nil && (dbFlags! & 1) == 0

        // R2b: Found in military CSV/OTA database
        // Skip if readsb actively says "not military" (e.g. LADD-flagged private jets)
        if isInMilCsv && !readsbSaysNotMil {
            return AircraftClassification(
                level: .military,
                confidence: 0.98,
                source: .hexExactMatch,
                militaryName: desc?.nilIfBlank
                    ?? milCsvName?.nilIfBlank
                    ?? MilitaryHexDatabase.resolveName(hex: hex, callsign: callsign, type: type),
                militaryUnit: ownOp?.nilIfBlank
            )
        }

        // R3+R4: Military ICAO hex ranges (sourced from tar1090/Mictronics ranges.js)
        // Skip for PIA/non-ICAO addresses, and defer to readsb dbFlags when available
        let hexLong = Int(hex.lowercased().drop(while: { $0 == "~" }), radix: 16)
        if !readsbSaysNotMil, !isPia, !isNonIcao, let hexLong = hexLong {
            if let country = militaryRangeCountry(hexLong) {
                let isUs = country == "US DoD"
                let resolvedName: String
                if let d = desc?.nilIfBlank {
                    resolvedName = d
                } else if isUs {
                    resolvedName = MilitaryHexDatabase.resolveName(hex: hex, callsign: callsign, type: type)
                } else if let t = type?.uppercased() {
                    resolvedName = "Military (\(t))"
                } else {
                    resolvedName = "Military Aircraft"
                }
                return AircraftClassification(
                    level: .military,
                    confidence: 0.95,
                    source: .hexRangeMatch,
                    militaryName: resolvedName,
                    militaryUnit: ownOp?.nilIfBlank ?? country
                )
            }
        }

        // ── Layer 2: Heuristic scoring ──────────────────────────────

        var score: Float = 0
        var bestSource: ClassificationSource = .none
        var resolvedName: String? = desc?.nilIfBlank
        var resolvedUnit: String? = ownOp?.nilIfBlank

        // R5: Callsign prefix
        if let csUnit = MilitaryHexDatabase.lookupCallsign(callsign) {
            score += 0.85
            bestSource = .callsignPrefix
            resolvedUnit = csUnit
            resolvedName = MilitaryHexDatabase.resolveName(hex: hex, callsign: callsign, type: type)
        }

        // R6: Known military ICAO type code
        let upperType = type?.uppercased().trimmingCharacters(in: .whitespaces)
        if let upperType = upperType {
            let typeScore: Float
            if MILITARY_ONLY_TYPES.contains(upperType) {
                typeScore = 0.80  // exclusively military (F-16, C-17, etc.)
            } else if MILITARY_DUAL_TYPES.contains(upperType) {
                typeScore = 0.30  // dual-use (King Air, Gulfstream, etc.)
            } else {
                typeScore = 0
            }
            if typeScore > 0 {
                score += typeScore
                if bestSource == .none {
                    bestSource = .icaoTypeCode
                }
                if resolvedName == nil {
                    resolvedName = MilitaryHexDatabase.decodeIcaoType(type)
                        ?? AircraftTypeNames.names[upperType]
                }
            }
        }

        // R7: Emitter category B6 = UAV
        if category == "B6" {
            score += 0.50
            if bestSource == .none {
                bestSource = .emitterCategory
            }
        }

        // R8: Missing registration (weak signal)
        if (registration?.isBlank ?? true) && callsign != nil {
            score += 0.20
        }

        // R9: Callsign pattern — military-style (2-5 alpha + 2-4 digits, no airline match)
        let cs = callsign?.trimmingCharacters(in: .whitespaces).uppercased()
        if let cs = cs, Self.matchesMilitaryCallsign(cs), !isLikelyAirlineCallsign(cs) {
            score += 0.15
        }

        // R10: Military squawk codes
        if let squawk = squawk, MILITARY_SQUAWKS.contains(squawk) {
            score += 0.30
            if bestSource == .none {
                bestSource = .multiSignal
            }
        }

        // ── Threshold classification ────────────────────────────────

        if score > 0 && bestSource == .none {
            bestSource = .multiSignal
        }

        if score >= 0.80 {
            return AircraftClassification(
                level: .military, confidence: score, source: bestSource,
                militaryName: resolvedName, militaryUnit: resolvedUnit
            )
        } else if score >= 0.50 {
            return AircraftClassification(
                level: .likelyMilitary, confidence: score, source: bestSource,
                militaryName: resolvedName, militaryUnit: resolvedUnit
            )
        } else if score > 0 {
            return AircraftClassification(
                level: .unknown, confidence: score, source: bestSource,
                militaryName: resolvedName, militaryUnit: resolvedUnit
            )
        } else {
            return AircraftClassification.civilian
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // LOOKUP DATA (all immutable, thread-safe)
    // ════════════════════════════════════════════════════════════════════

    /// Military ICAO hex ranges — sourced from tar1090/Mictronics ranges.js.
    /// These are the same ranges tar1090's "U" (military) filter uses.
    private struct MilRange {
        let range: ClosedRange<Int>
        let country: String
    }

    private static let MILITARY_HEX_RANGES: [MilRange] = [
        // US DoD
        MilRange(range: 0xADF7C8...0xAFFFFF, country: "US DoD"),
        // Algeria
        MilRange(range: 0x010070...0x01008F, country: "Algeria"),
        // Egypt
        MilRange(range: 0x0A4000...0x0A4FFF, country: "Egypt"),
        // Libya
        MilRange(range: 0x33FF00...0x33FFFF, country: "Libya"),
        // Italy (AMI)
        MilRange(range: 0x350000...0x37FFFF, country: "Italy (AMI)"),
        // France (Armée de l'Air)
        MilRange(range: 0x3AA000...0x3AFFFF, country: "France"),
        MilRange(range: 0x3B7000...0x3BFFFF, country: "France"),
        // Hungary
        MilRange(range: 0x3EA000...0x3EBFFF, country: "Hungary"),
        // Germany (Luftwaffe)
        MilRange(range: 0x3F4000...0x3FBFFF, country: "Germany"),
        // Monaco
        MilRange(range: 0x400000...0x40003F, country: "Monaco"),
        // UK (RAF)
        MilRange(range: 0x43C000...0x43CFFF, country: "UK (RAF)"),
        // Belgium
        MilRange(range: 0x444000...0x446FFF, country: "Belgium"),
        MilRange(range: 0x44F000...0x44FFFF, country: "Belgium"),
        // Denmark
        MilRange(range: 0x457000...0x457FFF, country: "Denmark"),
        // Finland
        MilRange(range: 0x45F400...0x45F4FF, country: "Finland"),
        // Greece
        MilRange(range: 0x468000...0x4683FF, country: "Greece"),
        // Croatia
        MilRange(range: 0x473C00...0x473C0F, country: "Croatia"),
        // Netherlands
        MilRange(range: 0x478100...0x4781FF, country: "Netherlands"),
        MilRange(range: 0x480000...0x480FFF, country: "Netherlands"),
        // Norway
        MilRange(range: 0x48D800...0x48D87F, country: "Norway"),
        // Poland
        MilRange(range: 0x497C00...0x497CFF, country: "Poland"),
        MilRange(range: 0x498420...0x49842F, country: "Poland"),
        // Turkey
        MilRange(range: 0x4B7000...0x4B7FFF, country: "Turkey"),
        MilRange(range: 0x4B8200...0x4B82FF, country: "Turkey"),
        // Maldives
        MilRange(range: 0x70C070...0x70C07F, country: "Maldives"),
        // Thailand
        MilRange(range: 0x710258...0x71028F, country: "Thailand"),
        MilRange(range: 0x710380...0x71039F, country: "Thailand"),
        // Israel (IDF)
        MilRange(range: 0x738A00...0x738AFF, country: "Israel (IDF)"),
        // Australia (RAAF)
        MilRange(range: 0x7CF800...0x7CFAFF, country: "Australia (RAAF)"),
        // India
        MilRange(range: 0x800200...0x8002FF, country: "India"),
        // Canada (RCAF)
        MilRange(range: 0xC20000...0xC3FFFF, country: "Canada (RCAF)"),
        // Brazil
        MilRange(range: 0xE40000...0xE41FFF, country: "Brazil"),
    ]

    private static func militaryRangeCountry(_ hexLong: Int) -> String? {
        for mr in MILITARY_HEX_RANGES where mr.range.contains(hexLong) {
            return mr.country
        }
        return nil
    }

    /// Exclusively military type codes — no civilian variant exists. Score: 0.80
    private static let MILITARY_ONLY_TYPES: Set<String> = [
        // Fighters
        "A10", "A10C", "AV8", "EA18", "F15", "F15C", "F15D", "F15E",
        "F16", "F16C", "F18", "F18C", "F18D", "F18E", "F18F", "F18S",
        "F22", "F22A", "F35", "F35A", "F35B", "F35C", "F117",
        // Bombers
        "B1", "B1B", "B2", "B2A", "B21", "B52", "B52H",
        // Military-only transport / tanker
        "C5", "C5M", "C17", "C017", "C27J", "C135", "C146",
        "KC10", "KC46", "K46A", "KC130", "KC135", "K35R",
        "HC130", "MC130", "HH60",
        // ISR / Special mission
        "E2", "E2D", "E3", "E3TF", "E3CF", "E4", "E6", "E8", "E8C",
        "E10", "E11", "EA6",
        "P8", "P8A", "RC135", "WC135", "U2",
        "RQ4", "MQ1", "MQ9", "MQ9A",
        "VC25",
        // Military trainers
        "T38", "T38C", "T45",
        // Military rotary (no civilian variant)
        "AH64", "AH64D", "AH64E", "AH1", "AH1Z", "OH58",
        "MH60", "SH60", "MH53", "CH53",
        // Tiltrotor
        "V22", "MV22", "CV22",
        // Foreign military-only
        "EUFI", "GRIF", "RAFL", "TORP", "TYPHON", "HAR", "A400", "A400M",
    ]

    /// Dual-use types — military AND civilian variants exist. Score: 0.30
    private static let MILITARY_DUAL_TYPES: Set<String> = [
        // Military designations of civilian airframes
        "C12", "C12C", "C21", "C21A", "C32", "C32A", "C37", "C37A", "C37B",
        "C40", "C40B", "C130", "C130J", "C13J", "C30J",
        "P3", "T1A", "T6", "T6A", "TEX2", "PC21",
        // Civilian types heavily used by military
        "BE20", "BE9L", "B212", "GLF5", "GLEX", "R66", "EC45", "A139",
        // Rotary with civilian variants
        "H60", "UH60", "H47", "CH47", "H53", "H53S",
        "H64", "CH46", "UH1",
    ]

    /// Military squawk codes.
    private static let MILITARY_SQUAWKS: Set<String> = {
        var s = Set<String>()
        // US military intercept range 4400-4477
        for i in 4400...4477 { s.insert(String(i)) }
        s.insert("7777") // military-only
        return s
    }()

    /// Military-style callsign check: 2-5 alpha followed by 2-4 digits.
    /// Equivalent of Kotlin's `Regex("^[A-Z]{2,5}\\d{2,4}$")`.
    private static func matchesMilitaryCallsign(_ cs: String) -> Bool {
        let chars = Array(cs)
        var i = 0
        var alpha = 0
        // Input is already uppercased by the caller; match only A-Z.
        while i < chars.count, chars[i] >= "A", chars[i] <= "Z" {
            alpha += 1
            i += 1
        }
        guard alpha >= 2 && alpha <= 5 else { return false }
        var digits = 0
        while i < chars.count, chars[i] >= "0" && chars[i] <= "9" {
            digits += 1
            i += 1
        }
        guard digits >= 2 && digits <= 4 else { return false }
        return i == chars.count
    }

    /// Quick check: does this callsign look like a commercial airline?
    private static func isLikelyAirlineCallsign(_ cs: String) -> Bool {
        if cs.count < 4 { return false }
        let prefix3 = String(cs.prefix(3))
        // Common US/EU airline 3-letter ICAO codes
        return COMMON_AIRLINE_PREFIXES.contains(prefix3)
    }

    private static let COMMON_AIRLINE_PREFIXES: Set<String> = [
        "AAL", "UAL", "DAL", "SWA", "JBU", "ASA", "NKS", "FFT", "SKW",
        "RPA", "ENY", "PDT", "ASH", "JIA", "CPZ", "EJA", "LXJ", "EGF",
        "BAW", "DLH", "AFR", "KLM", "ACA", "QFA", "SIA", "CPA", "ANA",
        "JAL", "KAL", "UAE", "ETH", "THY", "VOI", "RYR", "EZY", "WZZ",
        "FDX", "UPS", "GTI", "ABX", "CLX",
    ]
}

// ── Small string helpers mirroring Kotlin's ifBlank/isNullOrBlank semantics ──

private extension String {
    /// Kotlin `isBlank()` — true when empty or only whitespace.
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Kotlin `ifBlank { null }` — returns nil when blank, else self.
    var nilIfBlank: String? { isBlank ? nil : self }
}
