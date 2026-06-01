import SwiftUI
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// AlertsViewModel
// ─────────────────────────────────────────────────────────────────────────────

@MainActor @Observable
final class AlertsViewModel {
    private(set) var emergencyAircraft: [Aircraft] = []
    private(set) var militaryAircraft: [Aircraft] = []
    private(set) var taggedHexes: [String: TagCategory] = [:]

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private weak var container: AppContainer?
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true; container = c

        c.aircraftRepository.observeAircraft()
            .map { $0.filter { $0.emergency != .none } }
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.emergencyAircraft = $0 }
            .store(in: &bag)

        c.aircraftRepository.observeMilitaryAircraft()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.militaryAircraft = $0 }
            .store(in: &bag)

        c.tagRepository.observeTaggedHexes()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.taggedHexes = $0 }
            .store(in: &bag)

        c.preferences.ruleLowAlt.receive(on: RunLoop.main)
            .sink { [weak self] in self?.ruleLowAltStore = $0 }.store(in: &bag)
        c.preferences.ruleHighSpeed.receive(on: RunLoop.main)
            .sink { [weak self] in self?.ruleHighSpeedStore = $0 }.store(in: &bag)
        c.preferences.ruleFavGround.receive(on: RunLoop.main)
            .sink { [weak self] in self?.ruleFavGroundStore = $0 }.store(in: &bag)
    }

    var hasActiveAlerts: Bool { !emergencyAircraft.isEmpty || !militaryAircraft.isEmpty }
    var activeCount: Int { emergencyAircraft.count + militaryAircraft.count }

    func aircraft(for hex: String) -> Aircraft? {
        emergencyAircraft.first { $0.hex == hex } ?? militaryAircraft.first { $0.hex == hex }
    }

    // Custom-rule toggles — observable backing stores, persisted through `container.preferences`
    // (publisher + setX API). Backings are seeded/synced via the publishers subscribed in start().
    private var ruleLowAltStore = true
    private var ruleHighSpeedStore = true
    private var ruleFavGroundStore = true

    var ruleLowAlt: Bool {
        get { ruleLowAltStore }
        set { ruleLowAltStore = newValue; container?.preferences.setRuleLowAlt(newValue) }
    }
    var ruleHighSpeed: Bool {
        get { ruleHighSpeedStore }
        set { ruleHighSpeedStore = newValue; container?.preferences.setRuleHighSpeed(newValue) }
    }
    var ruleFavGround: Bool {
        get { ruleFavGroundStore }
        set { ruleFavGroundStore = newValue; container?.preferences.setRuleFavGround(newValue) }
    }

    func toggleFavorite(_ ac: Aircraft) {
        let hex = ac.hex, isFav = ac.isFavorite
        Task {
            if isFav { await container?.aircraftRepository.removeFavorite(hex: hex) }
            else { await container?.aircraftRepository.addFavorite(hex: hex) }
        }
    }

    func tag(_ hex: String, _ category: TagCategory) {
        Task { await container?.tagRepository.tag(hex: hex, category: category, note: "") }
    }
    func untag(_ hex: String) { Task { await container?.tagRepository.untag(hex: hex) } }
}

// ─────────────────────────────────────────────────────────────────────────────
// AlertsScreen
// ─────────────────────────────────────────────────────────────────────────────

