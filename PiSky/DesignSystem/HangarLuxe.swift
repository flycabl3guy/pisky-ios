import SwiftUI

/// Hangar Luxe design tokens — ported from `core/ui/theme/HangarLuxe.kt`.
/// Glass spec, corner radii, elevation shadows, motion curves, and the radar-sweep cadence.
enum HangarLuxe {

    enum Glass {
        static let border        = Palette.glassBorder
        static let fill          = Palette.glassBackground
        static let topHighlight  = Palette.glassHighlight
        static let scrim         = Palette.glassScrim
        static let borderHairline: CGFloat = 1.0
        static let borderActive:   CGFloat = 1.5
    }

    enum Radius {
        static let small:  CGFloat = 10
        static let medium: CGFloat = 16
        static let large:  CGFloat = 22
        static let hero:   CGFloat = 28
        static let sheet:  CGFloat = 32
        static let pill:   CGFloat = 999
    }

    /// Elevation → drop-shadow radius (the Compose elevation tiers, in dp/pt).
    enum Elevation {
        static let flat:   CGFloat = 0
        static let plate:  CGFloat = 4
        static let raised: CGFloat = 10
        static let hero:   CGFloat = 18
        static let sheet:  CGFloat = 24
    }

    /// Motion curves (cubic-bezier control points) + durations, mirroring the Compose easings.
    enum Motion {
        static func standard(_ d: Double = duration.normal)   -> Animation { .timingCurve(0.20, 0.00, 0.00, 1.00, duration: d) }
        static func enterSoft(_ d: Double = duration.settled) -> Animation { .timingCurve(0.05, 0.70, 0.10, 1.00, duration: d) }
        static func exit(_ d: Double = duration.quick)        -> Animation { .timingCurve(0.30, 0.00, 0.80, 0.15, duration: d) }
        static func emphasized(_ d: Double = duration.normal) -> Animation { .timingCurve(0.05, 0.70, 0.10, 1.00, duration: d) }

        enum duration {
            static let instant   = 0.080
            static let quick     = 0.180
            static let normal    = 0.280
            static let settled   = 0.420
            static let cinematic = 0.720
        }
    }

    /// Radar sweep cadence (shared by Home radar, PolarRose, scope overlays).
    enum Sweep {
        static let revolution: Double = 8.0      // seconds for a full 360°
        static let trailDegrees: Double = 72.0   // fading wedge behind the lead line
        static let lead  = Palette.cyan
        static let trail = Palette.cyanDim
        static let grid  = Palette.outline
        static let ping  = Palette.brassBright
    }
}

/// Quality color ramp (red → amber → green) for a 0…1 fraction — `qualityColor()` in AtlasHud.kt.
/// Used by integrity histograms, meters, and any "how good is this" coloring.
func qualityColor(_ fraction: Double) -> Color {
    let f = min(max(fraction, 0), 1)
    if f < 0.5 {
        // red → amber
        let t = f / 0.5
        return Color(.sRGB,
                     red: 1.0,
                     green: 0.23 + (0.70 - 0.23) * t,
                     blue: 0.19 * (1 - t),
                     opacity: 1)
    } else {
        // amber → green
        let t = (f - 0.5) / 0.5
        return Color(.sRGB,
                     red: 1.0 - (1.0 - 0.24) * t,
                     green: 0.70 + (0.86 - 0.70) * t,
                     blue: 0.0 + 0.59 * t,
                     opacity: 1)
    }
}
