import Foundation

/// User tag category — `TagCategory.kt`.
enum TagCategory: String, CaseIterable, Sendable {
    case military, `private`, interesting, watch

    var label: String {
        switch self {
        case .military:    return "Military"
        case .private:     return "Private/Charter"
        case .interesting: return "Interesting"
        case .watch:       return "Watch List"
        }
    }
}

/// A user tag on an aircraft — `AircraftTag.kt`.
struct AircraftTag: Equatable, Identifiable, Sendable {
    let hex: String
    let category: TagCategory
    var note: String = ""
    var timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    var id: String { hex }
}
