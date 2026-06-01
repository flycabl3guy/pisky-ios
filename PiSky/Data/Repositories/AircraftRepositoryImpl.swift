import Foundation
import Combine

/// `AircraftRepository` — port of `AircraftRepositoryImpl`. Owns the live HTTP poll loop (default
/// 1000 ms), merges the enriched/raw 1090 feed with the UAT 978 feed (case-insensitive dedup, ADS-B
/// wins, sorted by distance), records daily-aircraft, fires notifications, and updates live stats.
/// Favorites live in `PersistenceStore`. All published values land on the main thread via
/// `@MainActor`-confined `CurrentValueSubject`s; the poll loop runs in a detached `Task` driving the
/// `actor APIClient` for I/O.
@MainActor
final class AircraftRepositoryImpl: AircraftRepository {
    private let store: PersistenceStore
    private let prefs: AppPreferences
    private let aircraftTypes: AircraftTypeRepository
    private let notifications: NotificationManager

    // Observed state.
    private let aircraftSubject       = CurrentValueSubject<[Aircraft], Never>([])
    private let liveStatsSubject      = CurrentValueSubject<LiveStats?, Never>(nil)
    private let receiverStatsSubject  = CurrentValueSubject<ReceiverStats?, Never>(nil)
    private let connectionModeSubject = CurrentValueSubject<ConnectionMode, Never>(.disconnected)
    private let favoritesSubject      = CurrentValueSubject<Set<String>, Never>([])
    private let dailyCountSubject     = CurrentValueSubject<DailyCount, Never>(.zero)
    private let uniqueTodaySubject    = CurrentValueSubject<[UniqueAircraft], Never>([])
    private let militaryHistorySubject = CurrentValueSubject<[UniqueAircraft], Never>([])

    private var receiverLat: Double? = nil
    private var receiverLon: Double? = nil

    private var liveTask: Task<Void, Never>? = nil
    private var liveConfig: ConnectionConfig? = nil
    private var pollIntervalMs: Int = 1000
    private var lastDate: String = ""

    private static let cowdenLat = 39.24554
    private static let cowdenLon = -88.85792

    /// America/Chicago — matches the Kotlin `ZoneId.of("America/Chicago")` daily-rollover boundary.
    private static let centralCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        return c
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = centralCalendar
        f.timeZone = centralCalendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(store: PersistenceStore,
         prefs: AppPreferences,
         aircraftTypes: AircraftTypeRepository,
         notifications: NotificationManager) {
        self.store = store
        self.prefs = prefs
        self.aircraftTypes = aircraftTypes
        self.notifications = notifications
        Task {
            await refreshFavorites()
            await refreshDailyObservers()
        }
    }

    // MARK: - Observation

    func observeAircraft() -> AnyPublisher<[Aircraft], Never> { aircraftSubject.eraseToAnyPublisher() }
    func observeLiveStats() -> AnyPublisher<LiveStats?, Never> { liveStatsSubject.eraseToAnyPublisher() }
    func observeMilitaryAircraft() -> AnyPublisher<[Aircraft], Never> {
        aircraftSubject.map { $0.filter { $0.isMilitary } }.eraseToAnyPublisher()
    }
    func observeDailyCount() -> AnyPublisher<DailyCount, Never> { dailyCountSubject.eraseToAnyPublisher() }
    func observeUniqueToday() -> AnyPublisher<[UniqueAircraft], Never> { uniqueTodaySubject.eraseToAnyPublisher() }
    func observeMilitaryHistory() -> AnyPublisher<[UniqueAircraft], Never> { militaryHistorySubject.eraseToAnyPublisher() }
    func observeReceiverStats() -> AnyPublisher<ReceiverStats?, Never> { receiverStatsSubject.eraseToAnyPublisher() }
    func observeConnectionMode() -> AnyPublisher<ConnectionMode, Never> { connectionModeSubject.eraseToAnyPublisher() }
    func observeFavoriteHexCodes() -> AnyPublisher<Set<String>, Never> { favoritesSubject.eraseToAnyPublisher() }

