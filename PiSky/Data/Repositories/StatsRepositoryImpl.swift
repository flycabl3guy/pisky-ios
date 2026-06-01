import Foundation
import Combine

/// `StatsRepository` — port of the Android `StatsRepository` class. Pi is the single source of
/// truth: fetch `/pi-rolling-24h.json`, map `.preferred` → `Rolling24hStats`, cache via `StatsCache`,
/// and on failure serve the cache (unless it's > 24 h expired). Also exposes the L2-side military
/// rolling-24h history.
@MainActor
final class StatsRepositoryImpl: StatsRepository {
    private let connection: ConnectionRepository
    private let cache: StatsCache

    private let statsSubject: CurrentValueSubject<Rolling24hStats, Never>
    private let militaryHistorySubject = CurrentValueSubject<[MilitaryHistoryEntry], Never>([])

    init(connection: ConnectionRepository, cache: StatsCache) {
        self.connection = connection
        self.cache = cache
        // Seed from cache, discarding if older than 24 h (mirrors the Kotlin init block).
        let cached = cache.load()
        self.statsSubject = .init(cached.isExpired ? .empty : cached)
    }

    func observe24hStats() -> AnyPublisher<Rolling24hStats, Never> {
        statsSubject.eraseToAnyPublisher()
    }

    func observeMilitaryHistory() -> AnyPublisher<[MilitaryHistoryEntry], Never> {
        militaryHistorySubject.eraseToAnyPublisher()
    }

    @discardableResult
    func refresh24hStats() async throws -> Rolling24hStats {
        let config = await connection.getConfig()
        let api = APIClient(config: config)
        do {
            let response = try await api.getRolling24h()
            let fresh = response.preferred.toDomain()
            statsSubject.send(fresh)
            militaryHistorySubject.send(response.militaryHistory.map { $0.toDomain() })
            cache.save(fresh)
            return fresh
        } catch {
            ErrorLog.shared.log(level: "W", tag: "Stats",
                                message: "refresh24hStats failed; serving cache", error: error)
            let cached = cache.load()
            statsSubject.send(cached.isExpired ? .empty : cached)
            throw error
        }
    }
}
