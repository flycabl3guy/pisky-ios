import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers for the Aircraft feature
// ─────────────────────────────────────────────────────────────────────────────

/// Altitude band color used by the list rows and detail sheet (matches `altitudeColor` in the
/// Kotlin AircraftScreen/AircraftDetailSheet — distinct from `Palette.altitudeBand`, which treats
/// emergency as a top-priority override before MLAT).
func aircraftAltitudeColor(_ ac: Aircraft) -> Color {
    if ac.emergency != .none { return Palette.emergencyRed }
    if ac.isMlat            { return Palette.altMlat }
    if ac.isOnGround        { return Palette.altGround }
    guard let alt = ac.altitudeBaro else { return Palette.altGround }
    if alt < 5_000  { return Palette.altLow }
    if alt < 20_000 { return Palette.altMid }
    return Palette.altHigh
}

/// Tag category → accent color. Port of `tagCategoryColor` in TagsScreen.kt.
func tagCategoryColor(_ category: TagCategory) -> Color {
    switch category {
    case .military:    return Palette.statusError
    case .private:     return Palette.cyan       // PiSkyBlue → cyan
    case .interesting: return Palette.signalAmberHot
    case .watch:       return Palette.brassBright // PiSkyGreen → brassBright
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// AircraftDetailSheet — 12-section detail
// ─────────────────────────────────────────────────────────────────────────────

/// The aircraft detail sheet. Presented via `.sheet(item:)`; the host supplies tag + favorite
/// actions. Ported from `AircraftDetailSheet.kt` (header+badges, tag picker, emergency chip,
/// 6-cell grid, altitude sparkline, squawk, Identity / Position & Movement / Autopilot Intent /
/// Signal sections).
struct AircraftDetailSheet: View {
    let aircraft: Aircraft
    let currentTag: TagCategory?
    let onFavorite: () -> Void
    let onTagChange: (TagCategory?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showTagPicker = false

    private var isEmergency: Bool { aircraft.emergency != .none }
    private var altColor: Color { aircraftAltitudeColor(aircraft) }
    private var callsignColor: Color {
        if isEmergency { return Palette.emergencyRed }
        if aircraft.isMilitary { return Palette.brass }
        if aircraft.isMlat { return Palette.signalAmberHot }
        return Palette.cyan
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Altitude color bar
                Rectangle().fill(altColor).frame(height: 3).frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 16)
                    header
                    if showTagPicker { tagPicker }
                    if isEmergency {
                        Spacer().frame(height: 8)
                        emergencyChip
                    }
                    divider
                    overviewGrid
                    Spacer().frame(height: 12)
                    AltitudeSparkline(aircraft: aircraft, lineColor: altColor)
                    squawkRow
                    divider
                    identitySection
                    divider
                    positionSection
                    autopilotSection
                    signalSection
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(Palette.cardSheet.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
    }

    // ── Header ───────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(aircraft.displayCallsign)
                    .font(.psMono(24, weight: .bold))
                    .foregroundStyle(callsignColor)
                Spacer().frame(height: 2)
                HStack(spacing: 8) {
                    Text(aircraft.hex.uppercased())
                        .font(.psMono(12)).foregroundStyle(Palette.textMuted)
                    if let reg = aircraft.registration {
                        Text("·").foregroundStyle(Palette.textMuted)
                        Text(reg).font(.inter(12)).foregroundStyle(Palette.textSecondary)
                    }
                    if let type = aircraft.type {
                        Text("·").foregroundStyle(Palette.textMuted)
                        Text(AircraftTypeNames.decode(type) ?? type)
                            .font(.inter(12))
                            .foregroundStyle(aircraft.isMilitary ? Palette.brass.opacity(0.8) : Palette.textSecondary)
                    }
                }
                Spacer().frame(height: 4)
                HStack(spacing: 6) {
                    if aircraft.isMlat { SheetBadge("MLAT", Palette.signalAmberHot) }
                    if aircraft.isTisb { SheetBadge("TIS-B", Palette.cyan) }
                    switch aircraft.classification.level {
                    case .military:       SheetBadge("MIL", Palette.brass)
                    case .likelyMilitary: SheetBadge("MIL?", Palette.brass.opacity(0.7))
                    default:              EmptyView()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isEmergency {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22)).foregroundStyle(Palette.emergencyRed)
                    .padding(.trailing, 8)
            }
            Button { HangarHaptics.tap(); showTagPicker.toggle() } label: {
                Image(systemName: currentTag != nil ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 20))
                    .foregroundStyle(currentTag.map(tagCategoryColor) ?? Palette.textMuted)
            }
            .frame(width: 40, height: 40)
            Button { HangarHaptics.toggle(); onFavorite() } label: {
                Image(systemName: aircraft.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 20))
                    .foregroundStyle(aircraft.isFavorite ? Palette.brassBright : Palette.textMuted)
            }
            .frame(width: 40, height: 40)
        }
    }

    private var tagPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 8)
            AtlasFlow(spacing: 8, lineSpacing: 8) {
                ForEach(TagCategory.allCases, id: \.self) { cat in
                    let selected = currentTag == cat
                    Button {
                        HangarHaptics.select()
                        onTagChange(selected ? nil : cat)
                        showTagPicker = false
                    } label: {
                        Text(cat.label)
                            .font(.psMono(10, weight: .medium))
                            .foregroundStyle(selected ? tagCategoryColor(cat) : Palette.textSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(selected ? tagCategoryColor(cat).opacity(0.2) : Palette.cardElevated)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emergencyChip: some View {
        let (label, color) = emergencyLabelColor(aircraft.emergency)
        return HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14)).foregroundStyle(color)
            Text(label).font(.psMono(10, weight: .bold)).foregroundStyle(color)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(color.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // ── Overview grid (6 cells) ────────────────────────────────────────────────

    private var overviewGrid: some View {
        VStack(spacing: 8) {
            sheetSectionHeader("Overview")
            HStack(spacing: 8) {
                DataCell(label: "ALTITUDE", value: aircraft.altitudeDisplay, color: altColor)
                DataCell(label: "SPEED", value: aircraft.speedDisplay, color: Palette.cyan)
                DataCell(label: "V/RATE", value: aircraft.verticalRateDisplay, color: Palette.textPrimary)
            }
            HStack(spacing: 8) {
                DataCell(label: "DISTANCE",
                         value: aircraft.distanceNm.map { String(format: "%.1f nm", $0) } ?? "—",
                         color: Palette.cyan)
                DataCell(label: "BEARING",
                         value: aircraft.bearingDeg.map { String(format: "%.0f°", $0) } ?? "—",
                         color: Palette.textPrimary)
                DataCell(label: "RSSI",
                         value: aircraft.rssi.map { String(format: "%.1f dBFS", $0) } ?? "—",
                         color: Palette.textPrimary)
            }
        }
    }

    // ── Squawk ──────────────────────────────────────────────────────────────────

    @ViewBuilder private var squawkRow: some View {
        if let sq = aircraft.squawk {
            let isEmergencySq = ["7500", "7600", "7700"].contains(sq)
            let meaning = squawkMeaning(sq)
            Spacer().frame(height: 12)
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SQUAWK").font(.psMono(10, weight: .medium)).tracking(1)
                        .foregroundStyle(Palette.textMuted)
                    if let meaning {
                        Text(meaning).font(.psMono(10, weight: .medium))
                            .foregroundStyle(isEmergencySq ? Palette.emergencyRed : Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(sq).font(.psMono(16, weight: .bold))
                    .foregroundStyle(isEmergencySq ? Palette.emergencyRed : Palette.textPrimary)
                if isEmergencySq {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16)).foregroundStyle(Palette.emergencyRed)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(isEmergencySq ? Palette.emergencyRed.opacity(0.15) : Palette.cardElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // ── Identity ─────────────────────────────────────────────────────────────────

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetSectionHeader("Identity")
            InfoRow("Registration", aircraft.registration ?? "—")
            InfoRow("Type", aircraft.typeDescription)
            if let raw = aircraft.type, AircraftTypeNames.decode(raw) != nil {
                InfoRow("Type code", raw)
            }
            InfoRow("Category", aircraft.category ?? "—")
            InfoRow("MLAT", aircraft.isMlat ? "Yes" : "No")
            InfoRow("TIS-B", aircraft.isTisb ? "Yes" : "No")
        }
    }

    // ── Position & Movement ───────────────────────────────────────────────────────

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetSectionHeader("Position & Movement")
            InfoRow("Altitude (baro)", aircraft.altitudeDisplay)
            InfoRow("Altitude (geom)", aircraft.altitudeGeom.map { "\(Fmt.grouped($0)) ft" } ?? "—")
            InfoRow("Ground speed", aircraft.speedDisplay)
            InfoRow("Track", aircraft.track.map { String(format: "%.1f°", $0) } ?? "—")
            InfoRow("Vertical rate", aircraft.verticalRateDisplay)
            InfoRow("On ground", aircraft.isOnGround ? "Yes" : "No")
            if let lat = aircraft.latitude, let lon = aircraft.longitude {
                InfoRow("Position", String(format: "%.5f, %.5f", lat, lon))
            }
            if let dist = aircraft.distanceNm {
                InfoRow("Distance", String(format: "%.1f nm  •  %.0f°", dist, aircraft.bearingDeg ?? 0))
            }
        }
    }

    // ── Autopilot intent ──────────────────────────────────────────────────────────

    @ViewBuilder private var autopilotSection: some View {
        if aircraft.navAltitudeMcp != nil || aircraft.navHeading != nil
            || aircraft.navQnh != nil || !aircraft.navModes.isEmpty {
            divider
            VStack(alignment: .leading, spacing: 0) {
                sheetSectionHeader("Autopilot Intent")
                autopilotBody
            }
        }
    }

    private var autopilotBody: some View {
        let vertical = deriveVerticalIntent(mcp: aircraft.navAltitudeMcp,
                                            baroAlt: aircraft.altitudeBaro,
                                            onGround: aircraft.isOnGround)
        let lateral = deriveLateralIntent(navHdg: aircraft.navHeading, track: aircraft.track)
        return VStack(alignment: .leading, spacing: 0) {
            if let vertical { intentLine(vertical) }
            if let lateral { intentLine(lateral) }
            if !aircraft.navModes.isEmpty {
                Spacer().frame(height: 8)
                AtlasFlow(spacing: 6, lineSpacing: 6) {
                    ForEach(aircraft.navModes, id: \.self) { mode in
                        Text(mode.replacingOccurrences(of: "_", with: " ").uppercased())
                            .font(.psMono(10, weight: .medium)).tracking(0.7)
                            .foregroundStyle(Palette.brass)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Palette.brass.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
            if let qnh = aircraft.navQnh {
                Spacer().frame(height: 8)
                let deltaStd = qnh - 1013.25
                let deltaTxt = abs(deltaStd) >= 0.1 ? String(format: "  (%+.1f vs std)", deltaStd) : ""
                InfoRow("Altimeter", String(format: "%.1f hPa%@", qnh, deltaTxt))
            }
        }
    }

    private func intentLine(_ d: IntentDescriptor) -> some View {
        Text(d.text).font(.inter(14, weight: .semibold)).foregroundStyle(d.color)
            .padding(.vertical, 3)
    }

    // ── Signal ───────────────────────────────────────────────────────────────────

    private var signalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            divider
            sheetSectionHeader("Signal")
            InfoRow("RSSI", aircraft.rssi.map { String(format: "%.1f dBFS", $0) } ?? "—")
            InfoRow("Messages", Fmt.grouped(aircraft.messages))
            InfoRow("Seen", String(format: "%.1f s ago", aircraft.seen))
            if let seenPos = aircraft.seenPos {
                InfoRow("Last position", String(format: "%.1f s ago", seenPos))
            }
            InfoRow("NIC", aircraft.nic.map(String.init) ?? "—")
            InfoRow("NACp", aircraft.nacP.map(String.init) ?? "—")
            InfoRow("NACv", aircraft.nacV.map(String.init) ?? "—")
            InfoRow("SIL", aircraft.sil.map(String.init) ?? "—")
            InfoRow("ADS-B version", aircraft.version.map(String.init) ?? "—")
        }
    }

    // ── Small building blocks ──────────────────────────────────────────────────────

    private var divider: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 16)
            Rectangle().fill(Palette.outline.opacity(0.6)).frame(height: 1)
            Spacer().frame(height: 16)
        }
    }

    private func sheetSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.psMono(10, weight: .medium)).tracking(1.2)
            .foregroundStyle(Palette.brass.opacity(0.7))
            .padding(.bottom, 8)
    }
}

