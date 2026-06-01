import SwiftUI

/// `MapScreen` — port of `MapScreen.kt`. Contract §5: `MapScreen(initialSelectHex: String?)`.
///
/// PRIMARY backend is the tar1090 `WKWebView` ([TarWebView]); a SECONDARY in-app "Scope" mode
/// renders the pure-`Canvas` STARS PPI ([RadarScopeCanvas], ported from `RadarScope2Overlay.kt`).
/// HUD overlays (aircraft-count badge, mode toggle, search, filter chips, detail sheet) float over
/// whichever surface is active.
struct MapScreen: View {
    let initialSelectHex: String?

    @Environment(AppContainer.self) private var container
    @State private var vm = MapViewModel()
    @State private var controller: TarMapController?
    @State private var showSearch = false
    @State private var showFilter = false

    init(initialSelectHex: String? = nil) { self.initialSelectHex = initialSelectHex }

    var body: some View {
        @Bindable var vm = vm
        ZStack {
            Palette.background.ignoresSafeArea()

            // ── Base surface ───────────────────────────────────────────────
            switch vm.mode {
            case .live:
                if let url = vm.baseURL {
                    TarWebView(
                        baseURL: url,
                        onAircraftTap: { vm.selectAircraft($0) },
                        onControllerReady: { ctrl in
                            controller = ctrl
                            if let hex = vm.selectedHex { ctrl.selectAircraft(hex) }
                        }
                    )
                    .ignoresSafeArea()
                } else {
                    ProgressView().tint(Palette.brass)
                }
            case .scope:
                RadarScopeCanvas(
                    aircraft: vm.mapAircraft,
                    receiverLat: vm.receiverStats?.latitude ?? TarOverlayData.homeLat,
                    receiverLon: vm.receiverStats?.longitude ?? TarOverlayData.homeLon,
                    selectedHex: vm.selectedHex,
                    onSelect: { vm.selectAircraft($0) }
                )
                .ignoresSafeArea(edges: .bottom)
            }

            // ── HUD overlays ───────────────────────────────────────────────
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    AircraftCountBadge(
                        withPos: vm.mapAircraft.filter(\.hasPosition).count,
                        total: vm.aircraft.count
                    )
                    Spacer()
                    HStack(spacing: 8) {
                        modeToggle
                        PremiumIconButton(action: { showSearch.toggle() }, icon: "magnifyingglass")
                        PremiumIconButton(
                            action: { showFilter.toggle() },
                            icon: "line.3.horizontal.decrease.circle"
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                if showSearch { searchPanel.padding(.horizontal, 16).padding(.top, 8) }
                Spacer()
            }

            // ── Filter chips panel ─────────────────────────────────────────
            if showFilter {
                VStack { Spacer(); FilterChipsBar(filter: $vm.mapFilter, onReset: { vm.resetFilter() }) }
                    .padding(.bottom, vm.selectedAircraft != nil ? 0 : 16)
            }

            // ── Selected-aircraft detail sheet ─────────────────────────────
            if let ac = vm.selectedAircraft {
                VStack {
                    Spacer()
                    MapAircraftSheet(
                        aircraft: ac,
                        onDismiss: { vm.clearSelection() },
                        onFavorite: { vm.toggleFavorite(ac.hex, isFavorite: ac.isFavorite) }
                    )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .animation(HangarLuxe.Motion.standard(), value: vm.selectedHex)
        .task { vm.start(container, initialSelectHex: initialSelectHex) }
        // Native → web push when selection changes in Live mode.
        .onChange(of: vm.selectedHex) { _, hex in
            if vm.mode == .live, let hex { controller?.selectAircraft(hex) }
        }
    }

    // ── Mode toggle (Live / Scope) ─────────────────────────────────────────
    private var modeToggle: some View {
        HStack(spacing: 2) {
            ForEach(MapMode.allCases, id: \.self) { m in
                Button {
                    HangarHaptics.toggle(); vm.mode = m
                } label: {
                    Text(m.title.uppercased())
                        .font(.inter(10, weight: .bold)).tracking(1)
                        .foregroundStyle(vm.mode == m ? Palette.brassBright : Palette.textMuted)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(vm.mode == m ? Palette.brass.opacity(0.22) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(3)
        .background(Palette.cardElevated.opacity(0.92))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(HangarLuxe.Glass.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // ── Search panel ───────────────────────────────────────────────────────
    private var searchPanel: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.textMuted)
                TextField("Callsign, hex, type, squawk…", text: $vm.searchQuery)
                    .font(.psMono(13)).foregroundStyle(Palette.textPrimary)
                    .autocorrectionDisabled().textInputAutocapitalization(.characters)
                if !vm.searchQuery.isEmpty {
                    Button { vm.searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textMuted)
                    }
                }
            }
            .padding(10)
            .background(Palette.cardSheet.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !vm.searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(vm.searchResults) { ac in
                        Button {
                            vm.selectAircraft(ac.hex)
                            if vm.mode == .live { controller?.selectAircraft(ac.hex) }
                            showSearch = false; vm.searchQuery = ""
                        } label: { searchRow(ac) }
                    }
                }
                .padding(.horizontal, 12)
                .background(Palette.cardSheet.opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: 420)
    }

    private func searchRow(_ ac: Aircraft) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(ac.displayCallsign).font(.psMono(14, weight: .bold)).foregroundStyle(Palette.cyan)
                Text([ac.hex.uppercased(), ac.type, ac.squawk.map { "SQ\($0)" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.psMono(11)).foregroundStyle(Palette.textMuted)
            }
            Spacer()
            Text(ac.isOnGround ? "GND" : (ac.altitudeBaro.map { "\($0)ft" } ?? ""))
                .font(.psMono(12)).foregroundStyle(Palette.textSecondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Aircraft count badge

private struct AircraftCountBadge: View {
    let withPos: Int
    let total: Int
    var body: some View {
        Text("\(withPos) / \(total) pos")
            .font(.psMono(11, weight: .semibold))
            .foregroundStyle(Palette.cyan)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(hex: 0x0A1428, alpha: 0.80))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(HangarLuxe.Glass.border, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Filter chips bar (compact subset of the Android FilterPanel)

private struct FilterChipsBar: View {
    @Binding var filter: MapFilter
    var onReset: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            chip("MIL", on: filter.militaryOnly) { filter.militaryOnly.toggle() }
            chip("EMER", on: filter.emergencyOnly) { filter.emergencyOnly.toggle() }
            chip("HIDE MLAT", on: filter.hideMlat) { filter.hideMlat.toggle() }
            chip("HIDE GND", on: filter.hideGroundVehicles) { filter.hideGroundVehicles.toggle() }
            if filter.enabledCount > 0 {
                Button { HangarHaptics.tap(); onReset() } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Palette.cardElevated.opacity(0.92))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(HangarLuxe.Glass.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private func chip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button { HangarHaptics.toggle(); action() } label: {
            Text(label).font(.inter(10, weight: .semibold)).tracking(0.5)
                .foregroundStyle(on ? Palette.brassBright : Palette.textMuted)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background((on ? Palette.brass : Palette.textMuted).opacity(0.14))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Map aircraft detail sheet (port of PlatinumAircraftSheet)

private struct MapAircraftSheet: View {
    let aircraft: Aircraft
    var onDismiss: () -> Void
    var onFavorite: () -> Void

    private var titleColor: Color {
        if aircraft.emergency != .none { return Palette.emergencyRed }
        if aircraft.isMilitary { return Palette.brass }
        if aircraft.isMlat { return Palette.signalAmberHot }
        return Palette.cyan
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(aircraft.displayCallsign).font(.psMono(22, weight: .bold)).foregroundStyle(titleColor)
                    let sub = [aircraft.registration, aircraft.type].compactMap { $0 }.joined(separator: "  ·  ")
                    if !sub.isEmpty { Text(sub).font(.inter(12)).foregroundStyle(Palette.textSecondary) }
                    if let route = aircraft.routeDisplay {
                        Text(route).font(.psMono(12, weight: .semibold)).foregroundStyle(Palette.cyan)
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    if aircraft.isMlat { badge("MLAT", Palette.signalAmberHot) }
                    if aircraft.isTisb { badge("TIS-B", Palette.cyan) }
                    switch aircraft.classification.level {
                    case .military: badge("MIL", Palette.brass)
                    case .likelyMilitary: badge("MIL?", Palette.brass.opacity(0.7))
                    default: EmptyView()
                    }
                    if aircraft.emergency != .none { badge("EMER", Palette.emergencyRed) }
                }
                Button(action: { HangarHaptics.select(); onFavorite() }) {
                    Image(systemName: aircraft.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(aircraft.isFavorite ? Palette.emergencyRed : Palette.textMuted)
                }
                Button(action: { HangarHaptics.tap(); onDismiss() }) {
                    Image(systemName: "xmark").foregroundStyle(Palette.textMuted)
                }
            }

            Rectangle()
                .fill(LinearGradient(colors: [altColor.opacity(0), altColor, altColor.opacity(0.4)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 3).clipShape(Capsule())

            HStack(spacing: 8) {
                cell("Altitude", aircraft.altitudeDisplay, altColor)
                cell("Speed", aircraft.speedDisplay, Palette.cyan)
                cell("V/Rate", aircraft.verticalRateDisplay, vRateColor)
            }
            HStack(spacing: 8) {
                cell("Distance", aircraft.distanceNm.map { String(format: "%.0f mi", $0 * 1.15078) } ?? "—", Palette.textPrimary)
                cell("Bearing", aircraft.bearingDeg.map { String(format: "%.0f°", $0) } ?? "—", Palette.textPrimary)
                cell("RSSI", aircraft.rssi.map { String(format: "%.1f dBFS", $0) } ?? "—", rssiColor)
            }
        }
        .padding(16)
        .background(
            LinearGradient(stops: [
                .init(color: Color(hex: 0x112240, alpha: 0.85), location: 0),
                .init(color: Color(hex: 0x0A1428, alpha: 0.95), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Palette.brassBright.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
    }

    private var altColor: Color {
        Palette.altitudeBand(altFt: aircraft.altitudeBaro, onGround: aircraft.isOnGround,
                             isMlat: aircraft.isMlat, emergency: aircraft.emergency != .none)
    }
    private var vRateColor: Color {
        let vr = aircraft.verticalRate ?? 0
        if vr > 64 { return Palette.statusOk }
        if vr < -64 { return Palette.statusError }
        return Palette.textSecondary
    }
    private var rssiColor: Color {
        guard let r = aircraft.rssi else { return Palette.textMuted }
        if r > -3 { return Palette.statusError }
        if r > -10 { return Palette.statusOk }
        if r > -20 { return Palette.statusWarn }
        return Palette.textSecondary
    }

    private func cell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.psMono(10)).tracking(0.8).foregroundStyle(Palette.textMuted)
            Text(value).font(.inter(14, weight: .semibold)).foregroundStyle(color).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color(hex: 0x0A1830))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func badge(_ label: String, _ color: Color) -> some View {
        Text(label).font(.psMono(10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.4), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
