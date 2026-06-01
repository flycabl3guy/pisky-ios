import Foundation

/// Result of the military classification engine — `AircraftClassification.kt`.
struct AircraftClassification: Equatable, Sendable {
    let level: ClassificationLevel
    let confidence: Float
    let source: ClassificationSource
    var militaryName: String? = nil
    var militaryUnit: String? = nil

    static let unknown  = AircraftClassification(level: .unknown,  confidence: 0, source: .none)
    static let civilian = AircraftClassification(level: .civilian, confidence: 0, source: .none)
}

enum ClassificationLevel: Sendable {
    case military, likelyMilitary, unknown, civilian
    var isMilOrLikely: Bool { self == .military || self == .likelyMilitary }
}

enum ClassificationSource: Sendable {
    case readsbDbFlags, hexExactMatch, hexRangeMatch, callsignPrefix,
         icaoTypeCode, emitterCategory, multiSignal, none
}
