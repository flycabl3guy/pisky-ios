import Foundation

/// Parser for readsb's Prometheus exposition format (`stats.prom`) — `PromMetrics.kt`.
///
/// A few things live only in the prom feed:
///   - `readsb_net_connector_status{host="…",port="…"} <secondsConnected>` — per-aggregator
///     outbound feed health (non-zero = seconds up; 0 = down).
///   - RSSI quartiles (`readsb_aircraft_rssi_min/quart1/median/quart3/max/average`).
///   - `readsb_distance_min` (closest decode, metres).
///
/// Whole file parses into a flat `metrics` map; labelled connector lines go to `connectors`.
struct PromMetrics: Sendable {
    let metrics: [String: Double]
    let connectors: [FeedConnectorDto]

    subscript(_ key: String) -> Double? { metrics[key] }

    var rssiMin: Double? { metrics["readsb_aircraft_rssi_min"] }
    var rssiQ1: Double? { metrics["readsb_aircraft_rssi_quart1"] }
    var rssiMedian: Double? { metrics["readsb_aircraft_rssi_median"] }
    var rssiQ3: Double? { metrics["readsb_aircraft_rssi_quart3"] }
    var rssiMax: Double? { metrics["readsb_aircraft_rssi_max"] }
    var rssiAvg: Double? { metrics["readsb_aircraft_rssi_average"] }
    var distanceMaxM: Double? { metrics["readsb_distance_max"] }
    var distanceMinM: Double? { metrics["readsb_distance_min"] }

    // readsb_net_connector_status{host="feed.adsb.fi",port="30004"} 51865
    private static let connectorRegex = try! NSRegularExpression(
        pattern: #"readsb_net_connector_status\{host="([^"]+)",port="([^"]+)"\}\s+([0-9.eE+-]+)"#
    )
    // bare:  metric_name 123.4
    private static let scalarRegex = try! NSRegularExpression(
        pattern: #"^([a-zA-Z_][a-zA-Z0-9_]*)\s+([0-9.eE+-]+)\s*$"#
    )

    static func parse(_ text: String) -> PromMetrics {
        var metrics: [String: Double] = [:]
        metrics.reserveCapacity(256)
        var connectors: [FeedConnectorDto] = []
        connectors.reserveCapacity(8)

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let full = NSRange(line.startIndex..<line.endIndex, in: line)

            if let m = connectorRegex.firstMatch(in: line, range: full),
               let hostR = Range(m.range(at: 1), in: line),
               let portR = Range(m.range(at: 2), in: line),
               let valR = Range(m.range(at: 3), in: line) {
                let v = Double(line[valR]) ?? 0.0
                connectors.append(FeedConnectorDto(
                    host: String(line[hostR]),
                    port: String(line[portR]),
                    secondsConnected: v
                ))
                continue
            }

            if let m = scalarRegex.firstMatch(in: line, range: full),
               let nameR = Range(m.range(at: 1), in: line),
               let valR = Range(m.range(at: 2), in: line),
               let v = Double(line[valR]) {
                metrics[String(line[nameR])] = v
            }
        }
        return PromMetrics(metrics: metrics, connectors: connectors)
    }

    static let empty = PromMetrics(metrics: [:], connectors: [])
}

/// Outbound aggregator/feed connection from `stats.prom` — `FeedConnectorDto` in PromMetrics.kt.
/// Distinct from the domain `FeedConnector` (in TelemetryModels.swift); a mapper bridges the two.
struct FeedConnectorDto: Sendable, Equatable {
    let host: String
    let port: String
    /// Seconds the outbound connection has been up; 0 means currently down.
    let secondsConnected: Double
}
