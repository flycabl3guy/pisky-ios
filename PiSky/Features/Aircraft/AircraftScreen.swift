import SwiftUI
import Combine

/// Sort modes for the live aircraft list. Port of `AircraftSort` in AircraftViewModel.kt.
enum AircraftSort: String, CaseIterable, Identifiable {
    case distance, altitude, callsign, messages
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

// ─────────────────────────────────────────────────────────────────────────────
// AircraftViewModel
// ─────────────────────────────────────────────────────────────────────────────

@MainActor @Observable
final class AircraftViewModel {
    private(set) var aircraft: [Aircraft] = []
    private(set) var emergencyAircraft: [Aircraft] = []
    private(set) var taggedHexes: [String: TagCategory] = [:]

    // Two-way-bound UI state.
    var query: String = "" { didSet { searchSubject.send(query) } }
    var sortMode: AircraftSort = .distance { didSet { sortSubject.send(sortMode) } }
    var showOnlyWithPosition: Bool = false { didSet { posSubject.send(showOnlyWithPosition) } }

    @ObservationIgnored private let searchSubject = CurrentValueSubject<String, Never>("")
    @ObservationIgnored private let sortSubject = CurrentValueSubject<AircraftSort, Never>(.distance)
    @ObservationIgnored private let posSubject = CurrentValueSubject<Bool, Never>(false)
    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private weak var container: AppContainer?
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true; container = c

        // Filtered + sorted live list — combine the feed with debounced query / sort / filter.
        c.aircraftRepository.observeAircraft()
            .combineLatest(
                searchSubject.debounce(for: .milliseconds(150), scheduler: RunLoop.main),
                sortSubject,
                posSubject
            )
            .map { list, query, sort, posOnly in
                Self.process(list: list, query: query, sort: sort, posOnly: posOnly)
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.aircraft = $0 }
            .store(in: &bag)

        // Anyone currently squawking an emergency (excludes NONE).
        c.aircraftRepository.observeAircraft()
            .map { $0.filter { $0.emergency != .none } }
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.emergencyAircraft = $0 }
            .store(in: &bag)

