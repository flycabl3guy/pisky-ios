import Foundation
import Combine
import os

/// Process-wide error log — port of the Android `ErrorLog` object. Keeps a 200-entry in-memory ring
/// buffer (for the Diagnostics screen) plus appends to a rolling file in Application Support so
/// records survive restarts. Routes through `os.Logger` (the contract forbids `print`).
final class ErrorLog: @unchecked Sendable {
    static let shared = ErrorLog()

    struct Entry: Identifiable, Equatable, Sendable {
        let id = UUID()
        let timestampMs: Int64
        let level: String        // "W" / "E" / "CRASH" / "I" / "D"
        let tag: String
        let message: String
        let stackTrace: String?

        static func == (a: Entry, b: Entry) -> Bool { a.id == b.id }
    }

    private let maxEntries = 200
    private let maxFileBytes: Int = 256 * 1024
    private let logger = Logger(subsystem: "com.pisky.mobile", category: "ErrorLog")
    private let lock = NSLock()

    private var buffer: [Entry] = []
    private let entriesSubject = CurrentValueSubject<[Entry], Never>([])
    /// Live stream of the ring buffer (replays latest).
    var entries: AnyPublisher<[Entry], Never> { entriesSubject.eraseToAnyPublisher() }
    var currentEntries: [Entry] { lock.withLock { buffer } }

    private lazy var logFileURL: URL? = {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return dir.appendingPathComponent("pisky-errors.log")
    }()

    private static let tsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private init() {}

    func log(level: String, tag: String, message: String, error: Error? = nil) {
        let entry = Entry(
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            level: level,
            tag: tag,
            message: message,
            stackTrace: error.map { "\($0)" }
        )
        switch level {
        case "E", "CRASH": logger.error("\(tag, privacy: .public): \(message, privacy: .public)")
        case "W":          logger.warning("\(tag, privacy: .public): \(message, privacy: .public)")
        default:           logger.debug("\(tag, privacy: .public): \(message, privacy: .public)")
        }
        lock.withLock {
            if buffer.count >= maxEntries { buffer.removeFirst(buffer.count - maxEntries + 1) }
            buffer.append(entry)
            entriesSubject.send(buffer)
        }
        appendToFile(entry)
    }

    func clear() {
        lock.withLock {
            buffer.removeAll()
            entriesSubject.send([])
        }
        if let url = logFileURL { try? "".write(to: url, atomically: true, encoding: .utf8) }
    }

    func exportText() -> String {
        let snapshot = lock.withLock { buffer }
        var header = "=== PiSky Error Log ===\n"
        header += "device:   \(deviceModel())\n"
        header += "os:       \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        header += "entries:  \(snapshot.count)\n"
        header += "exported: \(Self.tsFormatter.string(from: Date()))\n"
        header += "=======================\n"
        return header + snapshot.map(format).joined(separator: "\n")
    }

    // MARK: - Private

    private func format(_ e: Entry) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(e.timestampMs) / 1000)
        let head = "\(Self.tsFormatter.string(from: date)) \(e.level)/\(e.tag): \(e.message)"
        if let st = e.stackTrace { return "\(head)\n\(st)" }
        return head
    }

    private func appendToFile(_ e: Entry) {
        guard let url = logFileURL else { return }
        let line = format(e) + "\n"
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int, size > maxFileBytes,
           let existing = try? String(contentsOf: url, encoding: .utf8) {
            let tail = String(existing.suffix(maxFileBytes / 2))
            try? (tail + line).write(to: url, atomically: true, encoding: .utf8)
            return
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func deviceModel() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let mirror = Mirror(reflecting: sysinfo.machine)
        let model = mirror.children.compactMap { ($0.value as? Int8).map { Character(UnicodeScalar(UInt8(bitPattern: $0))) } }
            .filter { $0 != "\0" }
        return String(model)
    }
}
