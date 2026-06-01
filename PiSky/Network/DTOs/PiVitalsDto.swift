import Foundation

/// Wire shape of `pi-vitals.json` — `PiVitalsDto.kt`. All sub-blocks nullable/defaulted so a
/// partial reader failure (missing thermal zone, dump978 not installed) doesn't crash decoding.
struct PiVitalsDto: Decodable, Sendable {
    let now: Double
    let host: String
    let uptimeSec: Double?
    let temp: PiTempDto?
    /// `vcgencmd get_throttled` raw value, e.g. "0x0" or "0x50000".
    let throttled: String
    let throttledOk: Bool
    let coreVolt: Double?
    let armClockHz: Int64?
    let load: PiLoadDto?
    let mem: PiMemDto?
    let disk: PiDiskDto?
    let sdr: PiSdrDto?
    let services: PiServicesDto?
    let bands: PiBandsDto?

    enum CodingKeys: String, CodingKey {
        case now
        case host
        case uptimeSec = "uptime_sec"
        case temp
        case throttled
        case throttledOk = "throttled_ok"
        case coreVolt = "core_volt"
        case armClockHz = "arm_clock_hz"
        case load
        case mem
        case disk
        case sdr
        case services
        case bands
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        now = try c.decodeIfPresent(Double.self, forKey: .now) ?? 0.0
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        uptimeSec = try c.decodeIfPresent(Double.self, forKey: .uptimeSec)
        temp = try c.decodeIfPresent(PiTempDto.self, forKey: .temp)
        throttled = try c.decodeIfPresent(String.self, forKey: .throttled) ?? "0x0"
        throttledOk = try c.decodeIfPresent(Bool.self, forKey: .throttledOk) ?? true
        coreVolt = try c.decodeIfPresent(Double.self, forKey: .coreVolt)
        armClockHz = try c.decodeIfPresent(Int64.self, forKey: .armClockHz)
        load = try c.decodeIfPresent(PiLoadDto.self, forKey: .load)
        mem = try c.decodeIfPresent(PiMemDto.self, forKey: .mem)
        disk = try c.decodeIfPresent(PiDiskDto.self, forKey: .disk)
        sdr = try c.decodeIfPresent(PiSdrDto.self, forKey: .sdr)
        services = try c.decodeIfPresent(PiServicesDto.self, forKey: .services)
        bands = try c.decodeIfPresent(PiBandsDto.self, forKey: .bands)
    }
}

struct PiTempDto: Decodable, Sendable {
    let celsius: Double
    let fahrenheit: Double

    enum CodingKeys: String, CodingKey {
        case celsius
        case fahrenheit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        celsius = try c.decodeIfPresent(Double.self, forKey: .celsius) ?? 0.0
        fahrenheit = try c.decodeIfPresent(Double.self, forKey: .fahrenheit) ?? 0.0
    }
}

struct PiLoadDto: Decodable, Sendable {
    let load1m: Double
    let load5m: Double
    let load15m: Double

    enum CodingKeys: String, CodingKey {
        case load1m = "1m"
        case load5m = "5m"
        case load15m = "15m"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        load1m = try c.decodeIfPresent(Double.self, forKey: .load1m) ?? 0.0
        load5m = try c.decodeIfPresent(Double.self, forKey: .load5m) ?? 0.0
        load15m = try c.decodeIfPresent(Double.self, forKey: .load15m) ?? 0.0
    }
}

struct PiMemDto: Decodable, Sendable {
    let totalKb: Int64
    let availKb: Int64
    let usedKb: Int64

    enum CodingKeys: String, CodingKey {
        case totalKb = "total_kb"
        case availKb = "avail_kb"
        case usedKb = "used_kb"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalKb = try c.decodeIfPresent(Int64.self, forKey: .totalKb) ?? 0
        availKb = try c.decodeIfPresent(Int64.self, forKey: .availKb) ?? 0
        usedKb = try c.decodeIfPresent(Int64.self, forKey: .usedKb) ?? 0
    }

