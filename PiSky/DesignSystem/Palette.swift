import SwiftUI

/// Hangar Luxe v6 palette — ported verbatim from `core/ui/theme/Color.kt`.
///
/// Namespaced under `Palette` (rather than extending `Color`) so the design's `cyan`/`brass`
/// names don't collide with SwiftUI's built-in `Color.cyan` etc. Reference as `Palette.background`.
enum Palette {

    // ── Surfaces — graphite stack ──────────────────────────────────────────
    static let background      = Color(hex: 0x0A0B0F)   // near-black, warm bias
    static let cardBackground  = Color(hex: 0x14161D)
    static let cardElevated    = Color(hex: 0x1C1F28)
    static let cardSheet       = Color(hex: 0x181B23)

    // ── Brand accents — brushed brass + cyan ───────────────────────────────
    static let brass        = Color(hex: 0xC9A961)
    static let brassBright  = Color(hex: 0xE3C682)
    static let brassDim     = Color(hex: 0x8A7440)
    static let brassShadow  = Color(hex: 0x3D341F)
    static let cyan         = Color(hex: 0x5BE5FF)
    static let cyanDim      = Color(hex: 0x2EA8C2)
    static let cyanGhost    = Color(hex: 0x1A4654)
    static let signalRed    = Color(hex: 0xFF3B30)
    static let signalAmberHot = Color(hex: 0xFFB300)

    // ── Legacy aliases (repointed to Hangar Luxe, kept for parity) ──────────
    static let platinumGold = brass
    static let piSkyGreen   = brassBright
    static let electricBlue = cyan
    static let skyBlue      = cyan
    static let purpleHigh   = Color(hex: 0x8E7CC8)

    // ── Text — bone palette ────────────────────────────────────────────────
    static let textPrimary   = Color(hex: 0xF2EFE6)
    static let textSecondary = Color(hex: 0xD8D5CC)
    static let textMuted     = Color(hex: 0x9C9A95)
    static let textGold      = brass

    // ── Glass / frosted ────────────────────────────────────────────────────
    static let glassBorder     = Color(hex: 0xD4B970, alpha: 0.24)
    static let glassBackground = Color(hex: 0xE3C682, alpha: 0.08)
    static let glassHighlight  = Color(hex: 0xF2EFE6, alpha: 0.10)  // top-edge sheen
    static let glassScrim      = Color(hex: 0x000000, alpha: 0.50)

    // ── M3 surface-container tiers (dark) ──────────────────────────────────
    static let surfaceContainerLowest  = Color(hex: 0x0E1015)
    static let surfaceContainerLow     = Color(hex: 0x14161D)
    static let surfaceContainer        = Color(hex: 0x1A1D24)
    static let surfaceContainerHigh    = Color(hex: 0x22262E)
    static let surfaceContainerHighest = Color(hex: 0x2A2E37)
    static let outline        = Color(hex: 0x2E323D)   // muted steel
    static let outlineVariant = Color(hex: 0x353944)
    static let scrim          = Color(hex: 0x000000, alpha: 0.80)
    static let inverseSurface = Color(hex: 0xE8E5DC)
    static let inversePrimary = brassDim

    // ── Status ─────────────────────────────────────────────────────────────
    static let statusOk      = Color(hex: 0x3DDC97)   // emerald
    static let statusWarn    = signalAmberHot
    static let statusError   = signalRed
    static let statusUnknown = Color(hex: 0x4A4E58)
    static let emergencyRed   = signalRed
    static let emergencyAmber = Color(hex: 0xFF8C00)

    // ── Altitude color bands (map / list / scope markers) ───────────────────
    static let altGround = Color(hex: 0x4A4E58)
    static let altLow    = statusOk            // < 5 000 ft
    static let altMid    = cyan                // 5 000–20 000 ft
    static let altHigh   = brass               // > 20 000 ft
    static let altMlat   = Color(hex: 0xB89A55)

    /// tar1090-style altitude ramp used by the Radar PPI (distinct from the list/map bands above):
    /// red < 5 k, amber < 10 k, cyan < 25 k, magenta < 38 k, pink ≥ 38 k.
    static func radarAltitude(_ altFt: Int?) -> Color {
        switch altFt {
        case .some(let a) where a < 0:      return statusError
        case .none:                          return statusError
        case .some(let a) where a < 5_000:   return statusError
        case .some(let a) where a < 10_000:  return statusWarn
        case .some(let a) where a < 25_000:  return Color(hex: 0x66E0FF)
        case .some(let a) where a < 38_000:  return Color(hex: 0xB088FF)
        default:                             return Color(hex: 0xFF80E0)
        }
    }

    /// Altitude band for the map/list markers (matches `altitudeColorArgb` in MapScreen.kt).
    static func altitudeBand(altFt: Int?, onGround: Bool, isMlat: Bool, emergency: Bool) -> Color {
        if emergency { return emergencyRed }
        if onGround  { return altGround }
        if isMlat    { return altMlat }
        switch altFt {
        case .none:                          return altLow
        case .some(let a) where a < 5_000:   return altLow
        case .some(let a) where a < 20_000:  return altMid
        default:                             return altHigh
        }
    }
}

extension Color {
    /// Hex initializer, e.g. `Color(hex: 0xC9A961)` or `Color(hex: 0xD4B970, alpha: 0.24)`.
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
