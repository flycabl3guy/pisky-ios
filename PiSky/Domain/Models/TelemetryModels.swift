import Foundation

/// One time-sample of receiver telemetry (ring-buffered live) — `TelemetryModels.kt`. Any field may
/// be nil when its source endpoint was unavailable that tick. Powers the Trends dashboard.
struct TrendSample: Equatable, Sendable {
    let tsMs: Int64
    var aircraftTotal: Int?
    var aircraftWithPos: Int?
    var messagesPerSec: Double?
    var signalDbfs: Double?
    var noiseDbfs: Double?
    var snrDb: Double?
    var cpuTempC: Double?
    var gainDb: Double?
    var maxRangeNm: Double?
    var cpuLoad1m: Double?
}

/// Outbound aggregator/feed connection (from stats.prom `net_connector_status`).
struct FeedConnector: Identifiable, Equatable, Sendable {
    let host: String
    let port: String
    let secondsConnected: Double

    var id: String { "\(host):\(port)" }
    var isUp: Bool { secondsConnected > 0 }
    var displayName: String {
        switch true {
        case host.contains("adsb.fi"):        return "adsb.fi"
        case host.contains("adsb.lol"):       return "adsb.lol"
        case host.contains("airplanes.live"): return "airplanes.live"
        case host.contains("adsb.one"):       return "adsb.one"
        case host.contains("adsbexchange"):   return "ADSB Exchange"
        case host.contains("flightaware"):    return "FlightAware"
        case host.contains("flightradar"):    return "FlightRadar24"
        case host.contains("dump978"):        return "UAT 978"
        default:                              return host
        }
    }
}

/// One vertex of the receiver's coverage polygon.
struct CoveragePoint: Equatable, Sendable {
    let lat: Double
    let lon: Double
    let altFt: Int
    let bearingDeg: Double
    let rangeNm: Double
}

/// The receiver's 24 h coverage outline, projected to bearing/range.
struct CoverageOutline: Equatable, Sendable {
    let points: [CoveragePoint]

    var maxRangeNm: Double { points.map(\.rangeNm).max() ?? 0 }
    var maxRangePoint: CoveragePoint? { points.max(by: { $0.rangeNm < $1.rangeNm }) }
    var isEmpty: Bool { points.isEmpty }

    /// Build from raw `[[lat, lon, altFt], …]` points relative to the receiver.
    static func from(rawPoints: [[Double]], recvLat: Double, recvLon: Double) -> CoverageOutline {
        let pts: [CoveragePoint] = rawPoints.compactMap { p in
            guard p.count >= 2 else { return nil }
            let lat = p[0], lon = p[1]
            let alt = p.count > 2 ? Int(p[2]) : 0
            return CoveragePoint(
                lat: lat, lon: lon, altFt: alt,
                bearingDeg: Geo.bearingDeg(recvLat, recvLon, lat, lon),
                rangeNm: Geo.haversineNm(recvLat, recvLon, lat, lon)
            )
        }
        return CoverageOutline(points: pts)
    }
}

/// Pure great-circle helpers — `Geo` in TelemetryModels.kt.
enum Geo {
    static func haversineNm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 3440.065
        let dLat = (lat2 - lat1).radians
        let dLon = (lon2 - lon1).radians
        let a = sin(dLat / 2) * sin(dLat / 2)
              + cos(lat1.radians) * cos(lat2.radians) * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    static func bearingDeg(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let dLon = (lon2 - lon1).radians
        let y = sin(dLon) * cos(lat2.radians)
        let x = cos(lat1.radians) * sin(lat2.radians)
              - sin(lat1.radians) * cos(lat2.radians) * cos(dLon)
        return (atan2(y, x).degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}
