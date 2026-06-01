import Foundation
import UserNotifications
import UIKit

/// Local-notification hub — ports `EmergencyNotificationHelper` + `MilitaryNotificationHelper` +
/// `HourlyTallyHelper` onto `UNUserNotificationCenter`. Android notification *channels* map to iOS
/// *categories* + *threads* + per-request interruption levels:
///
///   - emergency  → thread "pisky_emergency", interruption `.timeSensitive` (always fires)
///   - military   → thread "pisky_military",  interruption `.timeSensitive` (once-per-hex, gated)
///   - rules      → thread "pisky_rules",     interruption `.active`        (gated, dedup)
///   - hourlyTally→ thread "pisky_hourly",    interruption `.passive`
///
/// On a tap carrying an aircraft hex, the delegate sets `container?.pendingMapHex` for the Map
/// deep-link (the Kotlin `EXTRA_AIRCRAFT_HEX` launch-intent path).
@MainActor
final class NotificationManager: NSObject {
    // Mirror of the Android channel/group identifiers.
    enum Category {
        static let emergency = "pisky_emergency"
        static let military  = "pisky_military"
        static let rules     = "pisky_rules"
        static let hourly    = "pisky_hourly_tally"
    }
    static let hexUserInfoKey = "aircraft_hex"
    static let bgTaskIdentifier = "com.pisky.mobile.hourlytally"

    /// Set by `AppContainer` after construction so notification taps can deep-link to the Map.
    weak var container: AppContainer?

    private let center = UNUserNotificationCenter.current()

    // Per-session dedup sets (mirror AircraftRepositoryImpl's notifiedMilitaryHexes/notifiedRuleKeys).
    private var notifiedMilitaryHexes = Set<String>()
    private var notifiedRuleKeys = Set<String>()

    override init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    /// Request authorization (alert + sound + badge). Idempotent.
    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            ErrorLog.shared.log(level: "W", tag: "Notif", message: "auth request failed", error: error)
        }
    }

    private func registerCategories() {
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: Category.emergency, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.military,  actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.rules,     actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.hourly,    actions: [], intentIdentifiers: []),
        ]
        center.setNotificationCategories(categories)
    }

    // MARK: - Per-tick notification driver

    /// Mirrors `AircraftRepositoryImpl.fireNotifications`: emergencies always; military once-per-hex
    /// (gated by `militaryAlerts`); rules low-alt/high-speed/fav-on-ground (gated, deduped). Prunes
    /// dedup sets to aircraft still visible.
    func fireNotifications(for aircraft: [Aircraft], prefs: AppPreferences) {
        // Emergencies — always.
        for ac in aircraft where ac.emergency != .none {
            postEmergency(ac)
        }

        // Military — newly-seen hexes only, gated by preference.
        if prefs.currentMilitaryAlerts {
            let newMil = aircraft.filter { $0.isMilitary && !notifiedMilitaryHexes.contains($0.hex) }
            for ac in newMil {
                notifiedMilitaryHexes.insert(ac.hex)
                postMilitary(ac)
            }
        }

        // Custom rules.
        let favHexes = Set(aircraft.filter { $0.isFavorite }.map { $0.hex })
        if prefs.currentRuleLowAlt {
            for ac in aircraft where !ac.isOnGround && (ac.altitudeBaro ?? .max) >= 1 && (ac.altitudeBaro ?? .max) < 1000 {
                let key = "lowalt_\(ac.hex)"
                if notifiedRuleKeys.insert(key).inserted { postRule(ac, label: "Low Altitude") }
            }
        }
        if prefs.currentRuleHighSpeed {
            for ac in aircraft where (ac.groundSpeed ?? 0) > 700 {
                let key = "highspd_\(ac.hex)"
                if notifiedRuleKeys.insert(key).inserted { postRule(ac, label: "High Speed") }
            }
        }
        if prefs.currentRuleFavGround {
            for ac in aircraft where ac.isOnGround && favHexes.contains(ac.hex) {
                let key = "favgnd_\(ac.hex)"
                if notifiedRuleKeys.insert(key).inserted { postRule(ac, label: "Favorite on Ground") }
            }
        }

        // Prune dedup sets to currently-visible aircraft.
        let currentHexes = Set(aircraft.map { $0.hex })
        notifiedMilitaryHexes.formIntersection(currentHexes)
        notifiedRuleKeys = notifiedRuleKeys.filter { key in currentHexes.contains { key.hasSuffix("_\($0)") } }
    }

    // MARK: - Individual posts

    private func postEmergency(_ ac: Aircraft) {
        let content = UNMutableNotificationContent()
        content.title = "Emergency: \(ac.displayCallsign)"
        content.body = "\(ac.emergency.rawValue) • \(ac.altitudeDisplay) • \(ac.speedDisplay)"
        content.categoryIdentifier = Category.emergency
        content.threadIdentifier = Category.emergency
        content.interruptionLevel = .timeSensitive
        content.sound = .defaultCritical
        content.userInfo = [Self.hexUserInfoKey: ac.hex]
        deliver(id: "emg_\(ac.hex)", content)
    }

    private func postMilitary(_ ac: Aircraft) {
        let name = ac.classification.militaryName ?? ac.description ?? ac.type
        var parts: [String] = []
        if let name { parts.append(name) }
        if let unit = ac.classification.militaryUnit { parts.append(unit) }
        else if let op = ac.operatorName { parts.append(op) }
        parts.append(ac.altitudeDisplay)
        parts.append(ac.speedDisplay)

        let content = UNMutableNotificationContent()
        content.title = "Military: \(ac.displayCallsign)"
        content.body = parts.joined(separator: " • ")
        content.categoryIdentifier = Category.military
        content.threadIdentifier = Category.military
        content.interruptionLevel = .timeSensitive
        content.sound = .default
        content.userInfo = [Self.hexUserInfoKey: ac.hex]
        deliver(id: "mil_\(ac.hex)", content)
    }

    private func postRule(_ ac: Aircraft, label: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(label): \(ac.displayCallsign)"
        content.body = "\(ac.altitudeDisplay) • \(ac.speedDisplay)"
        content.categoryIdentifier = Category.rules
        content.threadIdentifier = Category.rules
        content.interruptionLevel = .active
        content.sound = .default
        content.userInfo = [Self.hexUserInfoKey: ac.hex]
        deliver(id: "rule_\(label)_\(ac.hex)", content)
    }

    /// Hourly summary — port of `HourlyTallyHelper.postTally`.
    func postTally(loggedToday: Int, taggedToday: Int, militaryToday: Int) {
        let content = UNMutableNotificationContent()
        content.title = "PiSky · \(Self.formatHour())"
        var body = "\(loggedToday) logged • \(taggedToday) tagged"
        if militaryToday > 0 { body += " • \(militaryToday) mil" }
        content.body = body
        content.categoryIdentifier = Category.hourly
        content.threadIdentifier = Category.hourly
        content.interruptionLevel = .passive
        content.sound = nil
        deliver(id: Category.hourly, content)
    }

    private func deliver(id: String, _ content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                ErrorLog.shared.log(level: "W", tag: "Notif", message: "deliver \(id) failed", error: error)
            }
        }
    }

    private static func formatHour() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "h a"
        return f.string(from: Date())
    }
}

// MARK: - Delegate (foreground presentation + tap deep-link)

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if let hex = response.notification.request.content.userInfo[Self.hexUserInfoKey] as? String {
            container?.pendingMapHex = hex
        }
    }
}
