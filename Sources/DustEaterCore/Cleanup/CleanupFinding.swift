import Foundation

/// One of the six ranked findings the Cleanup screen shows after a scan.
/// Order here has no meaning - `CleanupFindingsBuilder.rank(_:)` sorts the
/// built findings by `reclaimableBytes` descending, per the design handoff.
public enum CleanupFindingID: String, Sendable, CaseIterable, Identifiable {
    case packageManagerCaches
    case unusedApplications
    case oldDownloads
    case xcodeBuildArtifacts
    case duplicateFiles
    case simulatorRuntimes

    public var id: String { rawValue }

    /// Fixed copy from `docs/design_handoff_cleanup_restructure/README.md`'s
    /// findings table. Final, not editorial placeholder text - use verbatim.
    public var displayName: String {
        switch self {
        case .packageManagerCaches: return "Package manager caches"
        case .unusedApplications: return "Applications unopened in over a year"
        case .oldDownloads: return "Downloads older than 12 months"
        case .xcodeBuildArtifacts: return "Xcode build artifacts"
        case .duplicateFiles: return "Duplicate files"
        case .simulatorRuntimes: return "iOS Simulator runtimes"
        }
    }

    /// The group-level safety pill shown once per finding header - not
    /// per-row. A finding can contain items of varying individual
    /// `PurgeSafetyLevel` (e.g. package caches includes a couple of
    /// `.caution` entries), but the group itself always carries the fixed
    /// label the design table assigns it.
    public var safety: PurgeSafetyLevel {
        switch self {
        case .packageManagerCaches: return .rebuildable
        case .unusedApplications: return .caution
        case .oldDownloads: return .safe
        case .xcodeBuildArtifacts: return .rebuildable
        case .duplicateFiles: return .safe
        case .simulatorRuntimes: return .reportOnly
        }
    }

    public var reason: String {
        switch self {
        case .packageManagerCaches:
            return "Downloaded dependencies. Each one is fetched again the next time you install or build."
        case .unusedApplications:
            return "The app bundle plus its caches, preferences and application support files. Uninstalling removes all of them."
        case .oldDownloads:
            return "Installers and archives in your Downloads folder. Nothing here is used by an installed app."
        case .xcodeBuildArtifacts:
            return "Xcode regenerates these the next time you build. Nothing in your projects is touched."
        case .duplicateFiles:
            return "Identical file contents in more than one place. The newest copy of every file is always kept."
        case .simulatorRuntimes:
            return "Found, but DustEater will not delete these - removing them by hand breaks the simulators Xcode has installed."
        }
    }

    /// Optional caveat line shown in the group's footer, alongside
    /// `footerAction` where present.
    public var footer: String? {
        switch self {
        case .packageManagerCaches:
            return "Rust toolchains and Android emulator images are marked Caution: removing them means a full re-download, not a rebuild."
        case .unusedApplications:
            return "Last-opened dates come from macOS and can be wrong for apps launched by other software."
        case .duplicateFiles:
            return "Selecting a set marks every copy except the newest. The kept copy is shown with a lock."
        case .simulatorRuntimes:
            return "Remove runtimes in Xcode -> Settings -> Platforms, then rescan."
        case .oldDownloads, .xcodeBuildArtifacts:
            return nil
        }
    }

    /// A footer action link's label, e.g. "Open App Manager". `nil` when the
    /// finding has no deeper screen to link out to.
    public var footerAction: String? {
        switch self {
        case .unusedApplications: return "Open App Manager"
        case .xcodeBuildArtifacts: return "Browse Xcode Archives"
        default: return nil
        }
    }
}

/// One selectable (or, for `.reportOnly`, informational-only) row within a
/// `CleanupFinding`. Flattens whatever underlying type produced it - a
/// `PurgeTarget`, an `AppDiskEntity`, a `DuplicateSet`, or a large/old file -
/// into one shape the Cleanup, Review, and Receipt screens can all render
/// without knowing which finding it came from.
public struct CleanupItem: Sendable, Identifiable, Equatable {
    public let id: String
    public let findingID: CleanupFindingID
    public let name: String
    /// Secondary line shown under the name - a path, or for duplicates
    /// "~/Documents - 1 older copy of 2".
    public let detail: String
    public let sizeBytes: Int64
    public let safety: PurgeSafetyLevel
    /// "Mar 2025", "Never opened", "2 copies" - whatever age/count note this
    /// finding's row wants next to its size. `nil` when there is none.
    public let note: String?
    public let rebuildCommand: String?
    /// Non-nil iff `safety == .reportOnly` - the remedy shown instead of a
    /// delete action.
    public let hint: String?
    /// Every path removed if this item is committed. Empty iff `.reportOnly`.
    /// More than one path for an app (bundle + related storage) or a
    /// duplicate set (every copy except the newest, already resolved at
    /// construction time).
    public let deletablePaths: [String]
    /// Set only for the applications finding - routes deletion through
    /// `FileOperations.deleteAppBundle` instead of a plain path delete, and
    /// is itself also a member of `deletablePaths`.
    public let appBundlePath: String?
    /// Reveal in Finder / Quick Look target. Always non-empty, including for
    /// `.reportOnly` items - reporting something the user can't delete still
    /// means they should be able to go look at it.
    public let revealPath: String
    public let blockingAppBundleID: String?
    /// Always `false` for the six findings in this batch. Explore (item 6,
    /// out of scope here) is what sets this - see Review's destination rule.
    public let isUserContent: Bool

    public init(
        id: String,
        findingID: CleanupFindingID,
        name: String,
        detail: String,
        sizeBytes: Int64,
        safety: PurgeSafetyLevel,
        note: String? = nil,
        rebuildCommand: String? = nil,
        hint: String? = nil,
        deletablePaths: [String],
        appBundlePath: String? = nil,
        revealPath: String,
        blockingAppBundleID: String? = nil,
        isUserContent: Bool = false
    ) {
        self.id = id
        self.findingID = findingID
        self.name = name
        self.detail = detail
        self.sizeBytes = sizeBytes
        self.safety = safety
        self.note = note
        self.rebuildCommand = rebuildCommand
        self.hint = hint
        self.deletablePaths = deletablePaths
        self.appBundlePath = appBundlePath
        self.revealPath = revealPath
        self.blockingAppBundleID = blockingAppBundleID
        self.isUserContent = isUserContent
    }

    public var isReportOnly: Bool { safety == .reportOnly }
}

/// One ranked group on the Cleanup screen - fixed editorial copy from
/// `CleanupFindingID` plus the items actually found on this Mac.
public struct CleanupFinding: Sendable, Identifiable, Equatable {
    public let id: CleanupFindingID
    /// Largest first.
    public let items: [CleanupItem]

    public init(id: CleanupFindingID, items: [CleanupItem]) {
        self.id = id
        self.items = items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Excludes `.reportOnly` items - a finding's header total must never
    /// promise space the user can't actually reclaim from this screen.
    public var reclaimableBytes: Int64 {
        actionableItems.reduce(0) { $0 + $1.sizeBytes }
    }

    public var actionableItems: [CleanupItem] {
        items.filter { !$0.isReportOnly }
    }
}
