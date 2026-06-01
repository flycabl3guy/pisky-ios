import Foundation

/// Small formatting helpers. Locale pinned to `en_US` to match the Android `"%,d".format()` /
/// `Locale.US` behavior (see PORTING_NOTES.md §8).
enum Fmt {
    static let us = Locale(identifier: "en_US")

    /// Grouped integer, e.g. 123456 → "123,456".
    static func grouped(_ n: Int) -> String {
        n.formatted(.number.grouping(.automatic).locale(us))
    }

    static func grouped(_ n: Int64) -> String {
        n.formatted(.number.grouping(.automatic).locale(us))
    }

    /// Compact large counts: 1_500_000 → "1.5M", 12_300 → "12.3K".
    static func compact(_ n: Int64) -> String {
        n.formatted(.number.notation(.compactName).locale(us))
    }

    /// Uptime seconds → "5d 2h" / "23h 45m" / "12m".
    static func uptime(_ seconds: Double) -> String {
        let s = Int(seconds)
        let d = s / 86_400, h = (s % 86_400) / 3_600, m = (s % 3_600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

extension Double {
    /// Degrees → radians.
    var radians: Double { self * .pi / 180 }
    /// Radians → degrees.
    var degrees: Double { self * 180 / .pi }
}
