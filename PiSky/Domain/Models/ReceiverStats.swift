import Foundation

/// Receiver metadata — `ReceiverStats` in ReceiverStats.kt.
struct ReceiverStats: Equatable, Sendable {
    let version: String
    let refreshIntervalMs: Int
    let latitude: Double?
    let longitude: Double?
    let antenna: String?
}

/// Currently-visible live decode stats — `LiveStats` in ReceiverStats.kt.
struct LiveStats: Equatable, Sendable {
    var aircraftTotal: Int
    var aircraftWithPos: Int
    var aircraftWithMlat: Int
    var messagesTotal: Int64
    var messagesLastMinute: Int
    var strongSignals: Int
    var signalDbfs: Double?
    var noiseDbfs: Double?
    var maxRangeNm: Double?
    var trackedPositions: Int64
}

/// Connection health snapshot — `ConnectionState` in ReceiverStats.kt.
struct ConnectionState: Equatable, Sendable {
    var isConnected: Bool
    var lastSuccessMs: Int64
    var errorMessage: String?
}
