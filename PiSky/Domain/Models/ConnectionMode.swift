import Foundation

/// Live connection state — `ConnectionMode.kt`.
enum ConnectionMode: Sendable {
    case disconnected, connecting, pollingHttp, websocket, error

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting:   return "Connecting…"
        case .pollingHttp:  return "Connected"
        case .websocket:    return "Live"
        case .error:        return "Error"
        }
    }

    var isLive: Bool { self == .websocket || self == .pollingHttp }
}
