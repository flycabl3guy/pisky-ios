import Foundation

/// Diagnostics-screen status model — `PiStatusDto.kt`. No longer fetched directly (the
/// pisky-troubleshooter endpoint is retired); synthesized from vitals + stats by
/// `PiStatusSynthesizer`. Kept Decodable for shape stability. Each nested DTO has both a
/// memberwise init (for the synthesizer) and a lenient `init(from:)`.
struct PiStatusDto: Decodable, Sendable {
    let timestamp: String
    let rtlsdr: RtlSdrDto
    let piaware: ServiceDto
    let readsb: ServiceDto?
    let dump1090: ServiceDto
    let dump978: ServiceDto
    let temp: TempDto
    let throttle: ThrottleDto
    let readsbStats: Dump1090StatsDto?
    let dump1090Stats: Dump1090StatsDto
    let resources: ResourcesDto
    let gain1090: String
    let gain978: String
    let aircraftTracked24h: Int

    enum CodingKeys: String, CodingKey {
        case timestamp
        case rtlsdr
        case piaware
        case readsb
        case dump1090
        case dump978
        case temp
        case throttle
        case readsbStats = "readsb_stats"
        case dump1090Stats = "dump1090_stats"
        case resources
        case gain1090 = "gain_1090"
        case gain978 = "gain_978"
        case aircraftTracked24h = "aircraft_tracked_24h"
    }

    init(
        timestamp: String = "",
        rtlsdr: RtlSdrDto = RtlSdrDto(),
        piaware: ServiceDto = ServiceDto(),
        readsb: ServiceDto? = nil,
        dump1090: ServiceDto = ServiceDto(),
        dump978: ServiceDto = ServiceDto(),
        temp: TempDto = TempDto(),
        throttle: ThrottleDto = ThrottleDto(),
        readsbStats: Dump1090StatsDto? = nil,
        dump1090Stats: Dump1090StatsDto = Dump1090StatsDto(),
        resources: ResourcesDto = ResourcesDto(),
        gain1090: String = "",
        gain978: String = "",
        aircraftTracked24h: Int = 0
    ) {
        self.timestamp = timestamp
        self.rtlsdr = rtlsdr
        self.piaware = piaware
        self.readsb = readsb
        self.dump1090 = dump1090
        self.dump978 = dump978
        self.temp = temp
        self.throttle = throttle
        self.readsbStats = readsbStats
        self.dump1090Stats = dump1090Stats
        self.resources = resources
        self.gain1090 = gain1090
        self.gain978 = gain978
        self.aircraftTracked24h = aircraftTracked24h
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try c.decodeIfPresent(String.self, forKey: .timestamp) ?? ""
        rtlsdr = try c.decodeIfPresent(RtlSdrDto.self, forKey: .rtlsdr) ?? RtlSdrDto()
        piaware = try c.decodeIfPresent(ServiceDto.self, forKey: .piaware) ?? ServiceDto()
        readsb = try c.decodeIfPresent(ServiceDto.self, forKey: .readsb)
        dump1090 = try c.decodeIfPresent(ServiceDto.self, forKey: .dump1090) ?? ServiceDto()
        dump978 = try c.decodeIfPresent(ServiceDto.self, forKey: .dump978) ?? ServiceDto()
        temp = try c.decodeIfPresent(TempDto.self, forKey: .temp) ?? TempDto()
        throttle = try c.decodeIfPresent(ThrottleDto.self, forKey: .throttle) ?? ThrottleDto()
        readsbStats = try c.decodeIfPresent(Dump1090StatsDto.self, forKey: .readsbStats)
        dump1090Stats = try c.decodeIfPresent(Dump1090StatsDto.self, forKey: .dump1090Stats) ?? Dump1090StatsDto()
        resources = try c.decodeIfPresent(ResourcesDto.self, forKey: .resources) ?? ResourcesDto()
        gain1090 = try c.decodeIfPresent(String.self, forKey: .gain1090) ?? ""
        gain978 = try c.decodeIfPresent(String.self, forKey: .gain978) ?? ""
        aircraftTracked24h = try c.decodeIfPresent(Int.self, forKey: .aircraftTracked24h) ?? 0
    }

    /// Prefer the canonical readsb service when present; fall back to the dump1090 alias.
    var decoder: ServiceDto { readsb ?? dump1090 }
    /// Prefer canonical readsb_stats; fall back to dump1090_stats alias.
    var decoderStats: Dump1090StatsDto { readsbStats ?? dump1090Stats }
}

struct ServiceDto: Decodable, Sendable {
    let active: Bool
    let enabled: Bool
    let state: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case active, enabled, state, status
    }

    init(active: Bool = false, enabled: Bool = false, state: String = "", status: String = "") {
        self.active = active
        self.enabled = enabled
        self.state = state
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
    }
}

