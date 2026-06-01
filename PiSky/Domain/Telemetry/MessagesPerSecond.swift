import Foundation

/// Single-stream messages-per-second accumulator — `MessagesPerSecond.kt`.
///
/// Computes MPS from successive `(now, cumulativeMessages)` samples. Reset-resilient: if `messages`
/// decreases (readsb restarted) or `now` doesn't advance, the sample is discarded and the next
/// sample seeds a fresh baseline. Callers never see negative MPS. Not thread-safe — confine to one
/// actor/queue (the repository owns it).
final class MessagesPerSecond {
    private var prevNow: Double?
    private var prevMsgs: Int64?
    private var lastMps: Double?

    /// Feed a fresh sample. Returns the new MPS, or nil until two valid samples have arrived.
    @discardableResult
    func update(now: Double, cumulativeMessages: Int64) -> Double? {
        let pn = prevNow, pm = prevMsgs
        prevNow = now
        prevMsgs = cumulativeMessages

        guard let pn, let pm else { return nil }
        let dt = now - pn
        let dm = cumulativeMessages - pm
        if dt <= 0 || dm < 0 {            // clock didn't advance, or counter went backward (restart)
            lastMps = nil
            return nil
        }
        let mps = Double(dm) / dt
        lastMps = mps
        return mps
    }

    func peek() -> Double? { lastMps }

    func reset() {
        prevNow = nil
        prevMsgs = nil
        lastMps = nil
    }
}
