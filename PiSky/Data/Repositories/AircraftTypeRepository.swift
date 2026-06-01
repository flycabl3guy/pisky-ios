import Foundation

/// One resolved military-aircraft record — port of Kotlin `MilAircraftInfo`.
struct MilAircraftInfo: Sendable, Equatable {
    let typeName: String        // e.g. "Boeing C-17A Globemaster III"
    let operatorName: String    // e.g. "United States Air Force"
    let registration: String?   // e.g. "93-0604"
}

/// Bundled military-aircraft database + OTA cache — port of `AircraftTypeRepository`.
///
/// Loads `us_military_aircraft.csv` from the app bundle (Resources), columns `hex|reg|operator|type`
/// (comma-separated), lazily and once. The OTA cache (`pisky_mil_db.json`, synced from the Pi) is
/// layered on top and overrides bundled entries. Thread-safe via an internal lock; `@unchecked
/// Sendable` because the only mutable state is guarded.
final class AircraftTypeRepository: @unchecked Sendable {
    private let lock = NSLock()
    private var milHexMap: [String: MilAircraftInfo] = [:]
    private var milHexNameMap: [String: String] = [:]
    private var loaded = false

    init() {}

    // MARK: - Public API

    /// Look up a specific aircraft by ICAO hex (case-insensitive).
    func lookupMilHex(_ hex: String) -> MilAircraftInfo? {
        ensureLoaded()
        return lock.withLock { milHexMap[hex.uppercased().trimmingCharacters(in: .whitespaces)] }
    }

    /// Uppercase hex set for O(1) membership tests.
    func getMilHexSet() -> Set<String> {
        ensureLoaded()
        return lock.withLock { Set(milHexMap.keys) }
    }

    /// hex (uppercase) → display type name.
    func getMilHexNameMap() -> [String: String] {
        ensureLoaded()
        return lock.withLock { milHexNameMap }
    }

    /// Persist a freshly-fetched OTA database and force a reload on next access.
    func applyOtaUpdate(_ response: MilDbResponseDto) {
        guard let url = otaCacheURL else { return }
        do {
            let data = try JSONEncoder().encode(OtaCacheFile(from: response))
            try data.write(to: url, options: .atomic)
            lock.withLock { loaded = false }
            ErrorLog.shared.log(level: "I", tag: "MilDB",
                                message: "OTA mil DB saved: \(response.count) entries (\(response.version))")
        } catch {
            ErrorLog.shared.log(level: "W", tag: "MilDB", message: "Failed to save OTA mil cache", error: error)
        }
    }

    /// Version string of the cached OTA database, or nil if none.
    func getOtaVersion() -> String? {
        guard let url = otaCacheURL, let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(OtaCacheFile.self, from: data) else { return nil }
        return cache.version
    }

    // MARK: - Loading

    private func ensureLoaded() {
        lock.withLock {
            guard !loaded else { return }
            let bundled = loadBundledCsvLocked()
            let ota = loadOtaCacheLocked()
            milHexMap = bundled.merging(ota) { _, new in new }   // OTA overrides bundled
            milHexNameMap = milHexMap.mapValues { $0.typeName }
            loaded = true
            ErrorLog.shared.log(level: "D", tag: "MilDB",
                                message: "loaded \(bundled.count) bundled + \(ota.count) OTA = \(milHexMap.count) total")
        }
    }

    /// `hex,reg,operator,type` CSV from the app bundle (header row dropped).
    private func loadBundledCsvLocked() -> [String: MilAircraftInfo] {
        guard let url = Bundle.main.url(forResource: "us_military_aircraft", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var map: [String: MilAircraftInfo] = [:]
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for rawLine in lines.dropFirst() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let cols = line.components(separatedBy: ",")
            if cols.count < 4 { continue }
            let hex = cols[0].trimmingCharacters(in: .whitespaces).uppercased()
            if hex.isEmpty { continue }
            let regRaw = cols[1].trimmingCharacters(in: .whitespaces)
            let reg: String? = (regRaw.isEmpty || regRaw == "????") ? nil : regRaw
            let op = cols[2].trimmingCharacters(in: .whitespaces)
            if op.isEmpty { continue }
            let type = cols[3].trimmingCharacters(in: .whitespaces)
            if type.isEmpty { continue }
            map[hex] = MilAircraftInfo(typeName: type, operatorName: op, registration: reg)
        }
        return map
    }

    private func loadOtaCacheLocked() -> [String: MilAircraftInfo] {
        guard let url = otaCacheURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(OtaCacheFile.self, from: data) else { return [:] }
        var map: [String: MilAircraftInfo] = [:]
        for entry in cache.aircraft {
            let hex = entry.hex.uppercased().trimmingCharacters(in: .whitespaces)
            map[hex] = MilAircraftInfo(
                typeName: entry.desc ?? entry.type ?? "Military Aircraft",
                operatorName: entry.ownOp ?? "",
                registration: entry.reg
            )
        }
        return map
    }

    private var otaCacheURL: URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return dir.appendingPathComponent("pisky_mil_db.json")
    }
}

/// Codable mirror of `MilDbResponseDto` for round-tripping the OTA cache to disk (the DTO itself is
/// decode-only, so we re-shape it with the same short keys the Pi emits).
private struct OtaCacheFile: Codable {
    let version: String
    let count: Int
    let aircraft: [Entry]

    struct Entry: Codable {
        let hex: String
        let desc: String?
        let ownOp: String?
        let type: String?
        let reg: String?

        enum CodingKeys: String, CodingKey {
            case hex = "h", desc = "d", ownOp = "o", type = "t", reg = "r"
        }
    }

    init(from dto: MilDbResponseDto) {
        version = dto.version
        count = dto.count
        aircraft = dto.aircraft.map {
            Entry(hex: $0.hex, desc: $0.desc, ownOp: $0.ownOp, type: $0.type, reg: $0.reg)
        }
    }
}
