import SwiftUI

/// Typography — ported from `core/ui/theme/{Type,Fonts}.kt`.
///
/// Three families: **Rajdhani** (display/nameplate), **Inter** (body), **JetBrains Mono**
/// (data values, callsigns, hex). Drop the `.ttf`s into `Resources/Fonts/` and register them via
/// `UIAppFonts`; if a family is missing, `Font.custom` falls back to the system font, and the
/// helpers below additionally fall back to a sensible system design so the UI never renders blank.
enum PSFontFamily {
    static let rajdhani = "Rajdhani"
    static let inter    = "Inter"
    static let mono     = "JetBrainsMono-Regular"

    /// True once at launch if the custom faces registered. Cheap heuristic used to pick fallbacks.
    static let rajdhaniAvailable = UIFont(name: rajdhani, size: 12) != nil
    static let interAvailable    = UIFont(name: inter, size: 12) != nil
    static let monoAvailable     = UIFont(name: mono, size: 12) != nil
}

extension Font {
    /// Rajdhani display face; falls back to system rounded.
    static func rajdhani(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        PSFontFamily.rajdhaniAvailable
            ? .custom(PSFontFamily.rajdhani, size: size).weight(weight)
            : .system(size: size, weight: weight, design: .rounded)
    }

    /// Inter body face; falls back to system default.
    static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        PSFontFamily.interAvailable
            ? .custom(PSFontFamily.inter, size: size).weight(weight)
            : .system(size: size, weight: weight, design: .default)
    }

    /// JetBrains Mono data face; falls back to system monospaced.
    static func psMono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        PSFontFamily.monoAvailable
            ? .custom(PSFontFamily.mono, size: size).weight(weight)
            : .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Semantic styles mirroring the Compose `Typography` scale. Tracking (letter-spacing) is not part
/// of `Font` on SwiftUI — apply the paired `tracking` constant on the `Text` with `.tracking(_:)`.
enum PSText {
    // Rajdhani — display / headline
    static let displayLarge  = Font.rajdhani(57, weight: .bold)
    static let displayMedium = Font.rajdhani(45, weight: .semibold)
    static let displaySmall  = Font.rajdhani(36, weight: .semibold)
    static let headlineLarge  = Font.rajdhani(32, weight: .semibold)
    static let headlineMedium = Font.rajdhani(28, weight: .semibold)
    static let headlineSmall  = Font.rajdhani(24, weight: .medium)

    // Inter — title / body
    static let titleLarge  = Font.inter(20, weight: .semibold)
    static let titleMedium = Font.inter(16, weight: .semibold)
    static let titleSmall  = Font.inter(14, weight: .medium)
    static let bodyLarge   = Font.inter(16)
    static let bodyMedium  = Font.inter(14)
    static let bodySmall   = Font.inter(12)

    // JetBrains Mono — labels / data
    static let labelLarge  = Font.psMono(14, weight: .medium)
    static let labelMedium = Font.psMono(12, weight: .medium)
    static let labelSmall  = Font.psMono(10, weight: .medium)

    enum Tracking {
        static let label: CGFloat   = 0.5
        static let labelWide: CGFloat = 1.0
        static let nameplate: CGFloat = 1.5
    }
}
