import SwiftUI

/// Per-aircraft info strip across the bottom of the PFD: callsign / registration
/// / type / squawk / integrity / distance+bearing / position. Mimics the 737
/// PFD's bottom status area, with squawk turning red on emergency codes.
///
/// Ports `feature/pfd/instruments/BottomInfoBar.kt`.
struct BottomInfoBar: View {
    let aircraft: Aircraft?

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            field("CALLSIGN", callsignText, color: PfdColors.white)
            Spacer(minLength: 0)
            field("REG", aircraft?.registration ?? "—", color: PfdColors.white)
            Spacer(minLength: 0)
            field("TYPE", aircraft?.type ?? "—", color: PfdColors.white)
            Spacer(minLength: 0)
            field("SQWK", squawkText, color: squawkColor)
            Spacer(minLength: 0)
            field("INTEG", integText, color: integColor)
            Spacer(minLength: 0)
            field("DIST", distText, color: PfdColors.cyan)
            Spacer(minLength: 0)
            field("POS", posText, color: PfdColors.white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(PfdColors.background)
        .overlay(Rectangle().stroke(PfdColors.fmaBorder, lineWidth: 0.5))
    }

    private func field(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .tracking(1.0)
                .foregroundColor(PfdColors.fmaBorder)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
        }
    }

    // ── Callsign + registration ──
    private var callsignText: String {
        if let cs = aircraft?.callsign?.trimmingCharacters(in: .whitespaces), !cs.isEmpty { return cs }
        if let hex = aircraft?.hex { return hex.uppercased() }
        return "—"
    }

    // ── Squawk ──
    private var squawkText: String { aircraft?.squawk ?? "—" }
    private var squawkColor: Color {
        let sq = aircraft?.squawk ?? ""
        return ["7500", "7600", "7700"].contains(sq) ? PfdColors.red : PfdColors.white
    }

    // ── Position integrity — NACp/NIC + ADS-B version, colour-coded. ──
    // Colour off the lower of whichever values are actually present (a missing
    // NIC must not drag a good NACp down to red).
    private var integText: String {
        let nacp = aircraft?.nacP
        let nic = aircraft?.nic
        guard nacp != nil || nic != nil else { return "—" }
        let ver = aircraft?.version
        let np = nacp.map(String.init) ?? "–"
        let ni = nic.map(String.init) ?? "–"
        let v = ver.map { " v\($0)" } ?? ""
        return "\(np)/\(ni)\(v)"
    }
    private var integColor: Color {
        let present = [aircraft?.nacP, aircraft?.nic].compactMap { $0 }
        guard let lo = present.min() else { return PfdColors.fmaBorder }
        if lo >= 8 { return PfdColors.green }
        if lo >= 6 { return PfdColors.cyan }
        if lo >= 4 { return PfdColors.amber }
        return PfdColors.red
    }

    // ── Distance & bearing from receiver ──
    private var distText: String {
        guard let d = aircraft?.distanceNm else { return "—" }
        return String(format: "%.1f nm %03.0f°", d, aircraft?.bearingDeg ?? 0.0)
    }

    // ── Position ──
    private var posText: String {
        guard let lat = aircraft?.latitude, let lon = aircraft?.longitude else { return "—" }
        return String(format: "%.3f %+.3f", lat, lon)
    }
}
