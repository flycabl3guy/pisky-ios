import Foundation

/// Maps ICAO aircraft type designators to human-readable names.
/// Verbatim port of `core/domain/model/AircraftTypeNames.kt`.
enum AircraftTypeNames {

    /// ICAO aircraft type designator → human-readable name.
    static let names: [String: String] = [
        // ── US Military Fixed Wing ────────────────────────────────────────────────
        "A10":   "A-10 Thunderbolt II",
        "A10C":  "A-10C Thunderbolt II",
        "B1":    "B-1B Lancer",
        "B1B":   "B-1B Lancer",
        "B2":    "B-2 Spirit",
        "B21":   "B-21 Raider",
        "B52":   "B-52 Stratofortress",
        "B52H":  "B-52H Stratofortress",
        "C5":    "C-5 Galaxy",
        "C5M":   "C-5M Super Galaxy",
        "C12":   "C-12 Huron",
        "C17":   "C-17 Globemaster III",
        "C130":  "C-130 Hercules",
        "C130J": "C-130J Super Hercules",
        "C135":  "C-135 Stratolifter",
        "C146":  "C-146 Wolfhound",
        "E3":    "E-3 Sentry (AWACS)",
        "E3TF":  "E-3 Sentry (AWACS)",
        "E6":    "E-6B Mercury",
        "E8":    "E-8C JSTARS",
        "E8C":   "E-8C JSTARS",
        "E10":   "E-10A MC2A",
        "E11":   "E-11A BACN",
        "EA6":   "EA-6B Prowler",
        "EA18":  "EA-18G Growler",
        "F15":   "F-15 Eagle",
        "F15E":  "F-15E Strike Eagle",
        "F16":   "F-16 Fighting Falcon",
        "F16C":  "F-16C Fighting Falcon",
        "F18":   "F/A-18 Hornet",
        "F18C":  "F/A-18C Hornet",
        "F18S":  "F/A-18F Super Hornet",
        "F22":   "F-22 Raptor",
        "F35":   "F-35 Lightning II",
        "F35A":  "F-35A Lightning II",
        "F35B":  "F-35B Lightning II",
        "F35C":  "F-35C Lightning II",
        "F117":  "F-117 Nighthawk",
        "HC130": "HC-130 Combat King",
        "HH60":  "HH-60 Pave Hawk",
        "KC10":  "KC-10 Extender",
        "KC130": "KC-130 Hercules",
        "KC135": "KC-135 Stratotanker",
        "KC46":  "KC-46A Pegasus",
        "MC130": "MC-130 Combat Talon",
        "P3":    "P-3 Orion",
        "P8":    "P-8A Poseidon",
        "P8A":   "P-8A Poseidon",
        "RC135": "RC-135 Rivet Joint",
        "RQ4":   "RQ-4 Global Hawk",
        "SR71":  "SR-71 Blackbird",
        "T38":   "T-38 Talon",
        "T45":   "T-45 Goshawk",
        "U2":    "U-2 Dragon Lady",
        "WC135": "WC-135 Constant Phoenix",
        // ── US Military Rotary ────────────────────────────────────────────────────
        "AH1":   "AH-1Z Viper",
        "AH1Z":  "AH-1Z Viper",
        "AH64":  "AH-64 Apache",
        "CH46":  "CH-46 Sea Knight",
        "CH47":  "CH-47 Chinook",
        "CH53":  "CH-53 Sea Stallion",
        "MH60":  "MH-60 Black Hawk",
        "OH58":  "OH-58 Kiowa",
        "SH60":  "SH-60 Seahawk",
        "UH1":   "UH-1 Iroquois (Huey)",
        "UH60":  "UH-60 Black Hawk",
        // ── Tiltrotor ─────────────────────────────────────────────────────────────
        "V22":   "V-22 Osprey",
        "MV22":  "MV-22B Osprey",
        "CV22":  "CV-22B Osprey",
        // ── Other Military ────────────────────────────────────────────────────────
        "EUFI":  "Eurofighter Typhoon",
        "GRIF":  "Gripen",
        "RAFL":  "Rafale",
        "TORP":  "Tornado",
        "TYPHON": "Eurofighter Typhoon",
        "HAR":   "Harrier",
        "AV8":   "AV-8B Harrier II",
        "A400":  "Airbus A400M Atlas",
        "A400M": "Airbus A400M Atlas",
    ]

    /// `decodeAircraftType` in AircraftTypeNames.kt.
    /// Returns nil for nil/blank input; otherwise uppercases + trims and looks up.
    static func decode(_ code: String?) -> String? {
        guard let code = code else { return nil }
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        return names[trimmed.uppercased()]
    }
}
