import Foundation

/// Backend mode — single value post-Ultrafeeder cutover. Kept for serialization-shape stability.
enum ServerType: String, Codable, Sendable { case piaware }

/// Receiver connection settings — `ConnectionConfig.kt`.
struct ConnectionConfig: Equatable, Sendable {
    var hostname: String
    var port: Int
    var username: String
    var password: String
    var useBasicAuth: Bool
    var serverType: ServerType = .piaware

    var baseUrl: String { "http://\(hostname):\(port)" }

    /// L2 nginx front door — reverse-proxies /skyaware, /pi-vitals.json, /pi-rolling-24h.json and
    /// the tar1090 mirror through to the Ultrafeeder containers. :8088 because AdGuard owns :80.
    static let `default` = ConnectionConfig(
        hostname: "192.168.1.207",
        port: 8088,
        username: "",
        password: "",
        useBasicAuth: false
    )
}
