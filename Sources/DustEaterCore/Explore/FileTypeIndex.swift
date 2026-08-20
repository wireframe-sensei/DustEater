import Foundation

/// One file (or, for `.applications`, one whole `.app` bundle) recorded
/// against a `FileTypeCategory` during the main scan. Deliberately thin -
/// just what `DiskScanner` already knows for free (path, name, allocated
/// size) plus a cheap path-shape check for Photos-library membership.
/// Everything that needs real I/O to determine (logical size, last-opened
/// date, iCloud status) is fetched on demand, later, only for the bounded
/// set of entries a user actually opens a type to browse - see
/// `FileTypeBrowser`.
public struct FileTypeIndexEntry: Sendable, Equatable {
    public let path: String
    public let name: String
    public let sizeBytes: Int64
    /// True if `path` sits inside a `.photoslibrary` package - Photos
    /// manages these originals itself; DustEater must never offer to
    /// delete them directly. Computed here (a path-component check, no
    /// I/O) rather than on demand, since it's essentially free during a
    /// scan that already has the full path in hand.
    public let isPhotosManaged: Bool
    /// True for the one entry `DiskScanner` records for a whole recognized
    /// dependency/build directory (`node_modules`, `.next`, `dist`, `build`,
    /// `target`, `.venv`/`venv`, `Pods`, `DerivedData`) - the entry's
    /// `sizeBytes` is the directory's full recursive size, not one file's,
    /// exactly the same shape as the `.applications` bundle entries this
    /// mirrors. `Explore`'s Code & Projects screen uses this flag to split
    /// the category's entries into folder rows versus loose file rows
    /// without re-deriving the name match itself.
    public let isDependencyDirectory: Bool
    /// True for the one entry `DiskScanner` records for a whole
    /// `BundleProtection`-recognized creative-suite library package
    /// (`.fcpbundle`, `.imovielibrary`, `.theater`, `.tvlibrary`,
    /// `.logicx`, `.band`) or app-adjacent bundle (`.framework`,
    /// `.bundle`, `.xpc`, `.plugin`, `.appex`, `.sparsebundle) - the same
    /// "a folder, not its files, is the natural unit" problem
    /// `isDependencyDirectory` solves for dependency trees, applied to
    /// package directories `BundleProtection` already refuses to treat as
    /// individually inspectable elsewhere in the app. Unlike a dependency
    /// directory, this has no rebuild command - Explore shows it as one
    /// locked, report-only row in its category's normal file list rather
    /// than a dedicated folder section, the same lock-instead-of-checkbox
    /// treatment `isPhotosManaged` already gets.
    public let isProtectedBundle: Bool

    public init(
        path: String,
        name: String,
        sizeBytes: Int64,
        isPhotosManaged: Bool,
        isDependencyDirectory: Bool = false,
        isProtectedBundle: Bool = false
    ) {
        self.path = path
        self.name = name
        self.sizeBytes = sizeBytes
        self.isPhotosManaged = isPhotosManaged
        self.isDependencyDirectory = isDependencyDirectory
        self.isProtectedBundle = isProtectedBundle
    }
}

public struct FileTypeTotal: Sendable, Equatable {
    public let totalBytes: Int64
    public let fileCount: Int

    public init(totalBytes: Int64, fileCount: Int) {
        self.totalBytes = totalBytes
        self.fileCount = fileCount
    }
}

/// The finished, immutable result of a scan's type classification - what
/// the Type board and Type detail screens actually read. Built by calling
/// `FileTypeIndexPartial.finalize()` once the scan completes.
public struct FileTypeIndex: Sendable, Equatable {
    /// The cap every `entries` array respects, applied during the scan
    /// itself (not as a later truncation) so memory stays bounded
    /// regardless of how many files a category actually has - a category
    /// like "Code & Projects" can genuinely have well over 100,000 files
    /// on a real disk, and the Type detail list only ever needs the
    /// largest ones (the default sort, and the reason a user opens the
    /// screen at all: "the real user query is videos over 500 MB").
    public static let maxEntriesPerCategory = 2000

    public let totals: [FileTypeCategory: FileTypeTotal]
    /// Largest-first, capped at `maxEntriesPerCategory`.
    public let entries: [FileTypeCategory: [FileTypeIndexEntry]]

