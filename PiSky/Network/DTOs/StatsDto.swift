import Foundation

/// Full wire shape of readsb's `stats.json` (wiedehopf readsb 3.16.x) — `StatsDto.kt`.
/// Top-level carries the receiver-wide snapshot; the windowed blocks each hold a full
/// `StatsPeriodDto`. All lenient/defaulted so a partial reader failure doesn't crash decoding.
struct StatsDto: Decodable, Sendable {
    let now: Double
    let gainDb: Double?
    let estimatedPpm: Double?
    let aircraftWithPos: Int
    let aircraftWithoutPos: Int
    let aircraftCountByType: [String: Int]
    let last1min: StatsPeriodDto?
    let last5min: StatsPeriodDto?
    let last15min: StatsPeriodDto?
    let total: StatsPeriodDto?
    let latest: StatsPeriodDto?

    enum CodingKeys: String, CodingKey {
        case now
        case gainDb = "gain_db"
        case estimatedPpm = "estimated_ppm"
        case aircraftWithPos = "aircraft_with_pos"
        case aircraftWithoutPos = "aircraft_without_pos"
        case aircraftCountByType = "aircraft_count_by_type"
        case last1min
        case last5min
        case last15min
        case total
        case latest
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        now = try c.decodeIfPresent(Double.self, forKey: .now) ?? 0.0
        gainDb = try c.decodeIfPresent(Double.self, forKey: .gainDb)
        estimatedPpm = try c.decodeIfPresent(Double.self, forKey: .estimatedPpm)
        aircraftWithPos = try c.decodeIfPresent(Int.self, forKey: .aircraftWithPos) ?? 0
        aircraftWithoutPos = try c.decodeIfPresent(Int.self, forKey: .aircraftWithoutPos) ?? 0
        aircraftCountByType = try c.decodeIfPresent([String: Int].self, forKey: .aircraftCountByType) ?? [:]
        last1min = try c.decodeIfPresent(StatsPeriodDto.self, forKey: .last1min)
        last5min = try c.decodeIfPresent(StatsPeriodDto.self, forKey: .last5min)
        last15min = try c.decodeIfPresent(StatsPeriodDto.self, forKey: .last15min)
        total = try c.decodeIfPresent(StatsPeriodDto.self, forKey: .total)
        latest = try c.decodeIfPresent(StatsPeriodDto.self, forKey: .latest)
    }
}

struct StatsPeriodDto: Decodable, Sendable {
    let start: Double
    let end: Double
    let messages: Int
    let messagesValid: Int
    let positionCountTotal: Int
    let positionCountByType: [String: Int]
    /// Furthest decoded position this window, in metres.
    let maxDistanceM: Double
    let altitudeSuppressed: Int
    let tracks: TracksDto?
    let local: LocalStatsDto?
    let remote: RemoteStatsDto?
    let cpr: CprDto?
    let cpu: CpuDto?

    enum CodingKeys: String, CodingKey {
        case start
        case end
        case messages
        case messagesValid = "messages_valid"
        case positionCountTotal = "position_count_total"
        case positionCountByType = "position_count_by_type"
        case maxDistanceM = "max_distance"
        case altitudeSuppressed = "altitude_suppressed"
        case tracks
        case local
        case remote
        case cpr
        case cpu
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decodeIfPresent(Double.self, forKey: .start) ?? 0.0
        end = try c.decodeIfPresent(Double.self, forKey: .end) ?? 0.0
        messages = try c.decodeIfPresent(Int.self, forKey: .messages) ?? 0
        messagesValid = try c.decodeIfPresent(Int.self, forKey: .messagesValid) ?? 0
        positionCountTotal = try c.decodeIfPresent(Int.self, forKey: .positionCountTotal) ?? 0
        positionCountByType = try c.decodeIfPresent([String: Int].self, forKey: .positionCountByType) ?? [:]
        maxDistanceM = try c.decodeIfPresent(Double.self, forKey: .maxDistanceM) ?? 0.0
        altitudeSuppressed = try c.decodeIfPresent(Int.self, forKey: .altitudeSuppressed) ?? 0
        tracks = try c.decodeIfPresent(TracksDto.self, forKey: .tracks)
        local = try c.decodeIfPresent(LocalStatsDto.self, forKey: .local)
        remote = try c.decodeIfPresent(RemoteStatsDto.self, forKey: .remote)
        cpr = try c.decodeIfPresent(CprDto.self, forKey: .cpr)
        cpu = try c.decodeIfPresent(CpuDto.self, forKey: .cpu)
    }

