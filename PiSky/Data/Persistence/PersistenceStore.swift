import Foundation
import SwiftData

/// Async wrapper over a SwiftData `ModelContext`, mirroring the Room DAOs (`FavoriteDao`,
/// `AircraftTagDao`, `DailyAircraftDao`, `FlightTrailDao`). Confined to `@MainActor` so the single
/// `ModelContext` is touched from one thread (SwiftData's `ModelContext` is not `Sendable`); calls
/// are `async` to match the `suspend` DAO surface and to keep callers off any sync DB assumptions.
@MainActor
final class PersistenceStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        self.context.autosaveEnabled = false
    }

    private func save() {
        do { try context.save() } catch {
            ErrorLog.shared.log(level: "E", tag: "PersistenceStore", message: "save failed: \(error)")
        }
    }

    // MARK: - Favorites (FavoriteDao)

    /// All favorite hexes, newest-added first (ORDER BY addedAt DESC).
    func allFavorites() async -> [FavoriteRecord] {
        let d = FetchDescriptor<FavoriteRecord>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    func allFavoriteHexes() async -> [String] {
        await allFavorites().map(\.hex)
    }

    /// INSERT OR IGNORE — no-op if the hex already exists.
    func addFavorite(hex: String) async {
        if await favoriteExists(hex: hex) { return }
        context.insert(FavoriteRecord(hex: hex))
        save()
    }

    func removeFavorite(hex: String) async {
        let d = FetchDescriptor<FavoriteRecord>(predicate: #Predicate { $0.hex == hex })
        if let row = try? context.fetch(d).first {
            context.delete(row)
            save()
        }
    }

    func favoriteExists(hex: String) async -> Bool {
        var d = FetchDescriptor<FavoriteRecord>(predicate: #Predicate { $0.hex == hex })
        d.fetchLimit = 1
        return ((try? context.fetchCount(d)) ?? 0) > 0
    }

    // MARK: - Tags (AircraftTagDao)

    /// All tags, newest first (ORDER BY timestamp DESC).
    func allTags() async -> [TagRecord] {
        let d = FetchDescriptor<TagRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    func tagCount() async -> Int {
        (try? context.fetchCount(FetchDescriptor<TagRecord>())) ?? 0
    }

    func tag(hex: String) async -> TagRecord? {
        var d = FetchDescriptor<TagRecord>(predicate: #Predicate { $0.hex == hex })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// INSERT OR REPLACE — overwrite the existing row for this hex if present.
    func upsertTag(hex: String, category: String, note: String) async {
        if let existing = await tag(hex: hex) {
            existing.category = category
            existing.note = note
            existing.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        } else {
            context.insert(TagRecord(hex: hex, category: category, note: note))
        }
        save()
    }

    func untag(hex: String) async {
        if let row = await tag(hex: hex) {
            context.delete(row)
            save()
        }
    }

    // MARK: - Daily aircraft (DailyAircraftDao)

    /// Upsert mirroring `DailyAircraftDao.upsertAll`: INSERT-OR-IGNORE then COALESCE-merge metadata
    /// (keep first-seen, only fill nulls, OR military flag). Followed by a 30-day prune.
    func upsertDailyAircraft(_ entries: [DailyAircraftRecord], pruneBeforeDate cutoff: String) async {
        guard !entries.isEmpty else { return }
        for e in entries {
            let id = e.id
            var d = FetchDescriptor<DailyAircraftRecord>(predicate: #Predicate { $0.id == id })
            d.fetchLimit = 1
            if let existing = try? context.fetch(d).first {
                // COALESCE(:new, existing) — only overwrite when the new value is non-nil.
                if let t = e.type { existing.type = t }
                if let c = e.callsign { existing.callsign = c }
                if let r = e.registration { existing.registration = r }
                existing.isMilitary = existing.isMilitary || e.isMilitary
            } else {
                context.insert(e)
            }
        }
        // deleteOlderThan(cutoff): DELETE WHERE date < :cutoff
        let prune = FetchDescriptor<DailyAircraftRecord>(predicate: #Predicate { $0.date < cutoff })
        if let stale = try? context.fetch(prune) {
            for row in stale { context.delete(row) }
        }
        save()
    }

    func dailyForDate(_ date: String) async -> [DailyAircraftRecord] {
        let d = FetchDescriptor<DailyAircraftRecord>(
            predicate: #Predicate { $0.date == date },
            sortBy: [SortDescriptor(\.firstSeenMs, order: .reverse)]
        )
        return (try? context.fetch(d)) ?? []
    }

    func dailyCountForDate(_ date: String) async -> Int {
        let d = FetchDescriptor<DailyAircraftRecord>(predicate: #Predicate { $0.date == date })
        return (try? context.fetchCount(d)) ?? 0
    }

    /// All military rows across the retention window, newest first.
    func allMilitaryDaily() async -> [DailyAircraftRecord] {
        let d = FetchDescriptor<DailyAircraftRecord>(
            predicate: #Predicate { $0.isMilitary == true },
            sortBy: [SortDescriptor(\.firstSeenMs, order: .reverse)]
        )
        return (try? context.fetch(d)) ?? []
    }

    // MARK: - Flight trail (FlightTrailDao)

    /// INSERT OR REPLACE rows.
    func insertTrail(_ rows: [FlightTrailRecord]) async {
        guard !rows.isEmpty else { return }
        for r in rows {
            let id = r.id
            var d = FetchDescriptor<FlightTrailRecord>(predicate: #Predicate { $0.id == id })
            d.fetchLimit = 1
            if let existing = try? context.fetch(d).first {
                existing.lat = r.lat
                existing.lon = r.lon
                existing.altBaro = r.altBaro
                existing.track = r.track
                existing.groundSpeed = r.groundSpeed
            } else {
                context.insert(r)
            }
        }
        save()
    }

    /// All trail points for an aircraft, oldest first.
    func trailFor(hex: String) async -> [FlightTrailRecord] {
        let d = FetchDescriptor<FlightTrailRecord>(
            predicate: #Predicate { $0.hex == hex },
            sortBy: [SortDescriptor(\.tsMs, order: .forward)]
        )
        return (try? context.fetch(d)) ?? []
    }

    func trailKnownHexes() async -> [String] {
        let d = FetchDescriptor<FlightTrailRecord>()
        let rows = (try? context.fetch(d)) ?? []
        return Array(Set(rows.map(\.hex)))
    }

    func pruneTrail(beforeMs cutoffMs: Int64) async {
        let d = FetchDescriptor<FlightTrailRecord>(predicate: #Predicate { $0.tsMs < cutoffMs })
        if let stale = try? context.fetch(d) {
            for row in stale { context.delete(row) }
            save()
        }
    }

    func deleteAllTrail() async {
        let d = FetchDescriptor<FlightTrailRecord>()
        if let rows = try? context.fetch(d) {
            for row in rows { context.delete(row) }
            save()
        }
    }

    func trailRowCount() async -> Int {
        (try? context.fetchCount(FetchDescriptor<FlightTrailRecord>())) ?? 0
    }
}
