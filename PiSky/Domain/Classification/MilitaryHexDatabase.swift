import Foundation

/// Verbatim port of `core/domain/model/MilitaryHexDatabase.kt`.
///
/// Known US military ICAO hex codes mapped to aircraft/unit names.
/// Hex values are lowercase without the 0x prefix.
///
/// US DoD primary block: AE0000–AFFFFF
/// Additional blocks: A00000–ADFFFF (some military registrations)
enum MilitaryHexDatabase {

    // ── Specific known airframes ──────────────────────────────────────────────

    static let hexToName: [String: String] = [

        // E-4B Nightwatch — National Airborne Operations Center
        "ae01ce": "E-4B Nightwatch (NAOC)",
        "ae01cf": "E-4B Nightwatch (NAOC)",
        "ae01d0": "E-4B Nightwatch (NAOC)",
        "ae01d1": "E-4B Nightwatch (NAOC)",

        // E-6B Mercury — Strategic Communications (VQ-3 / VQ-4)
        "adf7c0": "E-6B Mercury",
        "adf7c1": "E-6B Mercury",
        "adf7c2": "E-6B Mercury",
        "adf7c3": "E-6B Mercury",
        "adf7c4": "E-6B Mercury",
        "adf7c5": "E-6B Mercury",
        "adf7c6": "E-6B Mercury",
        "adf7c7": "E-6B Mercury",
        "adf7c8": "E-6B Mercury",
        "adf7c9": "E-6B Mercury",
        "adf7ca": "E-6B Mercury",
        "adf7cb": "E-6B Mercury",
        "adf7cc": "E-6B Mercury",
        "adf7cd": "E-6B Mercury",
        "adf7ce": "E-6B Mercury",
        "adf7cf": "E-6B Mercury",

        // E-3 Sentry — AWACS (552nd ACW, Tinker AFB OK)
        "ae0400": "E-3B/C Sentry (AWACS)",
        "ae0401": "E-3B/C Sentry (AWACS)",
        "ae0402": "E-3B/C Sentry (AWACS)",
        "ae0403": "E-3B/C Sentry (AWACS)",
        "ae0404": "E-3B/C Sentry (AWACS)",
        "ae0405": "E-3B/C Sentry (AWACS)",
        "ae0406": "E-3B/C Sentry (AWACS)",
        "ae0407": "E-3B/C Sentry (AWACS)",
        "ae0408": "E-3B/C Sentry (AWACS)",
        "ae0409": "E-3B/C Sentry (AWACS)",
        "ae040a": "E-3B/C Sentry (AWACS)",
        "ae040b": "E-3B/C Sentry (AWACS)",
        "ae040c": "E-3B/C Sentry (AWACS)",
        "ae040d": "E-3B/C Sentry (AWACS)",
        "ae040e": "E-3B/C Sentry (AWACS)",
        "ae040f": "E-3B/C Sentry (AWACS)",
        "ae0410": "E-3B/C Sentry (AWACS)",
        "ae0411": "E-3B/C Sentry (AWACS)",
        "ae0412": "E-3B/C Sentry (AWACS)",
        "ae0413": "E-3B/C Sentry (AWACS)",
        "ae0414": "E-3B/C Sentry (AWACS)",
        "ae0415": "E-3B/C Sentry (AWACS)",
        "ae0416": "E-3B/C Sentry (AWACS)",
        "ae0417": "E-3B/C Sentry (AWACS)",

        // RC-135 family — Offutt AFB NE (55th Wing)
        "ae01b8": "RC-135V/W Rivet Joint",
        "ae01b9": "RC-135V/W Rivet Joint",
        "ae01ba": "RC-135V/W Rivet Joint",
        "ae01bb": "RC-135V/W Rivet Joint",
        "ae01bc": "RC-135V/W Rivet Joint",
        "ae01bd": "RC-135V/W Rivet Joint",
        "ae01be": "RC-135V/W Rivet Joint",
        "ae01bf": "RC-135V/W Rivet Joint",
        "ae01c0": "RC-135S Cobra Ball",
        "ae01c1": "RC-135S Cobra Ball",
        "ae01c2": "RC-135S Cobra Ball",
        "ae01c3": "RC-135U Combat Sent",
        "ae01c4": "RC-135U Combat Sent",
        "ae01c5": "RC-135W Rivet Joint",
        "ae01c6": "WC-135 Constant Phoenix",
        "ae01c7": "WC-135 Constant Phoenix",
        "ae01c8": "OC-135B Open Skies",

        // E-8 JSTARS — 116th ACW, Robins AFB GA
        "ae0450": "E-8C JSTARS",
        "ae0451": "E-8C JSTARS",
        "ae0452": "E-8C JSTARS",
        "ae0453": "E-8C JSTARS",
        "ae0454": "E-8C JSTARS",
        "ae0455": "E-8C JSTARS",
        "ae0456": "E-8C JSTARS",
        "ae0457": "E-8C JSTARS",
        "ae0458": "E-8C JSTARS",
        "ae0459": "E-8C JSTARS",
        "ae045a": "E-8C JSTARS",
        "ae045b": "E-8C JSTARS",
        "ae045c": "E-8C JSTARS",
        "ae045d": "E-8C JSTARS",
        "ae045e": "E-8C JSTARS",
        "ae045f": "E-8C JSTARS",

        // VC-25A Air Force One (SAM 28000 / SAM 29000)
        "ae01f8": "VC-25A Air Force One",
        "ae01f9": "VC-25A Air Force One",

        // C-32A / C-40 VIP Transport — 89th Airlift Wing, Andrews
        "ae0200": "C-32A VIP Transport (89th AW)",
        "ae0201": "C-32A VIP Transport (89th AW)",
        "ae0202": "C-32A VIP Transport (89th AW)",
        "ae0203": "C-32A VIP Transport (89th AW)",
        "ae0204": "C-37A/B VIP Transport (89th AW)",
        "ae0205": "C-37A/B VIP Transport (89th AW)",
        "ae0206": "C-37A/B VIP Transport (89th AW)",
        "ae0207": "C-40B VIP Transport",
        "ae0208": "C-40B VIP Transport",
        "ae0209": "C-40C VIP Transport",
        "ae020a": "C-40C VIP Transport",

        // U-2S Dragon Lady — 9th RW, Beale AFB CA
        "ae0350": "U-2S Dragon Lady (9th RW)",
        "ae0351": "U-2S Dragon Lady (9th RW)",
        "ae0352": "U-2S Dragon Lady (9th RW)",
        "ae0353": "U-2S Dragon Lady (9th RW)",
        "ae0354": "U-2S Dragon Lady (9th RW)",
        "ae0355": "TU-2S Dragon Lady",
        "ae0356": "TU-2S Dragon Lady",

        // RQ-4 Global Hawk — 9th RW, Beale AFB CA
        "ae0360": "RQ-4B Global Hawk",
        "ae0361": "RQ-4B Global Hawk",
        "ae0362": "RQ-4B Global Hawk",
        "ae0363": "RQ-4B Global Hawk",
        "ae0364": "RQ-4B Global Hawk",
        "ae0365": "RQ-4B Global Hawk",

        // P-8A Poseidon — Navy patrol
        "ae0500": "P-8A Poseidon",
        "ae0501": "P-8A Poseidon",
        "ae0502": "P-8A Poseidon",
        "ae0503": "P-8A Poseidon",
        "ae0504": "P-8A Poseidon",
        "ae0505": "P-8A Poseidon",
        "ae0506": "P-8A Poseidon",
        "ae0507": "P-8A Poseidon",
        "ae0508": "P-8A Poseidon",
        "ae0509": "P-8A Poseidon",
        "ae050a": "P-8A Poseidon",
        "ae050b": "P-8A Poseidon",
        "ae050c": "P-8A Poseidon",
        "ae050d": "P-8A Poseidon",
        "ae050e": "P-8A Poseidon",
        "ae050f": "P-8A Poseidon",

        // E-2D Hawkeye — Navy AEW
        "ae0600": "E-2D Hawkeye",
        "ae0601": "E-2D Hawkeye",
        "ae0602": "E-2D Hawkeye",
        "ae0603": "E-2D Hawkeye",
        "ae0604": "E-2D Hawkeye",

        // C-130J / HC-130 — various wings
        "ae1000": "C-130J Super Hercules",
        "ae1001": "C-130J Super Hercules",
        "ae1002": "HC-130J Combat King II",
        "ae1003": "HC-130J Combat King II",
        "ae1004": "MC-130J Commando II",
        "ae1005": "MC-130J Commando II",
        "ae1006": "WC-130J Weather Recon",
        "ae1007": "WC-130J Weather Recon",

        // Miscellaneous USAF special mission
        "ae0800": "EC-130H Compass Call",
        "ae0801": "EC-130H Compass Call",
        "ae0802": "EC-130H Compass Call",
        "ae0803": "EC-130H Compass Call",
        "ae0804": "EC-130H Compass Call",
        "ae0805": "EC-130H Compass Call",
        "ae0806": "EC-130H Compass Call",
        "ae0807": "EC-130H Compass Call",

        // Navy E/A-18G Growler — Electronic Attack
        "ae0700": "EA-18G Growler",
        "ae0701": "EA-18G Growler",
        "ae0702": "EA-18G Growler",
        "ae0703": "EA-18G Growler",

        // USAF AFSOC
        "ae0900": "AC-130J Ghostrider",
        "ae0901": "AC-130J Ghostrider",
        "ae0902": "AC-130W Stinger II",
        "ae0903": "AC-130W Stinger II",
    ]

