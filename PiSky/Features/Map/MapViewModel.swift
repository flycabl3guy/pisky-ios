import SwiftUI
import Combine

/// Which map surface is showing — the iOS analog of the Android `OsmMapType` selector, trimmed to
/// the two paths the iOS port exposes (PORTING_NOTES §2): the live tar1090 `WKWebView` and the
/// pure-`Canvas` STARS scope.
enum MapMode: String, CaseIterable {
    case live      // tar1090 WKWebView — primary
    case scope     // RadarScope2 STARS-look Canvas overlay

    var title: String { self == .live ? "Live" : "Scope" }
}

/// Column the (in-scope) stats table can be sorted by — `TableSortColumn`.
enum TableSortColumn: CaseIterable {
    case icao, ident, squawk, altitude, speed, distance, heading, msgs
}

struct TableSort: Equatable {
    var column: TableSortColumn = .distance
    var ascending: Bool = true
}

/// Source-classification chips — `AcSource` in MapViewModel.kt.
enum AcSource: CaseIterable { case adsb, uat, mlat, tisb, other }

/// Map filter state — `MapFilter` in MapViewModel.kt. Nil range bounds mean "no bound that side".
struct MapFilter: Equatable {
    var altMinFt: Int? = nil
    var altMaxFt: Int? = nil
    var spdMinKt: Int? = nil
    var spdMaxKt: Int? = nil
    var typeFilter: String = ""
    var identFilter: String = ""
    var sources: Set<AcSource> = Set(AcSource.allCases)
    var hideMlat: Bool = false
    var hideGroundVehicles: Bool = false
    var militaryOnly: Bool = false
    var emergencyOnly: Bool = false

    var enabledCount: Int {
        [
            altMinFt != nil || altMaxFt != nil,
            spdMinKt != nil || spdMaxKt != nil,
            !typeFilter.isEmpty,
            !identFilter.isEmpty,
            sources.count != AcSource.allCases.count,
            hideMlat,
            hideGroundVehicles,
            militaryOnly,
            emergencyOnly,
        ].filter { $0 }.count
    }
}

/// `MapViewModel` — port of `MapViewModel.kt`. Follows the iOS VM convention (contract §2).
@MainActor @Observable
final class MapViewModel {
    // ── Observable state ──────────────────────────────────────────────────────
    private(set) var aircraft: [Aircraft] = []
    private(set) var receiverStats: ReceiverStats?
    private(set) var liveStats: LiveStats?
    private(set) var connectionMode: ConnectionMode = .disconnected
    private(set) var selectedHex: String?

    // Two-way-bound UI state.
    var mode: MapMode = .live { didSet { if mode != oldValue { applyPollInterval() } } }
    var mapFilter = MapFilter()
    var tableSort = TableSort()
    var searchQuery: String = ""

    /// The base URL the WebView loads — resolved from `connectionRepository.getConfig()`.
    private(set) var baseURL: URL?

    var selectedAircraft: Aircraft? { selectedHex.flatMap { h in aircraft.first { $0.hex == h } } }

    /// Aircraft as rendered on the scope (filter applied).
    var mapAircraft: [Aircraft] { aircraft.filter { $0.matches(mapFilter) } }

    /// Filtered + sorted, position-only (matches the Android stats table semantics).
    var sortedAircraft: [Aircraft] {
        let withPos = mapAircraft.filter(\.hasPosition)
        let cmp: (Aircraft, Aircraft) -> Bool
        switch tableSort.column {
        case .icao:     cmp = { $0.hex < $1.hex }
        case .ident:    cmp = { $0.displayCallsign < $1.displayCallsign }
        case .squawk:   cmp = { ($0.squawk ?? "") < ($1.squawk ?? "") }
        case .altitude: cmp = { ($0.altitudeBaro ?? .min) < ($1.altitudeBaro ?? .min) }
        case .speed:    cmp = { ($0.groundSpeed ?? -1) < ($1.groundSpeed ?? -1) }
        case .distance: cmp = { ($0.distanceNm ?? .greatestFiniteMagnitude) < ($1.distanceNm ?? .greatestFiniteMagnitude) }
        case .heading:  cmp = { ($0.track ?? -1) < ($1.track ?? -1) }
        case .msgs:     cmp = { $0.messages < $1.messages }
        }
        let sorted = withPos.sorted(by: cmp)
        return tableSort.ascending ? sorted : sorted.reversed()
    }