    // MARK: - Control

    func startLiveUpdates(config: ConnectionConfig) {
        // Idempotent — if an active loop already serves this exact config, leave it running.
        if let task = liveTask, !task.isCancelled, liveConfig == config { return }
        liveTask?.cancel()
        liveConfig = config

        liveTask = Task { [weak self] in
            guard let self else { return }
            // Receiver stats first (for distance lat/lon), then OTA mil-DB sync (non-blocking).
            _ = try? await self.getReceiverStats(config: config)
            Task { await self.syncMilDb(config: config) }
            await self.runPollLoop(config: config)
        }
    }

    private func runPollLoop(config: ConnectionConfig) async {
        connectionModeSubject.send(.pollingHttp)
        while !Task.isCancelled {
            do {
                try await refreshAircraft(config: config)
                connectionModeSubject.send(.pollingHttp)
            } catch {
                connectionModeSubject.send(.error)
                ErrorLog.shared.log(level: "W", tag: "Aircraft", message: "poll error", error: error)
            }
            let ms = max(pollIntervalMs, 500)
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
        }
    }

    func stopLiveUpdates() {
        liveTask?.cancel()
        liveTask = nil
        liveConfig = nil
        connectionModeSubject.send(.disconnected)
    }

    func setPollIntervalMs(_ ms: Int) {
        pollIntervalMs = max(ms, 500)
    }

    // MARK: - One-shots / commands

    func refreshAircraft(config: ConnectionConfig) async throws {
        let api = APIClient(config: config)
        let favHexes = favoritesSubject.value
        let milHexes = aircraftTypes.getMilHexSet()
        let milNames = aircraftTypes.getMilHexNameMap()

        // Prefer L2's enriched feed; fall back to raw readsb so the app never goes dark.
        let response: AircraftResponseDto
        if let enriched = try? await api.getEnrichedAircraft() {
            response = enriched
        } else {
            response = try await api.getAircraft()
        }
        let adsb = response.aircraft.map {
            $0.toDomain(receiverLat: receiverLat, receiverLon: receiverLon,
                        favoriteHexes: favHexes, dataSource: .adsb1090,
                        milCsvHexes: milHexes, milCsvNames: milNames)
        }

        let uat: [Aircraft] = (try? await api.getUatAircraft())?.aircraft.map {
            $0.toDomain(receiverLat: receiverLat, receiverLon: receiverLon,
                        favoriteHexes: favHexes, dataSource: .uat978,
                        milCsvHexes: milHexes, milCsvNames: milNames)
        } ?? []

        // Case-insensitive dedup: ADS-B wins over UAT; distinct by lowercased hex; sort by distance.
        let adsbHexes = Set(adsb.map { $0.hex.lowercased() })
        var seen = Set<String>()
        let merged = (adsb + uat.filter { !adsbHexes.contains($0.hex.lowercased()) })
            .filter { seen.insert($0.hex.lowercased()).inserted }
            .sorted { ($0.distanceNm ?? .greatestFiniteMagnitude) < ($1.distanceNm ?? .greatestFiniteMagnitude) }

        aircraftSubject.send(merged)
        await recordDailyAircraft(merged)
        notifications.fireNotifications(for: merged, prefs: prefs)

        // Live stats — overlay locally-derived counts on the parsed stats block.
        if let statsDto = try? await api.getStats() {
            var live = statsDto.toLiveStats()
            live.aircraftTotal = merged.count
            live.aircraftWithPos = merged.filter { $0.hasPosition }.count
            live.aircraftWithMlat = merged.filter { $0.isMlat }.count
            live.maxRangeNm = merged.compactMap { $0.distanceNm }.max()
            liveStatsSubject.send(live)
        }
    }