        c.tagRepository.observeTaggedHexes()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.taggedHexes = $0 }
            .store(in: &bag)
    }

    /// The live aircraft matching `hex` from the freshest feed (so the sheet stays current).
    func aircraft(for hex: String) -> Aircraft? { aircraft.first { $0.hex == hex } }

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

    func untag(_ hex: String) {
        Task { await container?.tagRepository.untag(hex: hex) }
    }

    /// Filter (position + multi-field search) then sort. Faithful port of the Kotlin `combine`.
    private static func process(list: [Aircraft], query: String, sort: AircraftSort, posOnly: Bool) -> [Aircraft] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = list.filter { ac in
            if posOnly && !ac.hasPosition { return false }
            if q.isEmpty { return true }
            return ac.hex.lowercased().contains(q)
                || (ac.callsign?.lowercased().contains(q) ?? false)
                || (ac.registration?.lowercased().contains(q) ?? false)
                || (ac.type?.lowercased().contains(q) ?? false)
        }
        switch sort {
        case .distance:
            return filtered.sorted { lhs, rhs in nilLast(lhs.distanceNm, rhs.distanceNm, by: <) }
        case .altitude:
            return filtered.sorted { lhs, rhs in nilLast(lhs.altitudeBaro, rhs.altitudeBaro, by: >) }
        case .callsign:
            return filtered.sorted { $0.displayCallsign < $1.displayCallsign }
        case .messages:
            return filtered.sorted { $0.messages > $1.messages }
        }
    }

    /// nulls-last comparator: present values ordered by `cmp`, nils sink to the end.
    private static func nilLast<T>(_ a: T?, _ b: T?, by cmp: (T, T) -> Bool) -> Bool {
        switch (a, b) {
        case let (x?, y?): return cmp(x, y)
        case (nil, _?):    return false
        case (_?, nil):    return true
        case (nil, nil):   return false
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// AircraftScreen
// ─────────────────────────────────────────────────────────────────────────────

struct AircraftScreen: View {
    let onAircraftSelected: (String) -> Void

    @Environment(AppContainer.self) private var container
    @Environment(\.dimens) private var dimens
    @State private var vm = AircraftViewModel()
    @State private var sheetTarget: HexTarget?

    var body: some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            header
            EmergencyBanner(emergencyAircraft: vm.emergencyAircraft) { onAircraftSelected($0.hex) }
            searchBar
                .padding(.horizontal, dimens.screenPadding)
            Spacer().frame(height: 10)
            filterRow
                .padding(.horizontal, dimens.screenPadding)
            Spacer().frame(height: 4)
            list
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
            Image(systemName: "airplane")
                .font(.system(size: 18)).foregroundStyle(Palette.brass)
            Text("Aircraft").font(.inter(16, weight: .bold)).foregroundStyle(Palette.brass)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(vm.aircraft.count)")
                .font(.psMono(12, weight: .bold)).foregroundStyle(Palette.cyan)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Palette.cyan.opacity(0.15))
                .overlay(Capsule().strokeBorder(Palette.cyan.opacity(0.4), lineWidth: 1))
                .clipShape(Capsule())
        }
        .padding(.horizontal, dimens.screenPadding)
        .padding(.vertical, 10)
    }

    private var searchBar: some View {
        @Bindable var vm = vm
        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16)).foregroundStyle(Palette.cyan.opacity(0.7))
            TextField("", text: $vm.query, prompt:
                        Text("Search callsign, hex, type…").foregroundStyle(Palette.textMuted))
                .font(.inter(12)).foregroundStyle(Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .tint(Palette.cyan)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Palette.glassBackground)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Palette.glassBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var filterRow: some View {
        @Bindable var vm = vm
        return HStack(spacing: 8) {
            Button {
                HangarHaptics.toggle(); vm.showOnlyWithPosition.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "location.fill").font(.system(size: 12))
                    Text("With Position").font(.inter(11))
                }
                .foregroundStyle(vm.showOnlyWithPosition ? Palette.cyan : Palette.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(vm.showOnlyWithPosition ? Palette.cyan.opacity(0.15) : Palette.cardBackground)
                .overlay(Capsule().strokeBorder(
                    vm.showOnlyWithPosition ? Palette.cyan.opacity(0.5) : Palette.outline, lineWidth: 1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                ForEach(AircraftSort.allCases) { sort in
                    Button { vm.sortMode = sort } label: {
                        if vm.sortMode == sort { Label(sort.label, systemImage: "checkmark") }
                        else { Text(sort.label) }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 18)).foregroundStyle(Palette.cyan)
                    .frame(width: 36, height: 36)
            }
        }
    }

    @ViewBuilder private var list: some View {
        if vm.aircraft.isEmpty {
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "airplane").font(.system(size: 44)).foregroundStyle(Palette.textMuted)
                Spacer().frame(height: 12)
                Text("No aircraft").font(.inter(14)).foregroundStyle(Palette.textSecondary)
                Spacer().frame(height: 4)
                Text("Waiting for data…").font(.inter(12)).foregroundStyle(Palette.textMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: dimens.itemSpacing) {
                    ForEach(vm.aircraft) { ac in
                        AircraftRowCard(
                            aircraft: ac,
                            onTap: { onAircraftSelected(ac.hex); sheetTarget = HexTarget(hex: ac.hex) },
                            onFavorite: { vm.toggleFavorite(ac) }
                        )
                    }
                }
                .padding(.horizontal, dimens.screenPadding)
                .padding(.vertical, 8)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// AircraftRowCard
// ─────────────────────────────────────────────────────────────────────────────

private struct AircraftRowCard: View {
    let aircraft: Aircraft
    let onTap: () -> Void
    let onFavorite: () -> Void

    private var isEmergency: Bool { aircraft.emergency != .none }
    private var stripColor: Color { aircraftAltitudeColor(aircraft) }
    private var callsignColor: Color {
        if isEmergency { return Palette.emergencyRed }
        if aircraft.isMilitary { return Palette.brass }
        if aircraft.isMlat { return Palette.signalAmberHot }
        return Palette.cyan
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Rectangle().fill(stripColor).frame(width: 3)
                HStack(spacing: 0) {
                    identityColumn.frame(maxWidth: .infinity, alignment: .leading)
                    altitudeColumn.padding(.trailing, 10)
                    distanceColumn.padding(.trailing, 6)
                    Button { onFavorite() } label: {
                        Image(systemName: aircraft.isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 18))
                            .foregroundStyle(aircraft.isFavorite ? Palette.brassBright : Palette.textMuted)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 11)
            }
            .frame(minHeight: 72)
            .background(Palette.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isEmergency ? Palette.emergencyRed.opacity(0.5) : Palette.glassBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var identityColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(aircraft.displayCallsign)
                .font(.psMono(14, weight: .bold)).foregroundStyle(callsignColor)
            Text(subtitle).font(.psMono(10, weight: .medium)).foregroundStyle(Palette.textMuted)
            if let route = aircraft.routeDisplay {
                Text(route).font(.psMono(10, weight: .semibold)).foregroundStyle(Palette.cyan)
            }
            HStack(spacing: 4) {
                if aircraft.isMlat { RowBadge("MLAT", Palette.signalAmberHot) }
                if aircraft.isTisb { RowBadge("TIS-B", Palette.cyan) }
                if aircraft.dataSource == .uat978 { RowBadge("978", Palette.cyan) }
                switch aircraft.classification.level {
                case .military:       RowBadge("MIL", Palette.brass)
                case .likelyMilitary: RowBadge("MIL?", Palette.brass.opacity(0.7))
                default:              EmptyView()
                }
            }
            .padding(.top, 1)
        }
    }

    private var subtitle: String {
        var s = aircraft.hex.uppercased()
        if let reg = aircraft.registration { s += " · \(reg)" }
        if let type = aircraft.type { s += " · \(type)" }
        return s
    }

    @ViewBuilder private var altitudeColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(aircraft.altitudeDisplay).font(.psMono(12)).foregroundStyle(stripColor)
            if let vr = aircraft.verticalRate, vr != 0 {
                HStack(spacing: 2) {
                    Image(systemName: vr > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 10))
                        .foregroundStyle(vr > 0 ? Palette.altLow : Palette.signalAmberHot)
                    Text(Fmt.grouped(abs(vr))).font(.psMono(10)).foregroundStyle(Palette.textMuted)
                }
            }
        }
    }

    @ViewBuilder private var distanceColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let dist = aircraft.distanceNm {
                Text(String(format: "%.0f nm", dist)).font(.psMono(12)).foregroundStyle(Palette.cyan)
            }
            Text(aircraft.speedDisplay).font(.psMono(10)).foregroundStyle(Palette.textMuted)
        }
    }
}

private struct RowBadge: View {
    let label: String
    let tint: Color
    init(_ label: String, _ tint: Color) { self.label = label; self.tint = tint }
    var body: some View {
        Text(label).font(.psMono(9, weight: .medium)).foregroundStyle(tint)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(tint.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Identifiable wrapper for an aircraft hex — drives `.sheet(item:)` without a global
/// `String: Identifiable` conformance that could collide with other features in the same module.
struct HexTarget: Identifiable, Equatable { let hex: String; var id: String { hex } }