    // ── Callsign prefix → military unit / mission ─────────────────────────────

    // Only unambiguous military callsigns. Prefixes that collide with commercial
    // airline callsigns (SPIRIT=NKS, EAGLE=EGF, TIGER=TGW, CLIPPER=historic civil,
    // HORNET, SUPER, DUKE, SHARK, CARGO, IRON, TEAL, GUARD, PIKE, VIPER, HAWK,
    // BLADE, PANTHER, EVAC, MEDEVAC, WING, WOLF, COBRA, COMET, ORBIT, STRIKE, STEEL,
    // FURY, TORCH, MOOSE, PACK, NOBLE, ROCKY, HOMER, PEARL, JAKE, SPORT, BOXER,
    // KNIFE, DERBY, HOIST, TOPAZ, SLAM, TALON, GHOST, LANCE, ROOK, VADER, SKULL,
    // MAGMA, TROJAN, PUMA, HAVOC, DEMON, DUDE, HOOK, TROUT, CABAL, GOTHAM, MARLIN,
    // SIOUX, CHILI, OTIS, GOONY, TEAM, DUCE, BALL, MONDO, TANDM, SUPRT, GEARS,
    // CHAOS, ELVIS, FENIX, GUMP, MUSL, SHADO, NORSE, KANTO, REY, VENUS) are NOT
    // safe without a paired hex lookup — they cause false positives on civil traffic.
    static let callsignPrefixToUnit: [String: String] = [
        "RCH":    "Air Mobility Command (AMC)",
        "REACH":  "Air Mobility Command (AMC)",
        "SAM":    "Special Air Mission (VIP)",
        "SPAR":   "Special Air Mission (VIP)",
        "NAVY":   "US Navy",
        "ARMY":   "US Army",
        "CNV":    "US Navy",
        "BUFF":   "USAF B-52",
        "RAIDER": "USAF B-21",
        "RAIDR":  "USAF B-21",
        "LANCER": "USAF B-1",
        "RAPTOR": "USAF F-22",
        "THUD":   "USAF A-10",
        "HURON":  "USAF T-1A",
        "BLZR":   "T-38C Talon (Training)",
        "HRCLS":  "C-130J Super Hercules",
        "BATT":   "USAF (King Air ISR)",
        "BLCAT":  "USAF Recon (King Air)",
        "STGRY":  "USAF (King Air ISR)",
        "LDACE":  "V-22 Osprey",
        "GRYHK":  "V-22 Osprey (Gray Hawk)",
        "BRCAT":  "T-6A Texan II (Training)",
        "FFAB":   "UH-60 Black Hawk",
        "RDHK":   "UH-60 Black Hawk",
        "VVAB":   "UH-60 Black Hawk",
        "VVHR":   "UH-60 Black Hawk",
        "GATRS":  "US Army (AH-64)",
        "TOPCT":  "US Army",
        "PALEH":  "US Army",
        "DUSTY":  "US Army",
        "SGE":    "Army Aviation Training",
        "MNTNA":  "Military Transport",
        "SKED":   "UH-60 Black Hawk",
        "WRHRSE": "CH-53 Super Stallion",
        "SHWK":   "UH-60 Black Hawk",
        "FAMUS":  "USAF C-17",
        "PAT":    "US Army Priority Air Transport",
        "JAC":    "USAF Tower",
        "QPK":    "USAF Tower",
        "FAM":    "Mexican Air Force",
        "GAF":    "German Air Force",
        "SKYFL":  "Belgian Air Force",
    ]

