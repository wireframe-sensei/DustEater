import SwiftUI
import DustEaterCore

/// Tracks which files are currently marked for deletion across every
/// duplicate set on screen. A thin wrapper around `Set<String>` plus the
/// per-set queries the UI needs (locked survivor, select-all state) -
/// mirroring the shape of App Manager's `AppUninstallSelection`. The actual
/// bulk rules live in `SmartSelector` (`DustEaterCore`), which `apply(_:)`
/// below only consumes; this type owns nothing but which paths are checked.
struct DuplicateSelectionState {
    private(set) var selectedPaths: Set<String> = []

    enum SelectAllState {
        case all, none, mixed

        var nsControlState: NSControl.StateValue {
            switch self {
            case .all: .on
            case .none: .off
            case .mixed: .mixed
            }
        }
    }

    func isSelected(_ path: String) -> Bool {
        selectedPaths.contains(path)
    }

    /// True when `path` is the only unselected file remaining in `set` -
    /// selecting it would leave the set with zero survivors.
    ///
    /// This is advisory, not enforced by `toggle` below: the UI uses it to
    /// warn (a "Last Copy" badge, distinct help text) rather than to
    /// disable the checkbox, so a user who genuinely wants every copy of a
    /// file gone can still select it - deliberately, one click at a time,
    /// rather than via a single bulk action that could wipe out files they
    /// didn't mean to touch. `SmartSelector`'s automated bulk rules (Smart
    /// Select, applied across potentially dozens of sets at once with much
    /// less per-file visibility) keep their hard "always keep one"
    /// guarantee unconditionally - only this manual, per-set, per-file path
    /// can ever select every copy.
    func isLockedSurvivor(_ path: String, in set: DuplicateSet) -> Bool {
        guard !isSelected(path) else { return false }
        let unselectedCount = set.files.filter { !isSelected($0.path) }.count
        return unselectedCount <= 1
    }

    mutating func toggle(_ path: String, in set: DuplicateSet) {
        if isSelected(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
    }

    /// Selects every file in `set` except the newest, matching the same
    /// "always keep a survivor" invariant as the smart-select rules.
    mutating func selectAll(in set: DuplicateSet) {
        guard let survivor = set.files.max(by: { $0.modifiedAt < $1.modifiedAt }) else { return }
        for file in set.files where file.path != survivor.path {
            selectedPaths.insert(file.path)
        }
    }

    /// Selects literally every file in `set`, including whichever one
    /// `selectAll(in:)` would have kept back. A deliberately separate,
    /// explicitly-labeled action from `selectAll(in:)` - not a variant
    /// reached by the same button - since it removes every copy of the
    /// file rather than reclaiming duplicate storage.
    mutating func selectAllIncludingOriginal(in set: DuplicateSet) {
        for file in set.files {
            selectedPaths.insert(file.path)
        }
    }

    mutating func deselectAll(in set: DuplicateSet) {
        for file in set.files {
            selectedPaths.remove(file.path)
        }
    }

    /// `.all` here means "every file but the mandatory survivor is
    /// selected" - a `DuplicateSet` can never have every file selected, so
    /// treating `count - 1` as the ceiling is what makes the per-set
    /// select-all checkbox ever actually show as fully checked.
    func selectAllState(for set: DuplicateSet) -> SelectAllState {
        let selectedCount = set.files.filter { isSelected($0.path) }.count
        if selectedCount == 0 { return .none }
        if selectedCount >= set.files.count - 1 { return .all }
        return .mixed
    }

    /// Replaces the current selection with what `rule` would select -
    /// see `SmartSelector.apply` for why this replaces rather than unions.
    mutating func apply(_ rule: SmartSelectionRule, to sets: [DuplicateSet], downloadsPaths: [String]) {
        selectedPaths = SmartSelector.apply(rule, to: sets, downloadsPaths: downloadsPaths)
    }

    mutating func clear() {
        selectedPaths.removeAll()
    }

    mutating func removePaths(_ paths: Set<String>) {
        selectedPaths.subtract(paths)
    }

    func reclaimableBytes(across sets: [DuplicateSet]) -> Int64 {
        var total: Int64 = 0
        for set in sets {
            for file in set.files where isSelected(file.path) {
                total += file.logicalSize
            }
        }
        return total
    }

    var count: Int { selectedPaths.count }
}