// ── InfoRow / DataCell / SheetBadge ───────────────────────────────────────────────

private struct InfoRow: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        HStack {
            Text(label).font(.inter(12)).foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value).font(.psMono(12)).foregroundStyle(Palette.textPrimary)
        }
        .padding(.vertical, 4)
    }
}

private struct DataCell: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.psMono(9, weight: .medium)).tracking(0.8)
                .foregroundStyle(Palette.textMuted)
            Text(value).font(.psMono(12, weight: .semibold)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 10)
        .background(Palette.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SheetBadge: View {
    let label: String
    let tint: Color
    init(_ label: String, _ tint: Color) { self.label = label; self.tint = tint }
    var body: some View {
        Text(label).font(.psMono(9, weight: .medium)).foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// ── Autopilot intent derivation (ports from AircraftDetailSheet.kt) ─────────────────

struct IntentDescriptor { let text: String; let color: Color }

private func formatTargetAlt(_ ft: Int) -> String {
    ft >= 10_000 ? String(format: "FL%03d", (ft + 50) / 100) : "\(Fmt.grouped(ft)) ft"
}

private func deriveVerticalIntent(mcp: Int?, baroAlt: Int?, onGround: Bool) -> IntentDescriptor? {
    guard let mcp else { return nil }
    let label = formatTargetAlt(mcp)
    guard !onGround, let baroAlt else { return IntentDescriptor(text: "Target \(label)", color: Palette.brass) }
    let delta = mcp - baroAlt
    if delta > 300  { return IntentDescriptor(text: "↑ Climbing to \(label)", color: Palette.altLow) }
    if delta < -300 { return IntentDescriptor(text: "↓ Descending to \(label)", color: Palette.signalAmberHot) }
    return IntentDescriptor(text: "→ Level at \(label)", color: Palette.statusOk)
}

private func deriveLateralIntent(navHdg: Double?, track: Double?) -> IntentDescriptor? {
    guard let navHdg else { return nil }
    let target = ((Int(navHdg) % 360) + 360) % 360
    let targetTxt = String(format: "%03d°", target)
    guard let track else { return IntentDescriptor(text: "Selected \(targetTxt)", color: Palette.brass) }
    var delta = navHdg - track
    while delta > 180 { delta -= 360 }
    while delta < -180 { delta += 360 }
    if delta > 5  { return IntentDescriptor(text: "↻ Turning right → \(targetTxt)", color: Palette.altMid) }
    if delta < -5 { return IntentDescriptor(text: "↺ Turning left → \(targetTxt)", color: Palette.altMid) }
    return IntentDescriptor(text: "→ On heading \(targetTxt)", color: Palette.statusOk)
}

/// Best-effort 4-digit Mode A squawk interpretation. Returns nil for discrete ATC assignments.
func squawkMeaning(_ squawk: String) -> String? {
    switch squawk {
    case "7500": return "Hijack / unlawful interference"
    case "7600": return "Radio failure (NORDO)"
    case "7700": return "General emergency"
    case "1200": return "VFR (US/Canada)"
    case "7000": return "VFR (Europe)"
    case "1201": return "VFR glider"
    case "1202": return "VFR glider — no Mode C"
    case "1255": return "Firefighting aircraft"
    case "1276": return "ADIZ penetration"
    case "1277": return "Search and rescue"
    case "0000": return "Unassigned (military intercept)"
    case "4000": return "Military / special use"
    case "5000", "5001", "5002", "5003", "5004", "5005", "5006", "5007": return "Military operations"
    default: return nil
    }
}

/// Emergency → (banner label, color). Port of `PlatinumEmergencyChip`'s table.
func emergencyLabelColor(_ e: Emergency) -> (String, Color) {
    switch e {
    case .general:   return ("GENERAL EMERGENCY", Palette.emergencyRed)
    case .lifeguard: return ("LIFEGUARD / MEDICAL", Palette.emergencyRed)
    case .minfuel:   return ("MINIMUM FUEL", Palette.emergencyAmber)
    case .nordo:     return ("NO RADIO", Palette.emergencyAmber)
    case .unlawful:  return ("UNLAWFUL INTERFERENCE", Palette.emergencyRed)
    case .downed:    return ("DOWNED AIRCRAFT", Palette.emergencyRed)
    case .reserved:  return ("EMERGENCY (RESERVED)", Palette.emergencyAmber)
    case .none:      return ("", Palette.emergencyRed)
    }
}
