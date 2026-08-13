import Foundation
import DustEaterCore

/// Tracks which purge targets are currently marked for deletion across every
/// category on screen. Mirrors the shape of `DuplicateSelectionState` and
/// App Manager's `AppUninstallSelection`: a thin wrapper around `Set<String>`
/// plus the queries the UI needs.
struct PurgeSelection {
    private(set) var selectedPaths: Set<String> = []

    func isSelected(_ target: PurgeTarget) -> Bool {
        selectedPaths.contains(target.path)
    }

    /// Refuses `.reportOnly` targets outright. Deleting Docker's disk image
    /// corrupts its VM, and a mounted simulator runtime can't be removed at
    /// all - "no delete action exists for these" is enforced here, once,
    /// rather than left to every call site remembering not to render a
    /// toggle in the first place.
    mutating func toggle(_ target: PurgeTarget) {
        guard target.safety != .reportOnly else { return }
        if selectedPaths.contains(target.path) {
            selectedPaths.remove(target.path)
        } else {
            selectedPaths.insert(target.path)
        }
    }

    /// Bulk selection never picks up `.caution` targets - those are
    /// reachable only by an individual, deliberate toggle, one card at a
    /// time, with the badge visible. Same reasoning as
    /// `DuplicateSelectionState.selectAllIncludingOriginal` being a
    /// separate, explicitly-labeled action rather than a variant of
    /// `selectAll`: there is no "Select All" here, on purpose.
    mutating func selectAll(upTo level: PurgeSafetyLevel, in categories: [PurgeCategory]) {
        let allowedLevels: Set<PurgeSafetyLevel> = level == .safe ? [.safe] : [.safe, .rebuildable]
        for category in categories {
            for target in category.targets where allowedLevels.contains(target.safety) {
                selectedPaths.insert(target.path)
            }
        }
    }

    mutating func deselectAll() {
        selectedPaths.removeAll()
    }

    mutating func removePaths(_ paths: Set<String>) {
        selectedPaths.subtract(paths)
    }

    func reclaimableBytes(across categories: [PurgeCategory]) -> Int64 {
        var total: Int64 = 0
        for category in categories {
            for target in category.targets where isSelected(target) {
                total += target.sizeBytes
            }
        }
        return total
    }

    var count: Int { selectedPaths.count }
}
