import Foundation

/// A category of hidden storage macOS associates with an app outside its
/// `.app` bundle, keyed by bundle identifier (or, for Application Support,
/// sometimes by display name).
public enum RelatedStorageCategory: String, Sendable, CaseIterable {
    case applicationSupport = "Application Support"
    case caches = "Caches"
    case containers = "Containers"
    case savedState = "Saved State"
    case preferences = "Preferences"
}

/// One piece of hidden storage found to belong to an app.
public struct RelatedStorageItem: Sendable, Identifiable {
    public var id: String { path }
    public let category: RelatedStorageCategory
    public let path: String
    public let size: Int64

    public init(category: RelatedStorageCategory, path: String, size: Int64) {
        self.category = category
        self.path = path
        self.size = size
    }
}

/// The "true disk footprint" of one installed application: its `.app`
/// bundle plus every piece of hidden support/cache/container data macOS
/// associates with it by bundle identifier.
public struct AppDiskEntity: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let bundleIdentifier: String?
    public let appPath: String
    public let appBundleSize: Int64
    public let relatedItems: [RelatedStorageItem]
    public let lastOpenedDate: Date?

    public init(
        displayName: String,
        bundleIdentifier: String?,
        appPath: String,
        appBundleSize: Int64,
        relatedItems: [RelatedStorageItem],
        lastOpenedDate: Date? = nil
    ) {
        self.id = bundleIdentifier ?? appPath
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.appPath = appPath
        self.appBundleSize = appBundleSize
        self.relatedItems = relatedItems
        self.lastOpenedDate = lastOpenedDate
    }

    public var relatedTotalSize: Int64 {
        relatedItems.reduce(into: 0) { $0 += $1.size }
    }

    /// The `.app` bundle size plus every associated hidden folder's size -
    /// the number a WizTree-style "true size" view should show for this app.
    public var trueTotalSize: Int64 {
        appBundleSize + relatedTotalSize
    }
}