    var percentUsed: Double { totalKb > 0 ? Double(usedKb) * 100.0 / Double(totalKb) : 0.0 }
    var totalMb: Int64 { totalKb / 1024 }
    var usedMb: Int64 { usedKb / 1024 }
}

struct PiDiskDto: Decodable, Sendable {
    let totalBytes: Int64
    let usedBytes: Int64
    let freeBytes: Int64

    enum CodingKeys: String, CodingKey {
        case totalBytes = "total"
        case usedBytes = "used"
        case freeBytes = "free"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalBytes = try c.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        usedBytes = try c.decodeIfPresent(Int64.self, forKey: .usedBytes) ?? 0
        freeBytes = try c.decodeIfPresent(Int64.self, forKey: .freeBytes) ?? 0
    }

    var freeGb: Double { Double(freeBytes) / 1_000_000_000.0 }
    var percentUsed: Double { totalBytes > 0 ? Double(usedBytes) * 100.0 / Double(totalBytes) : 0.0 }
}

struct PiSdrDto: Decodable, Sendable {
    /// Vendor-specific USB iface count. Each RTL-SDR dongle reports 2 ifaces.
    let ifaceCount: Int

    enum CodingKeys: String, CodingKey {
        case ifaceCount = "iface_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ifaceCount = try c.decodeIfPresent(Int.self, forKey: .ifaceCount) ?? 0
    }
}

struct PiServicesDto: Decodable, Sendable {
    let piawareToFa: Bool
    /// Pre-readsb-migration name (PiAware native default). Kept for back-compat.
    let dump1090Fa: Bool
    /// Post-readsb-migration name (2026-04-29). pi-vitals.sh emits this key now.
    let readsb: Bool
    let dump978Fa: Bool
    let skyaware978: Bool

    enum CodingKeys: String, CodingKey {
        case piawareToFa = "piaware_to_fa"
        case dump1090Fa = "dump1090_fa"
        case readsb
        case dump978Fa = "dump978_fa"
        case skyaware978
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        piawareToFa = try c.decodeIfPresent(Bool.self, forKey: .piawareToFa) ?? false
        dump1090Fa = try c.decodeIfPresent(Bool.self, forKey: .dump1090Fa) ?? false
        readsb = try c.decodeIfPresent(Bool.self, forKey: .readsb) ?? false
        dump978Fa = try c.decodeIfPresent(Bool.self, forKey: .dump978Fa) ?? false
        skyaware978 = try c.decodeIfPresent(Bool.self, forKey: .skyaware978) ?? false
    }

    /// True if either decoder name reports running.
    var decoderActive: Bool { readsb || dump1090Fa }
}

struct PiBandsDto: Decodable, Sendable {
    let band1090: PiBandDto?
    let band978: PiBandDto?

    enum CodingKeys: String, CodingKey {
        case band1090 = "1090"
        case band978 = "978"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        band1090 = try c.decodeIfPresent(PiBandDto.self, forKey: .band1090)
        band978 = try c.decodeIfPresent(PiBandDto.self, forKey: .band978)
    }
}

struct PiBandDto: Decodable, Sendable {
    let available: Bool
    let now: Double
    let messagesCumulative: Int64
    let aircraftCount: Int
    let deltaTSec: Double?
    /// Null on first sample after pi-vitals timer fires, on counter resets, or probe failure.
    let mps: Double?

    enum CodingKeys: String, CodingKey {
        case available
        case now
        case messagesCumulative = "messages_cumulative"
        case aircraftCount = "aircraft_count"
        case deltaTSec = "delta_t_sec"
        case mps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available = try c.decodeIfPresent(Bool.self, forKey: .available) ?? false
        now = try c.decodeIfPresent(Double.self, forKey: .now) ?? 0.0
        messagesCumulative = try c.decodeIfPresent(Int64.self, forKey: .messagesCumulative) ?? 0
        aircraftCount = try c.decodeIfPresent(Int.self, forKey: .aircraftCount) ?? 0
        deltaTSec = try c.decodeIfPresent(Double.self, forKey: .deltaTSec)
        mps = try c.decodeIfPresent(Double.self, forKey: .mps)
    }
}