    /// Search results (≥2 chars) — callsign / hex / type / squawk match. Capped at 8.
    var searchResults: [Aircraft] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2 else { return [] }
        return aircraft.filter { ac in
            ac.displayCallsign.lowercased().contains(q)
                || ac.hex.lowercased().contains(q)
                || (ac.type?.lowercased().contains(q) ?? false)
                || (ac.squawk?.contains(q) ?? false)
        }.prefix(8).map { $0 }
    }

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private weak var container: AppContainer?
    private var started = false

    func start(_ c: AppContainer, initialSelectHex: String?) {
        guard !started else { return }
        started = true
        container = c

        if let hex = initialSelectHex { selectedHex = hex }

        c.aircraftRepository.observeAircraft()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.aircraft = $0 }
            .store(in: &bag)
        c.aircraftRepository.observeReceiverStats()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.receiverStats = $0 }
            .store(in: &bag)
        c.aircraftRepository.observeLiveStats()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.liveStats = $0 }
            .store(in: &bag)
        c.aircraftRepository.observeConnectionMode()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.connectionMode = $0 }
            .store(in: &bag)

        // Resolve the WebView base URL + start live updates on the latest config.
        c.connectionRepository.observeConfig()
            .receive(on: RunLoop.main)
            .sink { [weak self] config in
                guard let self else { return }
                self.baseURL = URL(string: config.baseUrl)
                if !config.hostname.isEmpty { c.aircraftRepository.startLiveUpdates(config: config) }
            }
            .store(in: &bag)

        applyPollInterval()
    }

    // ── Intents ────────────────────────────────────────────────────────────────
    func selectAircraft(_ hex: String) { selectedHex = hex }
    func clearSelection() { selectedHex = nil }
    func resetFilter() { mapFilter = MapFilter() }

    func toggleSort(_ column: TableSortColumn) {
        if tableSort.column == column { tableSort.ascending.toggle() }
        else { tableSort = TableSort(column: column, ascending: true) }
    }

    func toggleFavorite(_ hex: String, isFavorite: Bool) {
        Task { [container] in
            if isFavorite { await container?.aircraftRepository.removeFavorite(hex: hex) }
            else { await container?.aircraftRepository.addFavorite(hex: hex) }
        }
    }

    /// Dedupe app-side polling: the tar1090 WebView already pulls aircraft.json at 1 Hz, so bump
    /// the repo poll to 3 s when Live is showing; the native scope needs the 1 s cadence.
    /// (Ported from the Android `_mapType.collect { … setPollIntervalMs }`.)
    private func applyPollInterval() {
        container?.aircraftRepository.setPollIntervalMs(mode == .live ? 3000 : 1000)
    }
}

extension Aircraft {
    /// `Aircraft.sourceChip()` — first-match wins.
    fileprivate var sourceChip: AcSource {
        if isMlat { return .mlat }
        if isTisb { return .tisb }
        if dataSource == .uat978 { return .uat }
        if dataSource == .adsb1090 { return .adsb }
        return .other
    }

    /// `Aircraft.matches(MapFilter)` — ported field-for-field.
    fileprivate func matches(_ f: MapFilter) -> Bool {
        if f.militaryOnly && !isMilitary { return false }
        if f.emergencyOnly && emergency == .none { return false }
        if f.hideMlat && isMlat { return false }
        if f.hideGroundVehicles && (isOnGround || (category?.hasPrefix("C") ?? false)) { return false }
        if let lo = f.altMinFt, (altitudeBaro ?? .min) < lo { return false }
        if let hi = f.altMaxFt, (altitudeBaro ?? .max) > hi { return false }
        if let lo = f.spdMinKt, (groundSpeed ?? -1) < Double(lo) { return false }
        if let hi = f.spdMaxKt, (groundSpeed ?? .greatestFiniteMagnitude) > Double(hi) { return false }
        if !f.typeFilter.isEmpty,
           !(type?.range(of: f.typeFilter, options: .caseInsensitive) != nil) { return false }
        if !f.identFilter.isEmpty,
           displayCallsign.range(of: f.identFilter, options: .caseInsensitive) == nil { return false }
        if !f.sources.contains(sourceChip) { return false }
        return true
    }
}
