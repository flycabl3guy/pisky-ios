import Foundation

/// ICAO24 hex prefix → country flag emoji.
/// Verbatim port of `core/domain/model/HexCountry.kt`.
///
/// Ranges taken from ICAO Annex 10 Vol III allocations — covers the majority
/// of traffic; unknowns return nil (caller hides the flag).
///
/// The Kotlin source stores each flag as a pair of UTF-16 surrogate escapes
/// (e.g. `"🇺🇸"`); those encode the regional-indicator
/// emoji used directly below.
enum HexCountry {

    struct Range: Sendable {
        let start: Int
        let end: Int
        let flag: String
    }

    /// Ordered roughly by frequency at a US site to short-circuit quickly.
    static let ranges: [Range] = [
        Range(start: 0xA00000, end: 0xAFFFFF, flag: "🇺🇸"), // US
        Range(start: 0xC00000, end: 0xC3FFFF, flag: "🇨🇦"), // Canada
        Range(start: 0xF00000, end: 0xF07FFF, flag: "🇲🇽"), // Mexico
        Range(start: 0x400000, end: 0x43FFFF, flag: "🇬🇧"), // UK
        Range(start: 0x3C0000, end: 0x3FFFFF, flag: "🇩🇪"), // Germany
        Range(start: 0x380000, end: 0x3BFFFF, flag: "🇫🇷"), // France
        Range(start: 0x300000, end: 0x33FFFF, flag: "🇮🇹"), // Italy
        Range(start: 0x340000, end: 0x37FFFF, flag: "🇪🇸"), // Spain
        Range(start: 0x7C0000, end: 0x7FFFFF, flag: "🇦🇺"), // Australia
        Range(start: 0x480000, end: 0x4B7FFF, flag: "🇳🇱"), // Netherlands
        Range(start: 0x4A0000, end: 0x4A7FFF, flag: "🇸🇪"), // Sweden
        Range(start: 0x4B8000, end: 0x4BFFFF, flag: "🇨🇭"), // Switzerland
        Range(start: 0x440000, end: 0x447FFF, flag: "🇦🇹"), // Austria
        Range(start: 0x448000, end: 0x44FFFF, flag: "🇧🇪"), // Belgium
        Range(start: 0x450000, end: 0x457FFF, flag: "🇧🇬"), // Bulgaria
        Range(start: 0x458000, end: 0x45FFFF, flag: "🇩🇰"), // Denmark
        Range(start: 0x460000, end: 0x467FFF, flag: "🇫🇮"), // Finland
        Range(start: 0x468000, end: 0x46FFFF, flag: "🇬🇷"), // Greece
        Range(start: 0x470000, end: 0x477FFF, flag: "🇭🇺"), // Hungary
        Range(start: 0x478000, end: 0x47FFFF, flag: "🇳🇴"), // Norway
        Range(start: 0x4C0000, end: 0x4C7FFF, flag: "🇵🇹"), // Portugal
        Range(start: 0x4CA000, end: 0x4CAFFF, flag: "🇮🇪"), // Ireland
        Range(start: 0x4D0000, end: 0x4D03FF, flag: "🇲🇹"), // Malta
        Range(start: 0x500000, end: 0x5003FF, flag: "🇸🇲"), // San Marino
        Range(start: 0x508000, end: 0x50FFFF, flag: "🇹🇷"), // Turkey
        Range(start: 0x510000, end: 0x5103FF, flag: "🇨🇾"), // Cyprus
        Range(start: 0x511000, end: 0x5113FF, flag: "🇸🇰"), // Slovakia
        Range(start: 0x512000, end: 0x5123FF, flag: "🇷🇴"), // Romania
        Range(start: 0x100000, end: 0x1FFFFF, flag: "🇷🇺"), // Russia
        Range(start: 0x150000, end: 0x1503FF, flag: "🇪🇪"), // Estonia
        Range(start: 0x151000, end: 0x1513FF, flag: "🇱🇻"), // Latvia
        Range(start: 0x152000, end: 0x1523FF, flag: "🇱🇹"), // Lithuania
        Range(start: 0x710000, end: 0x717FFF, flag: "🇸🇦"), // Saudi Arabia
        Range(start: 0x718000, end: 0x71FFFF, flag: "🇰🇷"), // South Korea
        Range(start: 0x720000, end: 0x727FFF, flag: "🇰🇵"), // North Korea
        Range(start: 0x728000, end: 0x72FFFF, flag: "🇮🇶"), // Iraq
        Range(start: 0x730000, end: 0x737FFF, flag: "🇮🇷"), // Iran
        Range(start: 0x738000, end: 0x73FFFF, flag: "🇮🇱"), // Israel
        Range(start: 0x740000, end: 0x747FFF, flag: "🇯🇴"), // Jordan
        Range(start: 0x748000, end: 0x74FFFF, flag: "🇱🇧"), // Lebanon
        Range(start: 0x750000, end: 0x757FFF, flag: "🇸🇬"), // Singapore
        Range(start: 0x758000, end: 0x75FFFF, flag: "🇱🇰"), // Sri Lanka
        Range(start: 0x760000, end: 0x767FFF, flag: "🇸🇾"), // Syria
        Range(start: 0x768000, end: 0x76FFFF, flag: "🇦🇪"), // UAE
        Range(start: 0x770000, end: 0x777FFF, flag: "🇾🇪"), // Yemen
        Range(start: 0x780000, end: 0x7BFFFF, flag: "🇨🇳"), // China
        Range(start: 0x800000, end: 0x83FFFF, flag: "🇮🇳"), // India
        Range(start: 0x840000, end: 0x87FFFF, flag: "🇯🇵"), // Japan
        Range(start: 0x880000, end: 0x887FFF, flag: "🇹🇭"), // Thailand
        Range(start: 0x888000, end: 0x88FFFF, flag: "🇹🇼"), // Taiwan
        Range(start: 0x890000, end: 0x893FFF, flag: "🇵🇰"), // Pakistan
        Range(start: 0x894000, end: 0x8943FF, flag: "🇳🇵"), // Nepal
        Range(start: 0x8A0000, end: 0x8A7FFF, flag: "🇮🇩"), // Indonesia
        Range(start: 0x8F0000, end: 0x8F7FFF, flag: "🇰🇿"), // Kazakhstan
        Range(start: 0x900000, end: 0x9003FF, flag: "🇲🇭"), // Marshall Islands
        Range(start: 0x0A0000, end: 0x0A7FFF, flag: "🇿🇦"), // South Africa
        Range(start: 0x060000, end: 0x067FFF, flag: "🇪🇬"), // Egypt
        Range(start: 0xC80000, end: 0xC87FFF, flag: "🇳🇿"), // New Zealand
        Range(start: 0xE00000, end: 0xE3FFFF, flag: "🇦🇷"), // Argentina
        Range(start: 0xE40000, end: 0xE7FFFF, flag: "🇧🇷"), // Brazil
        Range(start: 0xE80000, end: 0xEBFFFF, flag: "🇨🇱"), // Chile
        Range(start: 0xEC0000, end: 0xEFFFFF, flag: "🇪🇨"), // Ecuador
        Range(start: 0x0D0000, end: 0x0D7FFF, flag: "🇨🇮"), // Cote d'Ivoire
    ]

    /// `flagFor` in HexCountry.kt.
    /// Trims, lowercases, strips a leading `~`, parses as hex, returns the first
    /// matching range's flag (or nil).
    static func flag(forHex hex: String?) -> String? {
        guard let hex = hex else { return nil }
        var h = hex.trimmingCharacters(in: .whitespaces).lowercased()
        if h.hasPrefix("~") { h.removeFirst() }
        guard let v = Int(h, radix: 16) else { return nil }
        return ranges.first { v >= $0.start && v <= $0.end }?.flag
    }
}
