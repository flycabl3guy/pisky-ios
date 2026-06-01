import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Boeing 737NG / MAX PFD color set per AC 25-11A Color Set 1.
// Boeing names colors, not RGBs — these hex values are the sim-industry
// consensus (PMDG / Zibo / IXEG) validated against real flight-deck photos.
// Six coding colors total (white, green, magenta, cyan, amber, red) — DO-257A
// limit — plus sky/ground/black as scene fill which don't count toward the cap.
//
// Ports `feature/pfd/PfdColors.kt`. Uses the project `Color(hex:)` (UInt32)
// initializer from DesignSystem/Palette.swift.
// ─────────────────────────────────────────────────────────────────────────────

enum PfdColors {
    static let background  = Color(hex: 0x000000)
    static let white       = Color(hex: 0xFFFFFF)
    static let green       = Color(hex: 0x10E010)
    static let magenta     = Color(hex: 0xFF14FF)
    static let cyan        = Color(hex: 0x00E5FF)
    static let amber       = Color(hex: 0xFFAA00)
    static let red         = Color(hex: 0xFF0000)
    static let sky         = Color(hex: 0x1C7BBF)
    static let ground      = Color(hex: 0x8B5A2B)
    static let chevronFill = Color(hex: 0x000000)
    static let chevronEdge = Color(hex: 0xFFFFFF)

    /// Tape background — slightly lifted off pure black so the boundary reads.
    static let tapePanel   = Color(hex: 0x101418)

    /// FMA cell border default (subtle gray) — turns green for the 10-second
    /// mode-change highlight per Boeing FCOM convention.
    static let fmaBorder   = Color(hex: 0x353944)

    /// SpeedTape header gray (Kotlin Color(0xFF6E7480)).
    static let headerGray  = Color(hex: 0x6E7480)
}
