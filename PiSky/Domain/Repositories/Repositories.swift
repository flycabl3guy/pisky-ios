import Foundation
import Combine

/// Repository protocols (the `core:domain/repository` interfaces). Kotlin `Flow`/`StateFlow`
/// observation maps to Combine `AnyPublisher<…, Never>` (hot, multicast, replays latest — the
/// `CurrentValueSubject` semantics the implementations back them with). `suspend` maps to
/// `async`/`async throws`. Implementations live in the Data layer as actors / @MainActor classes.

protocol AircraftRepository: AnyObject {
    // Observation
    func observeAircraft() -> AnyPublisher<[Aircraft], Never>
    func observeLiveStats() -> AnyPublisher<LiveStats?, Never>
    func observeMilitaryAircraft() -> AnyPublisher<[Aircraft], Never>
    func observeDailyCount() -> AnyPublisher<DailyCount, Never>
    func observeUniqueToday() -> AnyPublisher<[UniqueAircraft], Never>
    func observeMilitaryHistory() -> AnyPublisher<[UniqueAircraft], Never>
    func observeReceiverStats() -> AnyPublisher<ReceiverStats?, Never>
    func observeConnectionMode() -> AnyPublisher<ConnectionMode, Never>
    func observeFavoriteHexCodes() -> AnyPublisher<Set<String>, Never>

    // Control
    func startLiveUpdates(config: ConnectionConfig)
    func stopLiveUpdates()
    func setPollIntervalMs(_ ms: Int)

    // One-shots / commands
    func refreshAircraft(config: ConnectionConfig) async throws
    func getReceiverStats(config: ConnectionConfig) async throws -> ReceiverStats
    func testConnection(config: ConnectionConfig) async throws -> ReceiverStats
    func getFavoriteHexCodes() async -> [String]
    func addFavorite(hex: String) async
    func removeFavorite(hex: String) async
}

protocol ConnectionRepository: AnyObject {
    func observeConfig() -> AnyPublisher<ConnectionConfig, Never>
    func saveConfig(_ config: ConnectionConfig) async
    func getConfig() async -> ConnectionConfig
    func setOnboarded(_ value: Bool) async
    func isOnboarded() async -> Bool
}

protocol TagRepository: AnyObject {
    func observeAll() -> AnyPublisher<[AircraftTag], Never>
    func observeTaggedHexes() -> AnyPublisher<[String: TagCategory], Never>
    func observeCount() -> AnyPublisher<Int, Never>
    func tag(hex: String, category: TagCategory, note: String) async
    func untag(hex: String) async
    func getTag(hex: String) async -> AircraftTag?
}
