import Foundation

/// Whether the user has ever been through the welcome flow - gates whether
/// `ContentView` shows it on launch. Deliberately not tied to whether Full
/// Disk Access is currently granted: a user who already completed onboarding
/// and later revoked access in System Settings should land on Cleanup's
/// limited-access card (item 9), not be sent back through three onboarding
/// steps every launch. Same plain UserDefaults-backed pattern as
/// `ProtectedAppsStore`, just a single flag rather than a set.
enum OnboardingStore {
    private static let key = "DustEater.HasCompletedOnboarding"

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