    public init(totals: [FileTypeCategory: FileTypeTotal], entries: [FileTypeCategory: [FileTypeIndexEntry]]) {
        self.totals = totals
        self.entries = entries
    }

    public static let empty = FileTypeIndex(totals: [:], entries: [:])

    public func total(for category: FileTypeCategory) -> FileTypeTotal {
        totals[category] ?? FileTypeTotal(totalBytes: 0, fileCount: 0)
    }

    public func entries(for category: FileTypeCategory) -> [FileTypeIndexEntry] {
        entries[category] ?? []
    }

    /// Categories with at least one file, ranked by total size descending -
    /// "eight types, ranked by total size, not alphabetical" per the
    /// design handoff. A category with zero files (a scan of a folder with
    /// no audio in it, say) is simply absent, not shown as an empty tile.
    public var rankedCategories: [FileTypeCategory] {
        FileTypeCategory.allCases
            .filter { (totals[$0]?.fileCount ?? 0) > 0 }
            .sorted { total(for: $0).totalBytes > total(for: $1).totalBytes }
    }
}

/// The mutable accumulator `DiskScanner.scanDirectory` folds results into,
/// bottom-up, exactly the way it already folds `FileNode.size`/`itemCount`
/// - a plain value type combined via `merge`, not a shared, lock-protected
/// object touched from every concurrent directory task. This matches
/// `DiskScanner`'s existing architecture (function results combined
/// functionally, no shared mutable state) rather than adding a second,
/// different concurrency pattern to the same hot path.
public struct FileTypeIndexPartial: Sendable {
    private var totalBytes: [FileTypeCategory: Int64] = [:]
    private var fileCount: [FileTypeCategory: Int] = [:]
    private var entries: [FileTypeCategory: [FileTypeIndexEntry]] = [:]

    public init() {}

    /// Records one file. Trims a category's entry list only once it grows
    /// to double the eventual cap, not on every insert - sorting on every
    /// single file would be real, avoidable overhead on `DiskScanner`'s hot
    /// path, and most directories never come close to the cap at all.
    public mutating func record(_ entry: FileTypeIndexEntry, category: FileTypeCategory) {
        totalBytes[category, default: 0] += entry.sizeBytes
        fileCount[category, default: 0] += 1

        var bucket = entries[category, default: []]
        bucket.append(entry)
        if bucket.count > FileTypeIndex.maxEntriesPerCategory * 2 {
            bucket.sort { $0.sizeBytes > $1.sizeBytes }
            bucket.removeLast(bucket.count - FileTypeIndex.maxEntriesPerCategory)
        }
        entries[category] = bucket
    }

    /// Combines a child directory's partial index into this one - totals
    /// always add exactly (every file is counted once, regardless of the
    /// cap), while each category's entry list is merged and re-capped.
    public mutating func merge(_ other: FileTypeIndexPartial) {
        for (category, bytes) in other.totalBytes {
            totalBytes[category, default: 0] += bytes
        }
        for (category, count) in other.fileCount {
            fileCount[category, default: 0] += count
        }
        for (category, otherBucket) in other.entries {
            var bucket = entries[category, default: []]
            bucket.append(contentsOf: otherBucket)
            if bucket.count > FileTypeIndex.maxEntriesPerCategory {
                bucket.sort { $0.sizeBytes > $1.sizeBytes }
                bucket.removeLast(bucket.count - FileTypeIndex.maxEntriesPerCategory)
            }
            entries[category] = bucket
        }
    }

    public func finalize() -> FileTypeIndex {
        var totals: [FileTypeCategory: FileTypeTotal] = [:]
        for category in FileTypeCategory.allCases {
            let bytes = totalBytes[category] ?? 0
            let count = fileCount[category] ?? 0
            guard count > 0 else { continue }
            totals[category] = FileTypeTotal(totalBytes: bytes, fileCount: count)
        }

        var finalEntries: [FileTypeCategory: [FileTypeIndexEntry]] = [:]
        for (category, bucket) in entries {
            let sorted = bucket.sorted { $0.sizeBytes > $1.sizeBytes }
            finalEntries[category] = Array(sorted.prefix(FileTypeIndex.maxEntriesPerCategory))
        }

        return FileTypeIndex(totals: totals, entries: finalEntries)
    }
}
