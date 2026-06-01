import SwiftUI
import SwiftData
import BackgroundTasks
import Combine

/// Dependency-injection container and app lifecycle owner — the iOS analogue of the Hilt
/// `core:data` graph plus `PiSkyApplication`'s startup wiring. Built once in `PiSkyApp` and injected
/// into the view tree via `.environment(_:)`; screens read it with `@Environment(AppContainer.self)`.
///
/// `init()` constructs the SwiftData `ModelContainer` (schema of the 4 `@Model` records, with a
/// destructive reset-on-incompatible to mirror Room's `fallbackToDestructiveMigration`), the
/// preference/keychain stores, and every repository. `bootstrap()` requests notification auth, loads
/// the saved connection config, and starts the live updates + telemetry polling. `handleScenePhase`
/// resumes/suspends the foreground poll loop (iOS has no foreground-service equivalent) and schedules
/// the hourly-tally background task.
@MainActor
@Observable
final class AppContainer {
    // Repositories (protocol-typed per the contract).
    let aircraftRepository: AircraftRepository
    let connectionRepository: ConnectionRepository
    let tagRepository: TagRepository
    let statsRepository: StatsRepository

    // Concrete data-layer collaborators.
    let piVitals: PiVitalsRepository
    let preferences: AppPreferences
    let aircraftTypes: AircraftTypeRepository
    let notifications: NotificationManager
    let mdns: MdnsDiscovery

    /// Deep-link target set when a notification carrying an aircraft hex is tapped (→ Map).
    var pendingMapHex: String?

    // Retained so the SwiftData context stays alive for the app's lifetime.
    @ObservationIgnored private let modelContainer: ModelContainer

    init() {
        // ── SwiftData container ───────────────────────────────────────────────
        let schema = Schema([
            FavoriteRecord.self,
            TagRecord.self,
            DailyAircraftRecord.self,
            FlightTrailRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Mirror Room's destructive migration: an incompatible on-disk store is wiped and
            // recreated rather than crashing. The Pi is the source of truth, so local cache loss
            // is acceptable.
            ErrorLog.shared.log(level: "W", tag: "AppContainer",
                                message: "ModelContainer incompatible; resetting store", error: error)
            AppContainer.deleteDefaultStore()
            do {
                container = try ModelContainer(for: schema, configurations: [config])
            } catch {
                // Last resort: in-memory store so the app still runs.
                ErrorLog.shared.log(level: "E", tag: "AppContainer",
                                    message: "ModelContainer reset failed; using in-memory store", error: error)
                let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try! ModelContainer(for: schema, configurations: [mem])
            }
        }
        self.modelContainer = container
        let persistence = PersistenceStore(context: ModelContext(container))

        // ── Preferences / stores ──────────────────────────────────────────────
        let prefs = AppPreferences()
        let connectionStore = ConnectionStore()
        let statsCache = StatsCache()
        self.preferences = prefs

        // ── Concrete collaborators ────────────────────────────────────────────
        let types = AircraftTypeRepository()
        let notifs = NotificationManager()
        self.aircraftTypes = types
        self.notifications = notifs
        self.mdns = MdnsDiscovery()

        // ── Repositories ──────────────────────────────────────────────────────
        let connectionRepo = ConnectionRepositoryImpl(store: connectionStore)
        self.connectionRepository = connectionRepo
        self.aircraftRepository = AircraftRepositoryImpl(
            store: persistence, prefs: prefs, aircraftTypes: types, notifications: notifs
        )
        self.tagRepository = TagRepositoryImpl(store: persistence)
        self.statsRepository = StatsRepositoryImpl(connection: connectionRepo, cache: statsCache)
        self.piVitals = PiVitalsRepository(connection: connectionRepo)

        // Let notification taps deep-link to the Map.
        notifs.container = self

        // BG task handlers MUST be registered while the app is still launching — iOS throws an
        // (uncatchable) exception if this happens after launch finishes, so it cannot be deferred
        // to bootstrap(). init() runs from PiSkyApp's @State initializer, i.e. during launch.
        registerBackgroundTask()
    }

    /// Request notification auth, load the saved config, and kick off live updates + telemetry.
    func bootstrap() async {
        await notifications.requestAuthorization()
        let config = await connectionRepository.getConfig()
        aircraftRepository.startLiveUpdates(config: config)
        piVitals.startPolling()
    }

    /// `.active` → resume the poll loop; `.background` → stop it and schedule the hourly-tally
    /// background task (iOS suspends networking when backgrounded — see PORTING_NOTES §1).
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Task {
                let config = await self.connectionRepository.getConfig()
                self.aircraftRepository.startLiveUpdates(config: config)
                self.piVitals.startPolling()
            }
        case .background:
            aircraftRepository.stopLiveUpdates()
            scheduleHourlyTally()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Background task (hourly tally)

    private var bgTaskRegistered = false

    private func registerBackgroundTask() {
        guard !bgTaskRegistered else { return }
        bgTaskRegistered = true
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: NotificationManager.bgTaskIdentifier, using: nil
        ) { [weak self] task in
            guard let self, let appTask = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            self.handleHourlyTally(appTask)
        }
    }

    private func handleHourlyTally(_ task: BGAppRefreshTask) {
        // Re-schedule the next occurrence immediately so the chain continues.
        scheduleHourlyTally()
        let work = Task {
            await self.runHourlyTally()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// Hourly tally — port of `HourlyTallyWorker.doWork`: only 06:00–22:00 local; refresh Pi stats,
    /// take max of local vs Pi-authoritative counts, post the summary notification.
    private func runHourlyTally() async {
        let hour = Calendar.current.component(.hour, from: Date())
        guard (6...22).contains(hour) else { return }

        try? await statsRepository.refresh24hStats()
        let rolling = await firstValue(statsRepository.observe24hStats()) ?? .empty
        let unique = await firstValue(aircraftRepository.observeUniqueToday()) ?? []
        let tags = await firstValue(tagRepository.observeAll()) ?? []

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let startMs = Int64(startOfDay.timeIntervalSince1970 * 1000)
        let taggedToday = tags.filter { $0.timestamp >= startMs }.count
        let loggedToday = max(unique.count, rolling.aircraftSeen)
        let militaryToday = max(unique.filter { $0.isMilitary }.count, rolling.militarySeen)

        notifications.postTally(loggedToday: loggedToday, taggedToday: taggedToday, militaryToday: militaryToday)
    }

    private func scheduleHourlyTally() {
        let request = BGAppRefreshTaskRequest(identifier: NotificationManager.bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            ErrorLog.shared.log(level: "D", tag: "AppContainer", message: "BGTask submit failed", error: error)
        }
    }

    // MARK: - Helpers

    /// Pull the current value out of a replaying `AnyPublisher` (our subjects always have one).
    private func firstValue<T>(_ publisher: AnyPublisher<T, Never>) async -> T? {
        await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
            var cancellable: AnyCancellable?
            var resumed = false
            cancellable = publisher.first().sink { value in
                if !resumed { resumed = true; cont.resume(returning: value) }
                cancellable?.cancel()
            }
        }
    }

    private static func deleteDefaultStore() {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return }
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            try? FileManager.default.removeItem(at: appSupport.appendingPathComponent(name))
        }
    }
}