    // ── ICAO type code → human-readable aircraft name ─────────────────────────

    static let icaoTypeToName: [String: String] = [
        // Fixed-wing transport / tanker
        "C017":  "C-17 Globemaster III",
        "C17":   "C-17 Globemaster III",
        "C5":    "C-5M Galaxy",
        "C5M":   "C-5M Galaxy",
        "C130":  "C-130 Hercules",
        "C13J":  "C-130J Super Hercules",
        "C130J": "C-130J Super Hercules",
        "C30J":  "C-130J Super Hercules",
        "KC135": "KC-135 Stratotanker",
        "K35R":  "KC-135R Stratotanker",
        "KC46A": "KC-46A Pegasus",
        "K46A":  "KC-46A Pegasus",
        "B762":  "Boeing 767 (USAF Transport)",
        "C12":   "C-12 Huron",
        "C12C":  "C-12C Huron",
        "C21":   "C-21A Learjet",
        "C21A":  "C-21A Learjet",
        "C40":   "C-40 Clipper",
        "C40B":  "C-40B Clipper",
        "C32":   "C-32A (757 VIP)",
        "C32A":  "C-32A (757 VIP)",
        "C37":   "C-37A (G550 VIP)",
        "C37A":  "C-37A (G550 VIP)",
        "C37B":  "C-37B (G550 VIP)",
        // Bombers
        "B52":   "B-52H Stratofortress",
        "B52H":  "B-52H Stratofortress",
        "B1":    "B-1B Lancer",
        "B1B":   "B-1B Lancer",
        "B2":    "B-2A Spirit",
        "B2A":   "B-2A Spirit",
        // Fighters
        "F16":   "F-16 Fighting Falcon",
        "F16C":  "F-16C Fighting Falcon",
        "F15":   "F-15 Eagle",
        "F15C":  "F-15C Eagle",
        "F15D":  "F-15D Eagle",
        "F15E":  "F-15E Strike Eagle",
        "F22":   "F-22A Raptor",
        "F22A":  "F-22A Raptor",
        "F35":   "F-35 Lightning II",
        "F35A":  "F-35A Lightning II",
        "F35B":  "F-35B Lightning II",
        "F35C":  "F-35C Lightning II",
        "A10":   "A-10 Thunderbolt II",
        "A10C":  "A-10C Thunderbolt II",
        "F18":   "F/A-18 Hornet",
        "F18C":  "F/A-18C Hornet",
        "F18D":  "F/A-18D Hornet",
        "F18E":  "F/A-18E Super Hornet",
        "F18F":  "F/A-18F Super Hornet",
        "EA18":  "EA-18G Growler",
        // ISR / Special mission
        "E3TF":  "E-3 Sentry (AWACS)",
        "E3CF":  "E-3 Sentry (AWACS)",
        "E8":    "E-8C JSTARS",
        "P8":    "P-8A Poseidon",
        "P8A":   "P-8A Poseidon",
        "U2":    "U-2S Dragon Lady",
        "RQ4":   "RQ-4B Global Hawk",
        "MQ9":   "MQ-9 Reaper",
        "MQ9A":  "MQ-9A Reaper",
        "MQ1":   "MQ-1 Predator",
        "E2":    "E-2D Hawkeye",
        "E2D":   "E-2D Hawkeye",
        "RC135": "RC-135 Rivet Joint",
        "WC135": "WC-135 Constant Phoenix",
        "E4":    "E-4B Nightwatch",
        "E6":    "E-6B Mercury",
        "VC25":  "VC-25A Air Force One",
        // Trainers
        "T38":   "T-38C Talon",
        "T38C":  "T-38C Talon",
        "HAWK":  "T-38C Talon",           // ICAO designator used at some bases
        "T6":    "T-6A Texan II",
        "T6A":   "T-6A Texan II",
        "TEX2":  "T-6A Texan II",
        "T1A":   "T-1A Jayhawk",
        "T45":   "T-45C Goshawk",
        // Rotary wing
        "H60":   "UH-60 Black Hawk",
        "UH60":  "UH-60 Black Hawk",
        "SH60":  "SH-60 Seahawk",
        "MH60":  "MH-60 Seahawk",
        "H47":   "CH-47 Chinook",
        "CH47":  "CH-47 Chinook",
        "H64":   "AH-64 Apache",
        "AH64":  "AH-64 Apache",
        "AH64D": "AH-64D Apache",
        "AH64E": "AH-64E Apache Guardian",
        "H53":   "CH-53 Super Stallion",
        "H53S":  "CH-53E Super Stallion",
        "MH53":  "MH-53E Sea Dragon",
        "EC45":  "UH-72A Lakota",
        "B212":  "UH-1N Twin Huey",
        "A139":  "AW-139",
        // Tiltrotor
        "V22":   "V-22 Osprey",
        "MV22":  "MV-22B Osprey",
        "CV22":  "CV-22B Osprey",
        // Misc
        "BE9L":  "C-12 King Air",
        "BE20":  "C-12 King Air 200",
        "R66":   "Robinson R66 (Army Training)",
        "GLF5":  "Gulfstream V (VIP/ISR)",
        "GLEX":  "Global Express (VIP/ISR)",
        "C27J":  "C-27J Spartan",
        "PC21":  "Pilatus PC-21 Trainer",
        "TWR":   "Ground Transponder",
    ]