    /// Window length in seconds; 0 if start/end missing.
    var durationSec: Double { max(end - start, 0.0) }
    /// Furthest position this window in nautical miles.
    var maxDistanceNm: Double { maxDistanceM / 1852.0 }
}

struct CprDto: Decodable, Sendable {
    let airborne: Int64
    let surface: Int64
    let globalOk: Int64
    let globalBad: Int64
    let globalBadRange: Int64
    let globalBadSpeed: Int64
    let globalSkipped: Int64
    let localOk: Int64
    let localAircraftRelative: Int64
    let localReceiverRelative: Int64
    let localSkipped: Int64
    let localBadRange: Int64
    let localBadSpeed: Int64
    let filtered: Int64

    enum CodingKeys: String, CodingKey {
        case airborne
        case surface
        case globalOk = "global_ok"
        case globalBad = "global_bad"
        case globalBadRange = "global_range"
        case globalBadSpeed = "global_speed"
        case globalSkipped = "global_skipped"
        case localOk = "local_ok"
        case localAircraftRelative = "local_aircraft_relative"
        case localReceiverRelative = "local_receiver_relative"
        case localSkipped = "local_skipped"
        case localBadRange = "local_range"
        case localBadSpeed = "local_speed"
        case filtered
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        airborne = try c.decodeIfPresent(Int64.self, forKey: .airborne) ?? 0
        surface = try c.decodeIfPresent(Int64.self, forKey: .surface) ?? 0
        globalOk = try c.decodeIfPresent(Int64.self, forKey: .globalOk) ?? 0
        globalBad = try c.decodeIfPresent(Int64.self, forKey: .globalBad) ?? 0
        globalBadRange = try c.decodeIfPresent(Int64.self, forKey: .globalBadRange) ?? 0
        globalBadSpeed = try c.decodeIfPresent(Int64.self, forKey: .globalBadSpeed) ?? 0
        globalSkipped = try c.decodeIfPresent(Int64.self, forKey: .globalSkipped) ?? 0
        localOk = try c.decodeIfPresent(Int64.self, forKey: .localOk) ?? 0
        localAircraftRelative = try c.decodeIfPresent(Int64.self, forKey: .localAircraftRelative) ?? 0
        localReceiverRelative = try c.decodeIfPresent(Int64.self, forKey: .localReceiverRelative) ?? 0
        localSkipped = try c.decodeIfPresent(Int64.self, forKey: .localSkipped) ?? 0
        localBadRange = try c.decodeIfPresent(Int64.self, forKey: .localBadRange) ?? 0
        localBadSpeed = try c.decodeIfPresent(Int64.self, forKey: .localBadSpeed) ?? 0
        filtered = try c.decodeIfPresent(Int64.self, forKey: .filtered) ?? 0
    }

    /// Global CPR decode success rate (0..1). Bad decodes signal noise/spoofing.
    var globalOkRatio: Double {
        let tot = globalOk + globalBad
        return tot > 0 ? Double(globalOk) / Double(tot) : 1.0
    }
}

struct TracksDto: Decodable, Sendable {
    let all: Int
    let singleMessage: Int

    enum CodingKeys: String, CodingKey {
        case all
        case singleMessage = "single_message"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        all = try c.decodeIfPresent(Int.self, forKey: .all) ?? 0
        singleMessage = try c.decodeIfPresent(Int.self, forKey: .singleMessage) ?? 0
    }
}

struct CpuDto: Decodable, Sendable {
    let demod: Int64
    let reader: Int64
    let background: Int64
    let aircraftJson: Int64
    let globeJson: Int64
    let heatmapAndState: Int64
    let removeStale: Int64

    enum CodingKeys: String, CodingKey {
        case demod
        case reader
        case background
        case aircraftJson = "aircraft_json"
        case globeJson = "globe_json"
        case heatmapAndState = "heatmap_and_state"
        case removeStale = "remove_stale"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        demod = try c.decodeIfPresent(Int64.self, forKey: .demod) ?? 0
        reader = try c.decodeIfPresent(Int64.self, forKey: .reader) ?? 0
        background = try c.decodeIfPresent(Int64.self, forKey: .background) ?? 0
        aircraftJson = try c.decodeIfPresent(Int64.self, forKey: .aircraftJson) ?? 0
        globeJson = try c.decodeIfPresent(Int64.self, forKey: .globeJson) ?? 0
        heatmapAndState = try c.decodeIfPresent(Int64.self, forKey: .heatmapAndState) ?? 0
        removeStale = try c.decodeIfPresent(Int64.self, forKey: .removeStale) ?? 0
    }
}

