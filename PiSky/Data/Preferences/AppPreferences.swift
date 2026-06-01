import Foundation
import Combine

/// UserDefaults-backed display/map/notification/data settings — port of the DataStore-backed
/// `AppPreferences` in `core:data`. Each Kotlin `Flow<T>` becomes a `CurrentValueSubject`-backed
/// `AnyPublisher<T, Never>` (hot, replays latest) plus a synchronous current getter and a setter.
/// Defaults match the Kotlin `?: …` fallbacks exactly.
@MainActor
final class AppPreferences {
    private let defaults: UserDefaults

    // Keys — verbatim from the Kotlin companion object.
    private enum Key {
        static let logDepth        = "log_depth"
        static let pollInterval    = "poll_interval_idx"
        static let mapStyle        = "map_style"
        static let rangeRings      = "show_range_rings"
        static let trails          = "show_trails"
        static let trailLength     = "trail_length"
        static let emergencyAlerts = "emergency_alerts"
        static let militaryAlerts  = "military_alerts"
        static let notifSound      = "notif_sound"
        static let ruleLowAlt      = "rule_low_alt"
        static let ruleHighSpeed   = "rule_high_speed"
        static let ruleFavGround   = "rule_fav_ground"
        static let peakRangeMi     = "peak_range_mi"
        static let peakRangeDate   = "peak_range_date"
    }

    // Backing subjects, seeded from the persisted value or the Kotlin default.
    private let logDepthSubject:        CurrentValueSubject<Float, Never>
    private let pollIntervalIdxSubject: CurrentValueSubject<Int, Never>
    private let mapStyleSubject:        CurrentValueSubject<String, Never>
    private let showRangeRingsSubject:  CurrentValueSubject<Bool, Never>
    private let showTrailsSubject:      CurrentValueSubject<Bool, Never>
    private let trailLengthSubject:     CurrentValueSubject<Float, Never>
    private let emergencyAlertsSubject: CurrentValueSubject<Bool, Never>
    private let militaryAlertsSubject:  CurrentValueSubject<Bool, Never>
    private let notifSoundSubject:      CurrentValueSubject<String, Never>
    private let ruleLowAltSubject:      CurrentValueSubject<Bool, Never>
    private let ruleHighSpeedSubject:   CurrentValueSubject<Bool, Never>
    private let ruleFavGroundSubject:   CurrentValueSubject<Bool, Never>
    private let peakRangeMiSubject:     CurrentValueSubject<Float, Never>
    private let peakRangeDateSubject:   CurrentValueSubject<String, Never>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        func float(_ k: String, _ def: Float) -> Float { defaults.object(forKey: k) == nil ? def : defaults.float(forKey: k) }
        func int(_ k: String, _ def: Int) -> Int { defaults.object(forKey: k) == nil ? def : defaults.integer(forKey: k) }
        func bool(_ k: String, _ def: Bool) -> Bool { defaults.object(forKey: k) == nil ? def : defaults.bool(forKey: k) }
        func string(_ k: String, _ def: String) -> String { defaults.string(forKey: k) ?? def }

