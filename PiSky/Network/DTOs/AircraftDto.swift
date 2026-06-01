import Foundation

/// Wire shape of the readsb `aircraft.json` envelope — `AircraftResponseDto` in AircraftDto.kt.
/// kotlinx ran with `ignoreUnknownKeys`/`isLenient`/`coerceInputValues`, so a custom `init(from:)`
/// here uses `decodeIfPresent ?? default` to keep missing keys from throwing.
struct AircraftResponseDto: Decodable, Sendable {
    let now: Double
    let messages: Int64
    let feed: String?
    let total: Int64?
    let aircraft: [AircraftDto]

    enum CodingKeys: String, CodingKey {
        case now
        case messages
        case feed
        case total
        case aircraft
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        now = try c.decodeIfPresent(Double.self, forKey: .now) ?? 0.0
        messages = try c.decodeIfPresent(Int64.self, forKey: .messages) ?? 0
        feed = try c.decodeIfPresent(String.self, forKey: .feed)
        total = try c.decodeIfPresent(Int64.self, forKey: .total)
        aircraft = try c.decodeIfPresent([AircraftDto].self, forKey: .aircraft) ?? []
    }
}

/// The 76-field readsb aircraft record — `AircraftDto` in AircraftDto.kt.
/// Every JSON key preserved exactly via `CodingKeys`. `Double`-typed counters stay `Double`;
/// cumulative-message counters that were Kotlin `Long` are `Int64`; plain ints are `Int`.
struct AircraftDto: Decodable, Sendable {
    let hex: String
    let adsbType: String?
    let flight: String?
    let registration: String?
    let aircraftType: String?
    let category: String?
    let squawk: String?
    let emergency: String?
    let lat: Double?
    let lon: Double?
    let altBaro: AltitudeValue?
    let altGeom: Int?
    let groundSpeed: Double?
    let ias: Int?
    let tas: Int?
    let mach: Double?
    let track: Double?
    let calcTrack: Double?
    let trackRate: Double?
    let roll: Double?
    let baroRate: Int?
    let geomRate: Int?
    let magHeading: Double?
    let trueHeading: Double?
    let navAltMcp: Int?
    let navAltFms: Int?
    let navHeading: Double?
    let navQnh: Double?
    let nic: Int?
    let rc: Int?
    let nacP: Int?
    let nacV: Int?
    let sil: Int?
    let version: Int?
    let rssi: Double?
    let seen: Double
    let seenPos: Double?
    let messages: Int
    let mlat: [String]?
    let tisb: [String]?
    let dbFlags: Int?
    let desc: String?
    let ownOp: String?
    let year: String?
    let navModes: [String]?
    let rDst: Double?
    let rDir: Double?
    let alert: Int?
    let spi: Int?
    let source: String?
    let nicBaro: Int?
    let silType: String?
    let gva: Int?
    let sda: Int?
    let routeset: RouteSetDto?

