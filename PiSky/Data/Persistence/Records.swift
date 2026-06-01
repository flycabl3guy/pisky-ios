import Foundation
import SwiftData

/// SwiftData persistence records — ports of the Room entities in `core:data/local/database`.
///
/// Room composite primary keys (`["date","hex"]`, `["hex","ts_ms"]`) have no direct SwiftData
/// analogue, so each composite-key entity gains a derived `@Attribute(.unique) var id` built from
/// the component fields (`"\(date)|\(hex)"`). Single-PK entities key on the natural column.
/// Column names mirror the Kotlin entities so the upsert/query logic in `PersistenceStore` lines up
/// one-to-one with the DAOs.

/// `favorites` table — `FavoriteEntity`.
@Model
final class FavoriteRecord {
    @Attribute(.unique) var hex: String
    var addedAt: Int64

    init(hex: String, addedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.hex = hex
        self.addedAt = addedAt
    }
}

/// `aircraft_tags` table — `AircraftTagEntity`. `category` stored as the raw enum name (matching
/// `TagCategory.rawValue`).
@Model
final class TagRecord {
    @Attribute(.unique) var hex: String
    var category: String
    var note: String
    var timestamp: Int64

    init(hex: String,
         category: String,
         note: String = "",
         timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.hex = hex
        self.category = category
        self.note = note
        self.timestamp = timestamp
    }
}

/// `daily_aircraft` table — `DailyAircraftEntity`. Composite PK `["date","hex"]` → unique `id`.
@Model
final class DailyAircraftRecord {
    @Attribute(.unique) var id: String   // "\(date)|\(hex)"
    var date: String
    var hex: String
    var type: String?
    var callsign: String?
    var registration: String?
    var firstSeenMs: Int64
    var isMilitary: Bool

    init(date: String,
         hex: String,
         type: String? = nil,
         callsign: String? = nil,
         registration: String? = nil,
         firstSeenMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
         isMilitary: Bool = false) {
        self.id = "\(date)|\(hex)"
        self.date = date
        self.hex = hex
        self.type = type
        self.callsign = callsign
        self.registration = registration
        self.firstSeenMs = firstSeenMs
        self.isMilitary = isMilitary
    }

    static func makeId(date: String, hex: String) -> String { "\(date)|\(hex)" }
}

/// `flight_trail` table — `FlightTrailEntity`. Composite PK `["hex","ts_ms"]` → unique `id`.
@Model
final class FlightTrailRecord {
    @Attribute(.unique) var id: String   // "\(hex)|\(tsMs)"
    var hex: String
    var tsMs: Int64
    var lat: Double
    var lon: Double
    var altBaro: Int?
    var track: Double?
    var groundSpeed: Double?

    init(hex: String,
         tsMs: Int64,
         lat: Double,
         lon: Double,
         altBaro: Int? = nil,
         track: Double? = nil,
         groundSpeed: Double? = nil) {
        self.id = "\(hex)|\(tsMs)"
        self.hex = hex
        self.tsMs = tsMs
        self.lat = lat
        self.lon = lon
        self.altBaro = altBaro
        self.track = track
        self.groundSpeed = groundSpeed
    }

    static func makeId(hex: String, tsMs: Int64) -> String { "\(hex)|\(tsMs)" }
}
