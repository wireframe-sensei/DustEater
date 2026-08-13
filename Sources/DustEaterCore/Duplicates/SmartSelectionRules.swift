import Foundation

/// The automated rules exposed by "Smart Select" for bulk duplicate
/// cleanup, eliminating the need to check files one by one.
public enum SmartSelectionRule: String, Sendable, CaseIterable, Identifiable {
    case allExceptNewest
    case allExceptOldest
    case allInDownloads

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .allExceptNewest: return "Select All Except Newest"
        case .allExceptOldest: return "Select All Except Oldest"
        case .allInDownloads: return "Select All in Downloads"
        }
    }
}

/// Applies a `SmartSelectionRule` to a batch of duplicate sets, producing
/// the paths that rule would mark for deletion.
///
/// The one invariant every rule upholds, for every set it touches: at least
/// one file is always left unselected. A `DuplicateSet` is, by construction
/// (`DuplicateDetector`), never fewer than two byte-identical files, so
/// "keep one, select the rest" is always well-defined - there is no rule
/// here, and there should never be one added later, that can select every
/// copy of a file and leave nothing behind.
public enum SmartSelector {
    /// Computes the full selection for `rule` across all of `sets`. This
    /// *replaces* whatever selection the caller currently has - it is not
    /// meant to be unioned with a prior selection, since e.g. applying
    /// `allExceptOldest` after `allExceptNewest` should produce the
    /// oldest-kept result, not the union of both.
    ///
    /// `downloadsPaths` is injected rather than derived from
    /// `NSHomeDirectory()` internally, both so this stays testable without
    /// a real filesystem and so a full-disk scan (which can see other
    /// accounts' home directories) can pass every account's Downloads
    /// folder, not just the current user's.
    public static func apply(
        _ rule: SmartSelectionRule,
        to sets: [DuplicateSet],
        downloadsPaths: [String]
    ) -> Set<String> {
        var selected: Set<String> = []
        for set in sets {
            selected.formUnion(selectedPaths(for: rule, in: set, downloadsPaths: downloadsPaths))
        }
        return selected
    }

    private static func selectedPaths(
        for rule: SmartSelectionRule,
        in set: DuplicateSet,
        downloadsPaths: [String]
    ) -> Set<String> {
        // A DuplicateSet is never smaller than 2 by construction, but this
        // guard keeps the function correct on its own terms rather than
        // relying on that invariant holding elsewhere.
        guard set.files.count > 1 else { return [] }

        switch rule {
        case .allExceptNewest:
            return allPaths(in: set).subtracting([newest(in: set.files).path])

        case .allExceptOldest:
            return allPaths(in: set).subtracting([oldest(in: set.files).path])

        case .allInDownloads:
            let inDownloads = set.files.filter { isUnderAnyDownloadsFolder($0.path, downloadsPaths: downloadsPaths) }
            guard !inDownloads.isEmpty else { return [] }

            if inDownloads.count == set.files.count {
                // Every copy lives in Downloads - keep the newest instead
                // of selecting all of them, so this set is never left with
                // zero survivors.
                return allPaths(in: set).subtracting([newest(in: set.files).path])
            }

            return Set(inDownloads.map(\.path))
        }
    }

    private static func allPaths(in set: DuplicateSet) -> Set<String> {
        Set(set.files.map(\.path))
    }

    private static func newest(in files: [InspectedFile]) -> InspectedFile {
        files.sorted(by: newestFirstOrdering).first!
    }

    private static func oldest(in files: [InspectedFile]) -> InspectedFile {
        files.sorted(by: newestFirstOrdering).last!
    }

    /// Newer first; ties on `modifiedAt` broken by path, so the result
    /// never depends on whatever order the caller's array happens to be
    /// in - two calls with the same set, in any order, always agree on
    /// which file is "the" newest.
    private static func newestFirstOrdering(_ lhs: InspectedFile, _ rhs: InspectedFile) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return lhs.path < rhs.path
    }

    /// Component-boundary containment check, not a bare `hasPrefix`:
    /// `/Users/x/Downloads2/a.bin` must not match a Downloads folder at
    /// `/Users/x/Downloads`. `FileOperations.isSystemProtected` already
    /// relies on the same boundary-safe shape for its own path checks.
    private static func isUnderAnyDownloadsFolder(_ path: String, downloadsPaths: [String]) -> Bool {
        downloadsPaths.contains { downloadsPath in
            path == downloadsPath || path.hasPrefix(downloadsPath + "/")
        }
    }
}