struct RtlSdrDto: Decodable, Sendable {
    let detected: Bool
    let device: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case detected, device, status
    }

    init(detected: Bool = false, device: String = "", status: String = "") {
        self.detected = detected
        self.device = device
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        detected = try c.decodeIfPresent(Bool.self, forKey: .detected) ?? false
        device = try c.decodeIfPresent(String.self, forKey: .device) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
    }
}

struct TempDto: Decodable, Sendable {
    let celsius: Double
    let fahrenheit: Double
    let status: String

    enum CodingKeys: String, CodingKey {
        case celsius, fahrenheit, status
    }

    init(celsius: Double = 0.0, fahrenheit: Double = 0.0, status: String = "") {
        self.celsius = celsius
        self.fahrenheit = fahrenheit
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        celsius = try c.decodeIfPresent(Double.self, forKey: .celsius) ?? 0.0
        fahrenheit = try c.decodeIfPresent(Double.self, forKey: .fahrenheit) ?? 0.0
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
    }
}

struct ThrottleDto: Decodable, Sendable {
    let flags: [String]
    let ok: Bool
    let raw: String

    enum CodingKeys: String, CodingKey {
        case flags, ok, raw
    }

    init(flags: [String] = [], ok: Bool = true, raw: String = "") {
        self.flags = flags
        self.ok = ok
        self.raw = raw
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        flags = try c.decodeIfPresent([String].self, forKey: .flags) ?? []
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        raw = try c.decodeIfPresent(String.self, forKey: .raw) ?? ""
    }
}

struct Dump1090StatsDto: Decodable, Sendable {
    let aircraft: Int
    let messages: Int64
    let noiseDbfs: Double
    let peakSignalDbfs: Double
    let signalDbfs: Double
    let strongSignals: Int
    let status: String

    enum CodingKeys: String, CodingKey {
        case aircraft
        case messages
        case noiseDbfs = "noise_dbfs"
        case peakSignalDbfs = "peak_signal_dbfs"
        case signalDbfs = "signal_dbfs"
        case strongSignals = "strong_signals"
        case status
    }

    init(
        aircraft: Int = 0,
        messages: Int64 = 0,
        noiseDbfs: Double = 0.0,
        peakSignalDbfs: Double = 0.0,
        signalDbfs: Double = 0.0,
        strongSignals: Int = 0,
        status: String = ""
    ) {
        self.aircraft = aircraft
        self.messages = messages
        self.noiseDbfs = noiseDbfs
        self.peakSignalDbfs = peakSignalDbfs
        self.signalDbfs = signalDbfs
        self.strongSignals = strongSignals
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aircraft = try c.decodeIfPresent(Int.self, forKey: .aircraft) ?? 0
        messages = try c.decodeIfPresent(Int64.self, forKey: .messages) ?? 0
        noiseDbfs = try c.decodeIfPresent(Double.self, forKey: .noiseDbfs) ?? 0.0
        peakSignalDbfs = try c.decodeIfPresent(Double.self, forKey: .peakSignalDbfs) ?? 0.0
        signalDbfs = try c.decodeIfPresent(Double.self, forKey: .signalDbfs) ?? 0.0
        strongSignals = try c.decodeIfPresent(Int.self, forKey: .strongSignals) ?? 0
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
    }
}

/// Body for a gain-set POST — `GainSetBody` in PiStatusDto.kt. Encodable (the one DTO that's sent).
struct GainSetBody: Codable, Sendable {
    let gain: String

    enum CodingKeys: String, CodingKey {
        case gain
    }
}

/// Resources block — `ResourcesDto` in PiStatusDto.kt. Two wire shapes (new flat fields / legacy);
/// computed properties prefer the new shape and fall back to the old.
struct ResourcesDto: Decodable, Sendable {
    // New shape (canonical going forward)
    let load1m: Double?
    let load5m: Double?
    let load15m: Double?
    let memTotalKb: Int64?
    let memAvailKb: Int64?
    let diskTotalBytes: Int64?
    let diskFreeBytes: Int64?
    let diskUsedBytes: Int64?

    // Legacy shape (kept for back-compat with older troubleshooter builds)
    let cpuCount: Int
    let cpuPercent: Double
    let diskFreeGbLegacy: Double
    let diskPercentLegacy: Double
    let loadAvgLegacy: [Double]
    let memPercentLegacy: Double
    let memTotalMbLegacy: Int
    let memUsedMbLegacy: Int
    let temps: [String: Double]

    enum CodingKeys: String, CodingKey {
        case load1m = "load_1m"
        case load5m = "load_5m"
        case load15m = "load_15m"
        case memTotalKb = "mem_total_kb"
        case memAvailKb = "mem_avail_kb"
        case diskTotalBytes = "disk_total"
        case diskFreeBytes = "disk_free"
        case diskUsedBytes = "disk_used"
        case cpuCount = "cpu_count"
        case cpuPercent = "cpu_percent"
        case diskFreeGbLegacy = "disk_free_gb"
        case diskPercentLegacy = "disk_percent"
        case loadAvgLegacy = "load_avg"
        case memPercentLegacy = "mem_percent"
        case memTotalMbLegacy = "mem_total_mb"
        case memUsedMbLegacy = "mem_used_mb"
        case temps
    }