        logDepthSubject        = .init(float(Key.logDepth, 2))
        pollIntervalIdxSubject = .init(int(Key.pollInterval, 0))
        mapStyleSubject        = .init(string(Key.mapStyle, "Street"))
        showRangeRingsSubject  = .init(bool(Key.rangeRings, true))
        showTrailsSubject      = .init(bool(Key.trails, true))
        trailLengthSubject     = .init(float(Key.trailLength, 20))
        emergencyAlertsSubject = .init(bool(Key.emergencyAlerts, true))
        militaryAlertsSubject  = .init(bool(Key.militaryAlerts, true))
        notifSoundSubject      = .init(string(Key.notifSound, "Chime"))
        ruleLowAltSubject      = .init(bool(Key.ruleLowAlt, true))
        ruleHighSpeedSubject   = .init(bool(Key.ruleHighSpeed, true))
        ruleFavGroundSubject   = .init(bool(Key.ruleFavGround, true))
        peakRangeMiSubject     = .init(float(Key.peakRangeMi, 0))
        peakRangeDateSubject   = .init(string(Key.peakRangeDate, ""))
    }

    // MARK: - Observers (AnyPublisher, replays latest)

    var logDepth:        AnyPublisher<Float, Never>  { logDepthSubject.eraseToAnyPublisher() }
    var pollIntervalIdx: AnyPublisher<Int, Never>    { pollIntervalIdxSubject.eraseToAnyPublisher() }
    var mapStyle:        AnyPublisher<String, Never> { mapStyleSubject.eraseToAnyPublisher() }
    var showRangeRings:  AnyPublisher<Bool, Never>   { showRangeRingsSubject.eraseToAnyPublisher() }
    var showTrails:      AnyPublisher<Bool, Never>   { showTrailsSubject.eraseToAnyPublisher() }
    var trailLength:     AnyPublisher<Float, Never>  { trailLengthSubject.eraseToAnyPublisher() }
    var emergencyAlerts: AnyPublisher<Bool, Never>   { emergencyAlertsSubject.eraseToAnyPublisher() }
    var militaryAlerts:  AnyPublisher<Bool, Never>   { militaryAlertsSubject.eraseToAnyPublisher() }
    var notifSound:      AnyPublisher<String, Never> { notifSoundSubject.eraseToAnyPublisher() }
    var ruleLowAlt:      AnyPublisher<Bool, Never>   { ruleLowAltSubject.eraseToAnyPublisher() }
    var ruleHighSpeed:   AnyPublisher<Bool, Never>   { ruleHighSpeedSubject.eraseToAnyPublisher() }
    var ruleFavGround:   AnyPublisher<Bool, Never>   { ruleFavGroundSubject.eraseToAnyPublisher() }
    var peakRangeMi:     AnyPublisher<Float, Never>  { peakRangeMiSubject.eraseToAnyPublisher() }
    var peakRangeDate:   AnyPublisher<String, Never> { peakRangeDateSubject.eraseToAnyPublisher() }

    // MARK: - Current getters (synchronous; the latest subject value)

    var currentLogDepth: Float          { logDepthSubject.value }
    var currentPollIntervalIdx: Int     { pollIntervalIdxSubject.value }
    var currentMapStyle: String         { mapStyleSubject.value }
    var currentShowRangeRings: Bool     { showRangeRingsSubject.value }
    var currentShowTrails: Bool         { showTrailsSubject.value }
    var currentTrailLength: Float       { trailLengthSubject.value }
    var currentEmergencyAlerts: Bool    { emergencyAlertsSubject.value }
    var currentMilitaryAlerts: Bool     { militaryAlertsSubject.value }
    var currentNotifSound: String       { notifSoundSubject.value }
    var currentRuleLowAlt: Bool         { ruleLowAltSubject.value }
    var currentRuleHighSpeed: Bool      { ruleHighSpeedSubject.value }
    var currentRuleFavGround: Bool      { ruleFavGroundSubject.value }
    var currentPeakRangeMi: Float       { peakRangeMiSubject.value }
    var currentPeakRangeDate: String    { peakRangeDateSubject.value }

    // MARK: - Setters (persist + push to subject)

    func setLogDepth(_ v: Float)        { defaults.set(v, forKey: Key.logDepth); logDepthSubject.send(v) }
    func setPollIntervalIdx(_ v: Int)   { defaults.set(v, forKey: Key.pollInterval); pollIntervalIdxSubject.send(v) }
    func setMapStyle(_ v: String)       { defaults.set(v, forKey: Key.mapStyle); mapStyleSubject.send(v) }
    func setShowRangeRings(_ v: Bool)   { defaults.set(v, forKey: Key.rangeRings); showRangeRingsSubject.send(v) }
    func setShowTrails(_ v: Bool)       { defaults.set(v, forKey: Key.trails); showTrailsSubject.send(v) }
    func setTrailLength(_ v: Float)     { defaults.set(v, forKey: Key.trailLength); trailLengthSubject.send(v) }
    func setEmergencyAlerts(_ v: Bool)  { defaults.set(v, forKey: Key.emergencyAlerts); emergencyAlertsSubject.send(v) }
    func setMilitaryAlerts(_ v: Bool)   { defaults.set(v, forKey: Key.militaryAlerts); militaryAlertsSubject.send(v) }
    func setNotifSound(_ v: String)     { defaults.set(v, forKey: Key.notifSound); notifSoundSubject.send(v) }
    func setRuleLowAlt(_ v: Bool)       { defaults.set(v, forKey: Key.ruleLowAlt); ruleLowAltSubject.send(v) }
    func setRuleHighSpeed(_ v: Bool)    { defaults.set(v, forKey: Key.ruleHighSpeed); ruleHighSpeedSubject.send(v) }
    func setRuleFavGround(_ v: Bool)    { defaults.set(v, forKey: Key.ruleFavGround); ruleFavGroundSubject.send(v) }

    func setPeakRange(mi: Float, date: String) {
        defaults.set(mi, forKey: Key.peakRangeMi)
        defaults.set(date, forKey: Key.peakRangeDate)
        peakRangeMiSubject.send(mi)
        peakRangeDateSubject.send(date)
    }
}
