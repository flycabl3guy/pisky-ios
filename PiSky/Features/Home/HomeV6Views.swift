import SwiftUI

/// v6 home-screen supporting views — ports of `v6/StatPlate.kt` and `v6/StatusPill.kt`.
///
/// The hero stat plate is named **`HeroStatPlate`** to avoid colliding with the design system's
/// generic `StatPlate` (DesignSystem/Components/AtlasHud.swift).

// MARK: - HeroStatPlate (port of v6/StatPlate.kt)

/// The brass-bordered glass plate that holds the four hero numbers below the radar:
/// VISIBLE · CLOSEST · PEAK · MIL·24h. Numbers are big mono/Rajdhani; cells split by hairline rules.
struct HeroStatPlate: View {
    let visible: Int
    let closestNm: Double?
    let maxRangeNm: Double
    let militaryToday: Int

    var body: some View {
        HangarPlate(radius: HangarLuxe.Radius.large, elevation: HangarLuxe.Elevation.hero, contentPadding: 18) {
            HStack {
                cell("VISIBLE", value: "\(visible)", accent: Palette.cyan, mono: true)
                rule
                cell("CLOSEST",
                     value: closestNm.map { String(format: "%.1f", $0) } ?? "—",
                     unit: closestNm != nil ? "nm" : nil,
                     accent: Palette.brassBright)
                rule
                cell("PEAK", value: String(format: "%.0f", maxRangeNm), unit: "nm", accent: Palette.brassBright)
                rule
                cell("MIL · 24h", value: "\(militaryToday)",
                     accent: militaryToday > 0 ? Palette.brassBright : Palette.textMuted)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var rule: some View {
        Rectangle().fill(Palette.outline).frame(width: 1, height: 46)
    }

    private func cell(_ label: String, value: String, unit: String? = nil, accent: Color, mono: Bool = false) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .bottom, spacing: 4) {
                Text(value)
                    .font(mono ? .psMono(40, weight: .bold) : .rajdhani(44, weight: .bold))
                    .foregroundStyle(accent)
                if let unit {
                    Text(unit).font(.psMono(14, weight: .medium)).foregroundStyle(Palette.textMuted)
                        .padding(.bottom, 6)
                }
            }
            Text(label).font(.psMono(11, weight: .medium)).tracking(1.6).foregroundStyle(Palette.textMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - StatusKind + StatusPill (port of v6/StatusPill.kt)

enum StatusKind { case live, offline, stale }

/// Pulsing connection indicator: `Pi · <host> · LIVE`, cyan breathing dot when live, amber stale,
/// red offline. Glass pill with a brass hairline.
struct StatusPill: View {
    let host: String
    let status: StatusKind

    @State private var pulse: CGFloat = 0.45

    private var dotColor: Color {
        switch status { case .live: return Palette.cyan; case .stale: return Palette.statusWarn; case .offline: return Palette.statusError }
    }
    private var label: String {
        switch status { case .live: return "LIVE"; case .stale: return "STALE"; case .offline: return "OFFLINE" }
    }
    private var labelColor: Color {
        switch status { case .live: return Palette.brassBright; case .stale: return Palette.statusWarn; case .offline: return Palette.statusError }
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if status == .live {
                    Circle().fill(dotColor.opacity(0.18 * pulse)).frame(width: 14, height: 14)
                }
                Circle().fill(dotColor.opacity(status == .live ? pulse : 1)).frame(width: 6, height: 6)
            }
            .frame(width: 14, height: 14)

            Text("Pi").font(.psMono(11, weight: .bold)).tracking(1.5).foregroundStyle(Palette.brassBright)
            Text("·").font(.psMono(11)).foregroundStyle(Palette.textMuted)
            Text(host).font(.psMono(11, weight: .medium)).tracking(0.5).foregroundStyle(Palette.textMuted)
            Text("·").font(.psMono(11)).foregroundStyle(Palette.textMuted)
            Text(label).font(.psMono(11, weight: .bold)).tracking(1.8).foregroundStyle(labelColor)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color(hex: 0x000000, alpha: 0.20))
        .overlay(RoundedRectangle(cornerRadius: HangarLuxe.Radius.pill).strokeBorder(Palette.brass.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: HangarLuxe.Radius.pill, style: .continuous))
        .onAppear {
            guard status == .live else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = 1.0 }
        }
    }
}
