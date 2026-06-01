import Foundation

/// Canonical RF-telemetry formulas — ported from `core/domain/telemetry/RfTelemetry.kt`.
/// Any tile showing SNR / strong-signal % / overload state should go through here.
enum RfTelemetry {

    /// Mean SNR (dB) = signal − noise, both dBFS. nil if either input is missing.
    static func snrDb(signalDbfs: Double?, noiseDbfs: Double?) -> Double? {
        guard let s = signalDbfs, let n = noiseDbfs else { return nil }
        return s - n
    }

    /// Strong-signal percentage. readsb emits `strong_signals` as a per-window COUNT; this converts
    /// to a percentage. Denominator must be `messages_valid`, not raw `modes`. nil if denom ≤ 0.
    static func strongSignalPct(strongSignalsCount: Int, messagesInWindow: Int) -> Double? {
        guard messagesInWindow > 0 else { return nil }
        return Double(strongSignalsCount) * 100.0 / Double(messagesInWindow)
    }

    /// Bad-frame ratio. Sustained > 0.85 ⇒ gain too high / local interference. nil if denom ≤ 0.
    static func badFrameRatio(badFrames: Int64, totalModesFrames: Int64) -> Double? {
        guard totalModesFrames > 0 else { return nil }
        return Double(badFrames) / Double(totalModesFrames)
    }

    /// Strong-signal % above which a hot peak counts as sustained overload (not a single flyover).
    static let nearClippingPctThreshold = 5.0

    /// Classify overall RF health. Order is intentional — most severe wins. NEAR_CLIPPING requires
    /// BOTH a hot peak AND a sustained strong-signal rate (suppresses one-flyover false alarms).
    static func classify(samplesDropped: Int64,
                         peakSignalDbfs: Double?,
                         snrDb: Double?,
                         badRatio: Double?,
                         strongSignalPct: Double? = nil) -> RfHealth {
        if samplesDropped > 0 { return .overloadUsb }
        if let peak = peakSignalDbfs, peak > -3.0, (strongSignalPct ?? 0) > nearClippingPctThreshold {
            return .nearClipping
        }
        if let bad = badRatio, bad > 0.85 { return .noisy }
        guard let snr = snrDb else { return .unknown }
        if snr < 8.0  { return .weak }
        if snr < 15.0 { return .ok }
        return .strong
    }

    /// Round to one decimal so the UI doesn't render "−9.199999".
    static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
}

enum RfHealth: Sendable {
    case unknown, weak, ok, strong, noisy, nearClipping, overloadUsb

    var label: String {
        switch self {
        case .unknown:      return "Unknown"
        case .weak:         return "Weak"
        case .ok:           return "OK"
        case .strong:       return "Strong"
        case .noisy:        return "Noisy"
        case .nearClipping: return "Near clipping"
        case .overloadUsb:  return "USB overload"
        }
    }
}
