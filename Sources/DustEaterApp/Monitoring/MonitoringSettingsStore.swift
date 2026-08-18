import Foundation
import Observation

/// Persisted monitoring settings - one shared instance owned by
/// `DustEaterApp` and passed into both the main window and the `Settings {}`
/// scene, so a toggle in one place is reflected everywhere immediately.
/// `StatusItemController` also holds this instance and reacts to changes via
/// `withObservationTracking`, the non-View way to observe an `@Observable`.
///
/// Same plain UserDefaults-backed pattern as `ProtectedAppsStore`/
/// `OnboardingStore`, just with more fields - both are off until turned on
/// and never seeded with a "reasonable default that's actually on", per the
/// design handoff's "Both are off until you turn them on."
@Observable
final class MonitoringSettingsStore {
    enum GlanceMode: String {
        case figureAndGauge
        case gaugeOnly
    }

    private enum Keys {
        static let showInMenuBar = "DustEater.Monitoring.ShowInMenuBar"
        static let glanceMode = "DustEater.Monitoring.GlanceMode"
        static let isPaused = "DustEater.Monitoring.IsPaused"
        static let notifyLowSpace = "DustEater.Monitoring.NotifyLowSpace"
        static let notifyJunkGrowth = "DustEater.Monitoring.NotifyJunkGrowth"
        static let lowSpaceThresholdPercent = "DustEater.Monitoring.LowSpaceThresholdPercent"
        static let junkGrowthThresholdBytes = "DustEater.Monitoring.JunkGrowthThresholdBytes"
        static let lastLowSpaceNotified = "DustEater.Monitoring.LastLowSpaceNotified"
        static let lastJunkGrowthNotified = "DustEater.Monitoring.LastJunkGrowthNotified"
        static let hasRequestedNotificationPermission = "DustEater.Monitoring.HasRequestedNotificationPermission"
    }

    var showInMenuBar: Bool { didSet { UserDefaults.standard.set(showInMenuBar, forKey: Keys.showInMenuBar) } }
    var glanceMode: GlanceMode { didSet { UserDefaults.standard.set(glanceMode.rawValue, forKey: Keys.glanceMode) } }
    /// "Pause Monitoring" in the dropdown - distinct from `showInMenuBar`:
    /// the status item and its last-known figures stay visible, but the
    /// 6-hour timer and notification checks stop.
    var isPaused: Bool { didSet { UserDefaults.standard.set(isPaused, forKey: Keys.isPaused) } }
    var notifyLowSpace: Bool { didSet { UserDefaults.standard.set(notifyLowSpace, forKey: Keys.notifyLowSpace) } }
    var notifyJunkGrowth: Bool { didSet { UserDefaults.standard.set(notifyJunkGrowth, forKey: Keys.notifyJunkGrowth) } }
    var lowSpaceThresholdPercent: Double { didSet { UserDefaults.standard.set(lowSpaceThresholdPercent, forKey: Keys.lowSpaceThresholdPercent) } }
    var junkGrowthThresholdBytes: Int64 { didSet { UserDefaults.standard.set(junkGrowthThresholdBytes, forKey: Keys.junkGrowthThresholdBytes) } }

    var lastLowSpaceNotifiedAt: Date? {
        didSet { UserDefaults.standard.set(lastLowSpaceNotifiedAt, forKey: Keys.lastLowSpaceNotified) }
    }
    var lastJunkGrowthNotifiedAt: Date? {
        didSet { UserDefaults.standard.set(lastJunkGrowthNotifiedAt, forKey: Keys.lastJunkGrowthNotified) }
    }
    /// Set the first time either notification toggle is turned on - after
    /// that, `UNUserNotificationCenter.requestAuthorization` is safe to call
    /// again (it's a no-op once the user has answered), but this flag is
    /// what tells `SettingsView` to actually issue the request only on that
    /// first transition rather than on every toggle.
    var hasRequestedNotificationPermission: Bool {
        didSet { UserDefaults.standard.set(hasRequestedNotificationPermission, forKey: Keys.hasRequestedNotificationPermission) }
    }

    init() {
        let d = UserDefaults.standard
        showInMenuBar = d.object(forKey: Keys.showInMenuBar) as? Bool ?? false
        glanceMode = GlanceMode(rawValue: d.string(forKey: Keys.glanceMode) ?? "") ?? .figureAndGauge
        isPaused = d.object(forKey: Keys.isPaused) as? Bool ?? false
        notifyLowSpace = d.object(forKey: Keys.notifyLowSpace) as? Bool ?? false
        notifyJunkGrowth = d.object(forKey: Keys.notifyJunkGrowth) as? Bool ?? false
        lowSpaceThresholdPercent = d.object(forKey: Keys.lowSpaceThresholdPercent) as? Double ?? 10
        junkGrowthThresholdBytes = d.object(forKey: Keys.junkGrowthThresholdBytes) as? Int64 ?? 5_000_000_000
        lastLowSpaceNotifiedAt = d.object(forKey: Keys.lastLowSpaceNotified) as? Date
        lastJunkGrowthNotifiedAt = d.object(forKey: Keys.lastJunkGrowthNotified) as? Date
        hasRequestedNotificationPermission = d.object(forKey: Keys.hasRequestedNotificationPermission) as? Bool ?? false
    }
}
