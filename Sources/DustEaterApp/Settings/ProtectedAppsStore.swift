import Foundation
import Observation

@Observable
final class ProtectedAppsStore {
    private static let userDefaultsKey = "DustEater.ProtectedApps"

    private(set) var protectedBundleIdentifiers: Set<String> {
        didSet {
            saveToUserDefaults()
        }
    }

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.userDefaultsKey) {
            self.protectedBundleIdentifiers = Set(saved)
        } else {
            self.protectedBundleIdentifiers = []
        }
    }

    func isProtected(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier = bundleIdentifier else { return false }
        return protectedBundleIdentifiers.contains(bundleIdentifier)
    }

    func protect(bundleIdentifier: String) {
        protectedBundleIdentifiers.insert(bundleIdentifier)
    }

    func unprotect(bundleIdentifier: String) {
        protectedBundleIdentifiers.remove(bundleIdentifier)
    }

    private func saveToUserDefaults() {
        UserDefaults.standard.set(Array(protectedBundleIdentifiers).sorted(), forKey: Self.userDefaultsKey)
    }
}