struct AlertsScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dimens) private var dimens
    @State private var vm = AlertsViewModel()
    @State private var sheetTarget: HexTarget?
    @State private var pulse = false

    var body: some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    sectionHeader("Active Now", count: vm.activeCount)
                    if vm.emergencyAircraft.isEmpty && vm.militaryAircraft.isEmpty {
                        emptyState("No active alerts",
                                   "Emergency squawks and military aircraft will appear here")
                    }
                    ForEach(vm.emergencyAircraft) { ac in
                        EmergencyAlertCard(aircraft: ac) { sheetTarget = HexTarget(hex: ac.hex) }
                        Spacer().frame(height: 8)
                    }
                    ForEach(vm.militaryAircraft) { ac in
                        MilitaryAlertCard(aircraft: ac) { sheetTarget = HexTarget(hex: ac.hex) }
                        Spacer().frame(height: 8)
                    }

                    Spacer().frame(height: 8)
                    sectionHeader("Custom Rules", count: nil)
                    Spacer().frame(height: 8)
                    CustomRuleCard(name: "Low-altitude aircraft",
                                   description: "Alert when any aircraft drops below 1,000 ft near receiver",
                                   enabled: vm.ruleLowAlt) { vm.ruleLowAlt.toggle() }
                    Spacer().frame(height: 8)
                    CustomRuleCard(name: "High-speed traffic",
                                   description: "Alert when groundspeed exceeds 700 kt",
                                   enabled: vm.ruleHighSpeed) { vm.ruleHighSpeed.toggle() }
                    Spacer().frame(height: 8)
                    CustomRuleCard(name: "Favorite aircraft on ground",
                                   description: "Alert when a favorited aircraft is seen on the ground",
                                   enabled: vm.ruleFavGround) { vm.ruleFavGround.toggle() }

                    Spacer().frame(height: 16)
                    sectionHeader("Alert History", count: nil)
                    Spacer().frame(height: 8)
                    emptyState("No alerts in last 24h", "Past alerts will be recorded here")
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, dimens.screenPadding)
                .padding(.vertical, 4)
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .task { vm.start(container) }
        .sheet(item: $sheetTarget) { target in
            if let ac = vm.aircraft(for: target.hex) {
                AircraftDetailSheet(
                    aircraft: ac,
                    currentTag: vm.taggedHexes[ac.hex],
                    onFavorite: { vm.toggleFavorite(ac) },
                    onTagChange: { cat in cat.map { vm.tag(ac.hex, $0) } ?? vm.untag(ac.hex) }
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.fill").font(.system(size: 20)).foregroundStyle(Palette.brass)
            Text("Alerts").font(.inter(16, weight: .bold)).foregroundStyle(Palette.brass)
                .frame(maxWidth: .infinity, alignment: .leading)
            if vm.hasActiveAlerts {
                Circle().fill(Palette.emergencyRed).frame(width: 10, height: 10)
                    .opacity(pulse ? 0.2 : 1.0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
            }
        }
        .padding(.horizontal, dimens.screenPadding).padding(.vertical, 12)
    }

    private func sectionHeader(_ title: String, count: Int?) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title.uppercased()).font(.psMono(10, weight: .medium)).tracking(1.2)
                    .foregroundStyle(Palette.brass.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let count, count > 0 {
                    Text("\(count)").font(.psMono(10, weight: .medium))
                        .foregroundStyle(Palette.signalAmberHot)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Palette.signalAmberHot.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.vertical, 8)
            Rectangle().fill(Palette.outline.opacity(0.5)).frame(height: 1)
            Spacer().frame(height: 8)
        }
    }

    private func emptyState(_ message: String, _ sub: String) -> some View {
        VStack(spacing: 4) {
            Text(message).font(.inter(14)).foregroundStyle(Palette.textSecondary)
            Text(sub).font(.psMono(10, weight: .medium)).foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .background(Palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// ── Alert cards ───────────────────────────────────────────────────────────────────

private struct EmergencyAlertCard: View {
    let aircraft: Aircraft
    let onTap: () -> Void
    @State private var borderPulse = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2).fill(Palette.emergencyRed)
                    .frame(width: 3, height: 52)
                Spacer().frame(width: 12)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18)).foregroundStyle(Palette.emergencyRed)
                Spacer().frame(width: 10)
                VStack(alignment: .leading, spacing: 0) {
                    Text(aircraft.displayCallsign).font(.psMono(14, weight: .bold))
                        .foregroundStyle(Palette.emergencyRed)
                    HStack(spacing: 8) {
                        if let sq = aircraft.squawk {
                            Text("SQ: \(sq)").font(.psMono(10, weight: .medium))
                                .foregroundStyle(Palette.emergencyRed.opacity(0.8))
                        }
                        Text(aircraft.emergency.rawValue.uppercased())
                            .font(.psMono(10, weight: .medium)).foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailingMetrics(aircraft)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Palette.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.emergencyRed.opacity(borderPulse ? 0.3 : 1.0), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { borderPulse = true }
        }
    }
}

private struct MilitaryAlertCard: View {
    let aircraft: Aircraft
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2).fill(Palette.brass).frame(width: 3, height: 52)
                Spacer().frame(width: 12)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 18)).foregroundStyle(Palette.brass)
                Spacer().frame(width: 10)
                VStack(alignment: .leading, spacing: 0) {
                    Text(aircraft.displayCallsign).font(.psMono(14, weight: .bold))
                        .foregroundStyle(Palette.brass)
                    HStack(spacing: 6) {
                        if let type = aircraft.type {
                            Text(type).font(.psMono(10, weight: .medium)).foregroundStyle(Palette.textSecondary)
                        }
                        if let reg = aircraft.registration {
                            Text(reg).font(.psMono(10, weight: .medium)).foregroundStyle(Palette.textMuted)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailingMetrics(aircraft)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Palette.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.brass.opacity(0.5), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

@ViewBuilder private func trailingMetrics(_ aircraft: Aircraft) -> some View {
    VStack(alignment: .trailing, spacing: 0) {
        Text(aircraft.altitudeDisplay).font(.psMono(12)).foregroundStyle(Palette.textPrimary)
        if let dist = aircraft.distanceNm {
            Text(String(format: "%.0f nm", dist)).font(.psMono(10, weight: .medium))
                .foregroundStyle(Palette.cyan)
        }
    }
}

private struct CustomRuleCard: View {
    let name: String
    let description: String
    let enabled: Bool
    let onToggle: () -> Void

    var body: some View {
        Button { HangarHaptics.toggle(); onToggle() } label: {
            HStack(spacing: 0) {
                Circle().fill(enabled ? Palette.cyan : Palette.textMuted).frame(width: 8, height: 8)
                Spacer().frame(width: 12)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.inter(12, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                    Text(description).font(.psMono(10, weight: .medium)).foregroundStyle(Palette.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(enabled ? "ON" : "OFF").font(.psMono(10, weight: .bold))
                    .foregroundStyle(enabled ? Palette.cyan : Palette.textMuted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Palette.cardElevated)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.glassBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