    func getReceiverStats(config: ConnectionConfig) async throws -> ReceiverStats {
        let api = APIClient(config: config)
        let receiver = try await api.getReceiver().toDomain()
        // Ultrafeeder hides lat/lon by default; fall back to the known Cowden antenna coords so
        // distance + bearing math doesn't go null.
        receiverLat = receiver.latitude ?? Self.cowdenLat
        receiverLon = receiver.longitude ?? Self.cowdenLon
        let withCoords: ReceiverStats
        if receiver.latitude == nil || receiver.longitude == nil {
            withCoords = ReceiverStats(version: receiver.version, refreshIntervalMs: receiver.refreshIntervalMs,
                                       latitude: Self.cowdenLat, longitude: Self.cowdenLon, antenna: receiver.antenna)
        } else {
            withCoords = receiver
        }
        receiverStatsSubject.send(withCoords)
        return withCoords
    }

    func testConnection(config: ConnectionConfig) async throws -> ReceiverStats {
        try await getReceiverStats(config: config)
    }

    // MARK: - Favorites

    func getFavoriteHexCodes() async -> [String] {
        await store.allFavoriteHexes()
    }

    func addFavorite(hex: String) async {
        await store.addFavorite(hex: hex)
        await refreshFavorites()
    }

    func removeFavorite(hex: String) async {
        await store.removeFavorite(hex: hex)
        await refreshFavorites()
    }

    private func refreshFavorites() async {
        favoritesSubject.send(Set(await store.allFavoriteHexes()))
    }

    // MARK: - Daily aircraft + observers

    private func recordDailyAircraft(_ aircraft: [Aircraft]) async {
        let today = Self.dateFormatter.string(from: Date())
        let entries: [DailyAircraftRecord] = aircraft
            .filter { !$0.hex.isEmpty }
            .map { ac in
                // dump1090-fa leaves `t` blank for most military; fall back to the bundled mil CSV.
                let resolvedType = ac.type?.trimmedNonBlank
                    ?? (ac.isMilitary ? aircraftTypes.lookupMilHex(ac.hex)?.typeName : nil)
                return DailyAircraftRecord(
                    date: today, hex: ac.hex, type: resolvedType,
                    callsign: ac.callsign, registration: ac.registration, isMilitary: ac.isMilitary
                )
            }
        guard !entries.isEmpty else { return }
        // 30-day retention.
        let cutoffDate = Self.centralCalendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let cutoff = Self.dateFormatter.string(from: cutoffDate)
        await store.upsertDailyAircraft(entries, pruneBeforeDate: cutoff)
        await refreshDailyObservers()
    }

    /// Recompute the daily-count / unique-today / military-history publishers (SwiftData has no
    /// reactive query, so we re-read after writes and on the day rollover).
    private func refreshDailyObservers() async {
        let today = Self.dateFormatter.string(from: Date())
        lastDate = today
        let yesterdayDate = Self.centralCalendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let yesterday = Self.dateFormatter.string(from: yesterdayDate)

        let todayCount = await store.dailyCountForDate(today)
        let yesterdayCount = await store.dailyCountForDate(yesterday)
        dailyCountSubject.send(DailyCount(today: todayCount, yesterday: yesterdayCount))

        uniqueTodaySubject.send((await store.dailyForDate(today)).map(Self.toUnique))
        militaryHistorySubject.send((await store.allMilitaryDaily()).map(Self.toUnique))
    }

    private static func toUnique(_ r: DailyAircraftRecord) -> UniqueAircraft {
        UniqueAircraft(hex: r.hex, type: r.type, callsign: r.callsign,
                       registration: r.registration, firstSeenMs: r.firstSeenMs, isMilitary: r.isMilitary)
    }

    // MARK: - OTA mil DB

    /// Non-blocking: pull the Pi's military DB; silent fallback to bundled data on any failure.
    private func syncMilDb(config: ConnectionConfig) async {
        do {
            let response = try await APIClient(config: config).getMilDb()
            if response.count > 0 {
                aircraftTypes.applyOtaUpdate(response)
                ErrorLog.shared.log(level: "I", tag: "Aircraft",
                                    message: "OTA mil DB synced: \(response.count) (\(response.version))")
            }
        } catch {
            ErrorLog.shared.log(level: "D", tag: "Aircraft", message: "OTA mil DB not available", error: error)
        }
    }
}
