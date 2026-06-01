import Foundation
import Combine

/// `TagRepository` over `PersistenceStore` — port of `TagRepositoryImpl`. The Room `Flow`s become
/// `CurrentValueSubject`-backed publishers refreshed after every mutation (and on init), since
/// SwiftData has no built-in observable query equivalent we depend on here.
@MainActor
final class TagRepositoryImpl: TagRepository {
    private let store: PersistenceStore

    private let allSubject = CurrentValueSubject<[AircraftTag], Never>([])
    private let taggedHexesSubject = CurrentValueSubject<[String: TagCategory], Never>([:])
    private let countSubject = CurrentValueSubject<Int, Never>(0)

    init(store: PersistenceStore) {
        self.store = store
        Task { [weak self] in await self?.refresh() }
    }

    func observeAll() -> AnyPublisher<[AircraftTag], Never> { allSubject.eraseToAnyPublisher() }
    func observeTaggedHexes() -> AnyPublisher<[String: TagCategory], Never> { taggedHexesSubject.eraseToAnyPublisher() }
    func observeCount() -> AnyPublisher<Int, Never> { countSubject.eraseToAnyPublisher() }

    func tag(hex: String, category: TagCategory, note: String) async {
        await store.upsertTag(hex: hex, category: category.rawValue, note: note)
        await refresh()
    }

    func untag(hex: String) async {
        await store.untag(hex: hex)
        await refresh()
    }

    func getTag(hex: String) async -> AircraftTag? {
        (await store.tag(hex: hex)).flatMap(Self.toDomain)
    }

    // MARK: - Private

    private func refresh() async {
        let rows = await store.allTags()
        let tags = rows.compactMap(Self.toDomain)
        allSubject.send(tags)
        countSubject.send(tags.count)
        var map: [String: TagCategory] = [:]
        for t in tags { map[t.hex] = t.category }
        taggedHexesSubject.send(map)
    }

    private static func toDomain(_ r: TagRecord) -> AircraftTag? {
        guard let category = TagCategory(rawValue: r.category) else { return nil }
        return AircraftTag(hex: r.hex, category: category, note: r.note, timestamp: r.timestamp)
    }
}