struct LocalStatsDto: Decodable, Sendable {
    /// `[0]` = messages accepted with 0 bit errors, `[1]` = accepted after 1-bit correction.
    let accepted: [Int64]
    let strongSignals: Int
    let signal: Double?
    let noise: Double?
    let peakSignal: Double?
    let positions: Int64
    let modes: Int64
    let bad: Int64
    let unknownIcao: Int64
    let samplesProcessed: Int64
    let samplesDropped: Int64
    let samplesLost: Int64
    let prePhase: [Int64]
    let bestPhase: [Int64]
    let gainDb: Double?

    enum CodingKeys: String, CodingKey {
        case accepted
        case strongSignals = "strong_signals"
        case signal
        case noise
        case peakSignal = "peak_signal"
        case positions
        case modes
        case bad
        case unknownIcao = "unknown_icao"
        case samplesProcessed = "samples_processed"
        case samplesDropped = "samples_dropped"
        case samplesLost = "samples_lost"
        case prePhase = "pre_phase_1"
        case bestPhase = "best_phase"
        case gainDb = "gain_db"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accepted = try c.decodeIfPresent([Int64].self, forKey: .accepted) ?? []
        strongSignals = try c.decodeIfPresent(Int.self, forKey: .strongSignals) ?? 0
        signal = try c.decodeIfPresent(Double.self, forKey: .signal)
        noise = try c.decodeIfPresent(Double.self, forKey: .noise)
        peakSignal = try c.decodeIfPresent(Double.self, forKey: .peakSignal)
        positions = try c.decodeIfPresent(Int64.self, forKey: .positions) ?? 0
        modes = try c.decodeIfPresent(Int64.self, forKey: .modes) ?? 0
        bad = try c.decodeIfPresent(Int64.self, forKey: .bad) ?? 0
        unknownIcao = try c.decodeIfPresent(Int64.self, forKey: .unknownIcao) ?? 0
        samplesProcessed = try c.decodeIfPresent(Int64.self, forKey: .samplesProcessed) ?? 0
        samplesDropped = try c.decodeIfPresent(Int64.self, forKey: .samplesDropped) ?? 0
        samplesLost = try c.decodeIfPresent(Int64.self, forKey: .samplesLost) ?? 0
        prePhase = try c.decodeIfPresent([Int64].self, forKey: .prePhase) ?? []
        bestPhase = try c.decodeIfPresent([Int64].self, forKey: .bestPhase) ?? []
        gainDb = try c.decodeIfPresent(Double.self, forKey: .gainDb)
    }

    var acceptedClean: Int64 { accepted.indices.contains(0) ? accepted[0] : 0 }
    var acceptedCorrected: Int64 { accepted.indices.contains(1) ? accepted[1] : 0 }
    var acceptedTotal: Int64 { acceptedClean + acceptedCorrected }
}

struct RemoteStatsDto: Decodable, Sendable {
    let modeac: Int64
    let modes: Int64
    let bad: Int64
    let unknownIcao: Int64
    let accepted: [Int64]
    let bytesIn: Int64
    let bytesOut: Int64

    enum CodingKeys: String, CodingKey {
        case modeac
        case modes
        case bad
        case unknownIcao = "unknown_icao"
        case accepted
        case bytesIn = "bytes_in"
        case bytesOut = "bytes_out"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modeac = try c.decodeIfPresent(Int64.self, forKey: .modeac) ?? 0
        modes = try c.decodeIfPresent(Int64.self, forKey: .modes) ?? 0
        bad = try c.decodeIfPresent(Int64.self, forKey: .bad) ?? 0
        unknownIcao = try c.decodeIfPresent(Int64.self, forKey: .unknownIcao) ?? 0
        accepted = try c.decodeIfPresent([Int64].self, forKey: .accepted) ?? []
        bytesIn = try c.decodeIfPresent(Int64.self, forKey: .bytesIn) ?? 0
        bytesOut = try c.decodeIfPresent(Int64.self, forKey: .bytesOut) ?? 0
    }
}
