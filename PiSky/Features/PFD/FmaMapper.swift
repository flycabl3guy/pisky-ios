import Foundation

/// FMA cell state per Boeing FCOM convention.
///  - engaged (green) text in upper row
///  - armed   (white) text in lower row (smaller)
///  - caution (amber) text used for SINGLE CH / NO AUTOLAND / TCAS
///
/// Empty string in either field renders blank.
///
/// Ports `feature/pfd/FmaMapper.kt`.
struct FmaCell: Equatable {
    var engaged: String = ""
    var armed:   String = ""
    var caution: String = ""
}

struct FmaState: Equatable {
    let autothrottle: FmaCell
    let roll:         FmaCell
    let pitch:        FmaCell
    let apStatus:     FmaCell
    /// True when the underlying source emits zero target-state data; the strip
    /// should annunciate "NO MODE DATA" in amber per the no-fabricated-data
    /// rule (DO-260B TSS subtype 1 is not broadcast by older transponders).
    let noData:       Bool
}

/// Maps the six readsb nav_modes strings (`autopilot`, `vnav`, `althold`,
/// `approach`, `lnav`, `tcas`) plus MCP target fields to a 737-style FMA.
///
/// readsb→Boeing mapping table:
///   nav_modes "autopilot"                → AP status     CMD            (green)
///   nav_modes "lnav"                     → Roll engaged  LNAV           (green)
///   nav_modes "vnav"                     → Pitch engaged VNAV PTH       (green) — can't infer PTH vs SPD
///   nav_modes "althold"                  → Pitch engaged ALT HOLD       (green) — wins over vnav
///   nav_modes "approach" w/ lnav         → Roll engaged  LNAV    + Pitch armed G/S
///   nav_modes "approach" no lnav         → Roll engaged  VOR/LOC + Pitch armed G/S
///   nav_modes "tcas"                     → Pitch caution TCAS           (amber)
///
/// Implied from MCP fields (armed/white only — not "engaged" because we can't
/// confirm capture from the broadcast):
///   nav_heading present, no lnav         → Roll armed    HDG SEL
///   nav_altitude_mcp present, no vnav    → Pitch armed   ALT
enum FmaMapper {

    static func derive(_ aircraft: Aircraft) -> FmaState {
        let modes = Set(aircraft.navModes)
        let hasNavData = !modes.isEmpty
            || aircraft.navAltitudeMcp != nil
            || aircraft.navHeading != nil
            || aircraft.navQnh != nil

        // ── AP status column ────────────────────────────────────────────────
        let apStatus: FmaCell
        if modes.contains("autopilot") {
            apStatus = FmaCell(engaged: "CMD")
        } else if hasNavData {
            apStatus = FmaCell(engaged: "FD")   // assume FD-only when MCP refs present
        } else {
            apStatus = FmaCell()
        }

        // ── Roll (lateral) column ───────────────────────────────────────────
        let roll: FmaCell
        if modes.contains("lnav") {
            roll = FmaCell(engaged: "LNAV")
        } else if modes.contains("approach") {
            roll = FmaCell(engaged: "VOR/LOC")
        } else if aircraft.navHeading != nil {
            roll = FmaCell(engaged: "HDG SEL")
        } else {
            roll = FmaCell()
        }

        // ── Pitch (vertical) column ─────────────────────────────────────────
        let pitchEngaged: String
        if modes.contains("althold") {
            pitchEngaged = "ALT HOLD"
        } else if modes.contains("vnav") {
            pitchEngaged = "VNAV PTH"
        } else {
            pitchEngaged = ""
        }
        let pitchArmed: String
        if modes.contains("approach") {
            pitchArmed = "G/S"
        } else if aircraft.navAltitudeMcp != nil && pitchEngaged.isEmpty {
            pitchArmed = "ALT"
        } else {
            pitchArmed = ""
        }
        let pitchCaution = modes.contains("tcas") ? "TCAS" : ""
        let pitch = FmaCell(engaged: pitchEngaged, armed: pitchArmed, caution: pitchCaution)

        // ── Autothrottle column ─────────────────────────────────────────────
        // readsb nav_modes carries no autothrottle data. Leave blank rather
        // than fabricate a state.
        let autothrottle = FmaCell()

        let noData = !hasNavData
        return FmaState(autothrottle: autothrottle, roll: roll, pitch: pitch, apStatus: apStatus, noData: noData)
    }
}