    static func decodeIcaoType(_ icaoType: String?) -> String? {
        guard let icaoType = icaoType else { return nil }
        return icaoTypeToName[icaoType.uppercased()]
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /// Look up a specific hex code. Returns nil if not in the known list.
    static func lookupHex(_ hex: String) -> String? {
        hexToName[hex.lowercased()]
    }

    /// Look up a callsign prefix to get the military unit/mission type.
    static func lookupCallsign(_ callsign: String?) -> String? {
        guard let cs = callsign?.trimmingCharacters(in: .whitespaces).uppercased() else { return nil }
        // Try longest prefix match (up to 6 chars)
        let maxLen = min(cs.count, 7)
        if maxLen < 2 { return nil }
        for len in stride(from: maxLen, through: 2, by: -1) {
            if let unit = callsignPrefixToUnit[String(cs.prefix(len))] { return unit }
        }
        return nil
    }

    /// Returns a display name for a military aircraft.
    /// Priority: specific hex → ICAO type decode → callsign prefix unit → raw type → fallback
    static func resolveName(hex: String, callsign: String?, type: String?) -> String {
        lookupHex(hex)
            ?? decodeIcaoType(type)
            ?? lookupCallsign(callsign)
            ?? type.map { "Military (\($0.uppercased()))" }
            ?? "US Military"
    }
}