    enum CodingKeys: String, CodingKey {
        case hex
        case adsbType = "type"
        case flight
        case registration = "r"
        case aircraftType = "t"
        case category
        case squawk
        case emergency
        case lat
        case lon
        case altBaro = "alt_baro"
        case altGeom = "alt_geom"
        case groundSpeed = "gs"
        case ias
        case tas
        case mach
        case track
        case calcTrack = "calc_track"
        case trackRate = "track_rate"
        case roll
        case baroRate = "baro_rate"
        case geomRate = "geom_rate"
        case magHeading = "mag_heading"
        case trueHeading = "true_heading"
        case navAltMcp = "nav_altitude_mcp"
        case navAltFms = "nav_altitude_fms"
        case navHeading = "nav_heading"
        case navQnh = "nav_qnh"
        case nic
        case rc
        case nacP = "nac_p"
        case nacV = "nac_v"
        case sil
        case version
        case rssi
        case seen
        case seenPos = "seen_pos"
        case messages
        case mlat
        case tisb
        case dbFlags
        case desc
        case ownOp
        case year
        case navModes = "nav_modes"
        case rDst = "r_dst"
        case rDir = "r_dir"
        case alert
        case spi
        case source
        case nicBaro = "nic_baro"
        case silType = "sil_type"
        case gva
        case sda
        case routeset
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // hex is the only non-optional, non-defaulted field in the Kotlin DTO.
        hex = try c.decode(String.self, forKey: .hex)
        adsbType = try c.decodeIfPresent(String.self, forKey: .adsbType)
        flight = try c.decodeIfPresent(String.self, forKey: .flight)
        registration = try c.decodeIfPresent(String.self, forKey: .registration)
        aircraftType = try c.decodeIfPresent(String.self, forKey: .aircraftType)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        squawk = try c.decodeIfPresent(String.self, forKey: .squawk)
        emergency = try c.decodeIfPresent(String.self, forKey: .emergency)
        lat = try c.decodeIfPresent(Double.self, forKey: .lat)
        lon = try c.decodeIfPresent(Double.self, forKey: .lon)
        altBaro = try c.decodeIfPresent(AltitudeValue.self, forKey: .altBaro)
        altGeom = try c.decodeIfPresent(Int.self, forKey: .altGeom)
        groundSpeed = try c.decodeIfPresent(Double.self, forKey: .groundSpeed)
        ias = try c.decodeIfPresent(Int.self, forKey: .ias)
        tas = try c.decodeIfPresent(Int.self, forKey: .tas)
        mach = try c.decodeIfPresent(Double.self, forKey: .mach)
        track = try c.decodeIfPresent(Double.self, forKey: .track)
        calcTrack = try c.decodeIfPresent(Double.self, forKey: .calcTrack)
        trackRate = try c.decodeIfPresent(Double.self, forKey: .trackRate)
        roll = try c.decodeIfPresent(Double.self, forKey: .roll)
        baroRate = try c.decodeIfPresent(Int.self, forKey: .baroRate)
        geomRate = try c.decodeIfPresent(Int.self, forKey: .geomRate)
        magHeading = try c.decodeIfPresent(Double.self, forKey: .magHeading)
        trueHeading = try c.decodeIfPresent(Double.self, forKey: .trueHeading)
        navAltMcp = try c.decodeIfPresent(Int.self, forKey: .navAltMcp)
        navAltFms = try c.decodeIfPresent(Int.self, forKey: .navAltFms)
        navHeading = try c.decodeIfPresent(Double.self, forKey: .navHeading)
        navQnh = try c.decodeIfPresent(Double.self, forKey: .navQnh)
        nic = try c.decodeIfPresent(Int.self, forKey: .nic)
        rc = try c.decodeIfPresent(Int.self, forKey: .rc)
        nacP = try c.decodeIfPresent(Int.self, forKey: .nacP)
        nacV = try c.decodeIfPresent(Int.self, forKey: .nacV)
        sil = try c.decodeIfPresent(Int.self, forKey: .sil)
        version = try c.decodeIfPresent(Int.self, forKey: .version)
        rssi = try c.decodeIfPresent(Double.self, forKey: .rssi)
        seen = try c.decodeIfPresent(Double.self, forKey: .seen) ?? 0.0
        seenPos = try c.decodeIfPresent(Double.self, forKey: .seenPos)
        messages = try c.decodeIfPresent(Int.self, forKey: .messages) ?? 0
        mlat = try c.decodeIfPresent([String].self, forKey: .mlat)
        tisb = try c.decodeIfPresent([String].self, forKey: .tisb)
        dbFlags = try c.decodeIfPresent(Int.self, forKey: .dbFlags)
        desc = try c.decodeIfPresent(String.self, forKey: .desc)
        ownOp = try c.decodeIfPresent(String.self, forKey: .ownOp)
        year = try c.decodeIfPresent(String.self, forKey: .year)
        navModes = try c.decodeIfPresent([String].self, forKey: .navModes)
        rDst = try c.decodeIfPresent(Double.self, forKey: .rDst)
        rDir = try c.decodeIfPresent(Double.self, forKey: .rDir)
        alert = try c.decodeIfPresent(Int.self, forKey: .alert)
        spi = try c.decodeIfPresent(Int.self, forKey: .spi)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        nicBaro = try c.decodeIfPresent(Int.self, forKey: .nicBaro)
        silType = try c.decodeIfPresent(String.self, forKey: .silType)
        gva = try c.decodeIfPresent(Int.self, forKey: .gva)
        sda = try c.decodeIfPresent(Int.self, forKey: .sda)
        routeset = try c.decodeIfPresent(RouteSetDto.self, forKey: .routeset)
    }
}

/// Route enrichment block from L2's `/enrich/aircraft.json` — `RouteSetDto` in AircraftDto.kt.
/// `from`/`to` are ICAO airport codes (e.g. KORD, MMMX).
struct RouteSetDto: Decodable, Sendable {
    let from: String?
    let to: String?

    enum CodingKeys: String, CodingKey {
        case from
        case to
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decodeIfPresent(String.self, forKey: .from)
        to = try c.decodeIfPresent(String.self, forKey: .to)
    }
}
