import Foundation

/// A single sized purge candidate, pairing a catalog definition (fixed or
/// tree-discovered) with its measured size.
public struct PurgeTarget: Sendable, Identifiable {
    public var id: String { path }

    public let definition: PurgeTargetDefinition
    public let sizeBytes: Int64

    public init(definition: PurgeTargetDefinition, sizeBytes: Int64) {
        self.definition = definition
        self.sizeBytes = sizeBytes
    }

    public var path: String { definition.path }
    public var safety: PurgeSafetyLevel { definition.safety }
}

extension PurgeTarget: Equatable {
    /// Deliberately not synthesized. A target's identity is its path, and
    /// the only thing that ever changes about one after creation is its
    /// size - the editorial strings on `definition` are compile-time
    /// constants, so comparing them on every SwiftUI diff is pure waste.
    /// Same reasoning as `FileNode`'s hand-written `==`, applied for a
    /// different reason: there it was avoiding tree recursion, here it's a
    /// dozen immutable strings per row.
    public static func == (lhs: PurgeTarget, rhs: PurgeTarget) -> Bool {
        lhs.path == rhs.path && lhs.sizeBytes == rhs.sizeBytes
    }
}

/// A group of `PurgeTarget`s under one developer or creative-app category,
/// as rendered by one section of the Developer Kit grid.
public struct PurgeCategory: Sendable, Identifiable, Equatable {
    public var id: String { categoryID.rawValue }

    public let categoryID: PurgeCategoryID
    public let targets: [PurgeTarget]

    public init(categoryID: PurgeCategoryID, targets: [PurgeTarget]) {
        self.categoryID = categoryID
        self.targets = targets
    }

    public var title: String { categoryID.displayName }
    public var systemImage: String { categoryID.systemImage }

    /// Every matched target's size, including `.reportOnly` ones.
    public var totalBytes: Int64 {
        targets.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Excludes `.reportOnly` targets. The header total must never promise
    /// space the user cannot actually reclaim from this screen - Docker's
    /// multi-gigabyte `Docker.raw` counts toward "found," never toward
    /// "reclaimable".
    public var reclaimableBytes: Int64 {
        targets.filter { $0.safety != .reportOnly }.reduce(0) { $0 + $1.sizeBytes }
    }
}

extension PurgeCategory {
    /// Groups a flat list of measured targets into one `PurgeCategory` per
    /// `PurgeCategoryID` that has at least one match, each sorted largest
    /// first. Shared by `PurgeScanner` (to build the final `.loaded` state)
    /// and `DeveloperKitView` (to group the partial results shown mid-scan)
    /// - both need the exact same grouping, so it lives here once rather
    /// than as two copies drifting apart.
    public static func grouped(_ targets: [PurgeTarget]) -> [PurgeCategory] {
        PurgeCategoryID.allCases.compactMap { categoryID in
            let categoryTargets = targets.filter { $0.definition.categoryID == categoryID }
            guard !categoryTargets.isEmpty else { return nil }
            return PurgeCategory(categoryID: categoryID, targets: categoryTargets.sorted { $0.sizeBytes > $1.sizeBytes })
        }
    }
}
