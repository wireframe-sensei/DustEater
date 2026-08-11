import Foundation

public struct OrphanedAppData: Sendable, Identifiable {
    public var id: String { inferredIdentifier }
    public let inferredIdentifier: String
    public let inferredDisplayName: String
    public let items: [RelatedStorageItem]
    public let isVendorSibling: Bool

    public init(inferredIdentifier: String, items: [RelatedStorageItem], isVendorSibling: Bool = false) {
        self.inferredIdentifier = inferredIdentifier
        self.inferredDisplayName = inferredIdentifier
        self.items = items
        self.isVendorSibling = isVendorSibling
    }

    public var totalSize: Int64 {
        items.reduce(into: 0) { $0 += $1.size }
    }
}

public struct OrphanScanResult: Sendable {
    public let apps: [OrphanedAppData]
    public let developerTools: [OrphanedAppData]
}

public enum OrphanFinder {
    public static func findOrphanedData(
        installedApps: [AppDiskEntity],
        homeDirectory: String = NSHomeDirectory()
    ) async -> OrphanScanResult {
        let knownBundleIDs = Set(installedApps.compactMap(\.bundleIdentifier))
        let knownDisplayNames = Set(installedApps.map(\.displayName))
        let knownProductNames = Set(installedApps.compactMap {
            $0.bundleIdentifier?.split(separator: ".").last.map(String.init)
        })
        let vendorNames = Set(installedApps.compactMap {
            $0.bundleIdentifier.flatMap(VendorFolderExpander.vendorName(fromBundleIdentifier:))
        })
        let knownNames = knownBundleIDs.union(knownDisplayNames).union(knownProductNames).map { $0.lowercased() }

        var orphansByIdentifier: [String: [RelatedStorageItem]] = [:]
        var isVendorSiblingByIdentifier: [String: Bool] = [:]

        let libraryPath = (homeDirectory as NSString).appendingPathComponent("Library")
        let fileManager = FileManager.default

        let categories: [(folder: String, category: RelatedStorageCategory, stripSuffix: String?)] = [
            ("Containers", .containers, nil),
            ("Caches", .caches, nil),
            ("Application Support", .applicationSupport, nil),
            ("Saved Application State", .savedState, ".savedState"),
            ("Preferences", .preferences, ".plist"),
        ]

        for (folder, category, stripSuffix) in categories {
            let folderPath = (libraryPath as NSString).appendingPathComponent(folder)
            guard fileManager.fileExists(atPath: folderPath) else { continue }

            for entry in VendorFolderExpander.listEntries(in: folderPath, vendorNames: vendorNames, knownNames: Set(knownNames)) {
                var name = entry.matchName
                if category == .preferences {
                    if name.hasPrefix(".") || name == "ByHost" || name.hasSuffix("~") {
                        continue
                    }
                }

                var inferredID = name

                if let stripSuffix = stripSuffix, name.hasSuffix(stripSuffix) {
                    inferredID = String(name.dropLast(stripSuffix.count))
                }

                let isKnownExact = knownBundleIDs.contains { $0.caseInsensitiveCompare(inferredID) == .orderedSame } ||
                    knownDisplayNames.contains { $0.caseInsensitiveCompare(inferredID) == .orderedSame } ||
                    knownProductNames.contains { $0.caseInsensitiveCompare(inferredID) == .orderedSame }

                let isKnownPrefix = !isKnownExact && (knownBundleIDs.union(knownProductNames)).contains { known in
                    let lowerKnown = known.lowercased()
                    let lowerID = inferredID.lowercased()
                    guard lowerID.hasPrefix(lowerKnown), lowerID.count > lowerKnown.count else { return false }
                    let separatorIndex = lowerID.index(lowerID.startIndex, offsetBy: lowerKnown.count)
                    return !lowerID[separatorIndex].isLetter && !lowerID[separatorIndex].isNumber
                }

                if !isKnownExact && !isKnownPrefix && !AppleSystemServices.isAppleSystemService(inferredID) {
                    let size = await StorageSizing.sizeOnDisk(atPath: entry.path)
                    if size > 0 {
                        let relatedItem = RelatedStorageItem(category: category, path: entry.path, size: size)
                        orphansByIdentifier[inferredID, default: []].append(relatedItem)
                        isVendorSiblingByIdentifier[inferredID] = (isVendorSiblingByIdentifier[inferredID] ?? false) || entry.isVendorSibling
                    }
                }
            }
        }

        let allOrphans = orphansByIdentifier
            .map { inferredID, items in
                let isVendorSibling = isVendorSiblingByIdentifier[inferredID] ?? false
                return OrphanedAppData(inferredIdentifier: inferredID, items: items, isVendorSibling: isVendorSibling)
            }
            .sorted { $0.totalSize > $1.totalSize }

        let apps = allOrphans.filter { !DeveloperToolFolders.isDeveloperTool($0.inferredIdentifier) }
        let developerTools = allOrphans.filter { DeveloperToolFolders.isDeveloperTool($0.inferredIdentifier) }

        return OrphanScanResult(apps: apps, developerTools: developerTools)
    }
}