    init(
        load1m: Double? = nil,
        load5m: Double? = nil,
        load15m: Double? = nil,
        memTotalKb: Int64? = nil,
        memAvailKb: Int64? = nil,
        diskTotalBytes: Int64? = nil,
        diskFreeBytes: Int64? = nil,
        diskUsedBytes: Int64? = nil,
        cpuCount: Int = 0,
        cpuPercent: Double = 0.0,
        diskFreeGbLegacy: Double = 0.0,
        diskPercentLegacy: Double = 0.0,
        loadAvgLegacy: [Double] = [],
        memPercentLegacy: Double = 0.0,
        memTotalMbLegacy: Int = 0,
        memUsedMbLegacy: Int = 0,
        temps: [String: Double] = [:]
    ) {
        self.load1m = load1m
        self.load5m = load5m
        self.load15m = load15m
        self.memTotalKb = memTotalKb
        self.memAvailKb = memAvailKb
        self.diskTotalBytes = diskTotalBytes
        self.diskFreeBytes = diskFreeBytes
        self.diskUsedBytes = diskUsedBytes
        self.cpuCount = cpuCount
        self.cpuPercent = cpuPercent
        self.diskFreeGbLegacy = diskFreeGbLegacy
        self.diskPercentLegacy = diskPercentLegacy
        self.loadAvgLegacy = loadAvgLegacy
        self.memPercentLegacy = memPercentLegacy
        self.memTotalMbLegacy = memTotalMbLegacy
        self.memUsedMbLegacy = memUsedMbLegacy
        self.temps = temps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        load1m = try c.decodeIfPresent(Double.self, forKey: .load1m)
        load5m = try c.decodeIfPresent(Double.self, forKey: .load5m)
        load15m = try c.decodeIfPresent(Double.self, forKey: .load15m)
        memTotalKb = try c.decodeIfPresent(Int64.self, forKey: .memTotalKb)
        memAvailKb = try c.decodeIfPresent(Int64.self, forKey: .memAvailKb)
        diskTotalBytes = try c.decodeIfPresent(Int64.self, forKey: .diskTotalBytes)
        diskFreeBytes = try c.decodeIfPresent(Int64.self, forKey: .diskFreeBytes)
        diskUsedBytes = try c.decodeIfPresent(Int64.self, forKey: .diskUsedBytes)
        cpuCount = try c.decodeIfPresent(Int.self, forKey: .cpuCount) ?? 0
        cpuPercent = try c.decodeIfPresent(Double.self, forKey: .cpuPercent) ?? 0.0
        diskFreeGbLegacy = try c.decodeIfPresent(Double.self, forKey: .diskFreeGbLegacy) ?? 0.0
        diskPercentLegacy = try c.decodeIfPresent(Double.self, forKey: .diskPercentLegacy) ?? 0.0
        loadAvgLegacy = try c.decodeIfPresent([Double].self, forKey: .loadAvgLegacy) ?? []
        memPercentLegacy = try c.decodeIfPresent(Double.self, forKey: .memPercentLegacy) ?? 0.0
        memTotalMbLegacy = try c.decodeIfPresent(Int.self, forKey: .memTotalMbLegacy) ?? 0
        memUsedMbLegacy = try c.decodeIfPresent(Int.self, forKey: .memUsedMbLegacy) ?? 0
        temps = try c.decodeIfPresent([String: Double].self, forKey: .temps) ?? [:]
    }

    /// `[1m, 5m, 15m]` load average — prefers the new flat fields.
    var loadAvg: [Double] {
        let new = [load1m, load5m, load15m].compactMap { $0 }
        return new.isEmpty ? loadAvgLegacy : new
    }

    /// Used RAM in MB.
    var memUsedMb: Int {
        if let total = memTotalKb, let avail = memAvailKb {
            return Int(max(total - avail, 0) / 1024)
        }
        return memUsedMbLegacy
    }

    var memTotalMb: Int {
        if let total = memTotalKb { return Int(total / 1024) }
        return memTotalMbLegacy
    }

    var memPercent: Double {
        if let total = memTotalKb, total > 0, let avail = memAvailKb {
            return (Double(total - avail) / Double(total)) * 100.0
        }
        return memPercentLegacy
    }

    var diskFreeGb: Double {
        if let free = diskFreeBytes { return Double(free) / 1_000_000_000.0 }
        return diskFreeGbLegacy
    }

    var diskPercent: Double {
        if let total = diskTotalBytes, total > 0, let used = diskUsedBytes {
            return (Double(used) / Double(total)) * 100.0
        }
        return diskPercentLegacy
    }
}
