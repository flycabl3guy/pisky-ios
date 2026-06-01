import Foundation
import Combine

/// Rolling-24h statistics repository (Pi-authoritative, cached) — the `StatsRepository` class in
/// the Android `core:data`. Modeled as a protocol so view models depend on the contract, not the
/// concrete actor.
protocol StatsRepository: AnyObject {
    func observe24hStats() -> AnyPublisher<Rolling24hStats, Never>
    func observeMilitaryHistory() -> AnyPublisher<[MilitaryHistoryEntry], Never>
    @discardableResult
    func refresh24hStats() async throws -> Rolling24hStats
}
