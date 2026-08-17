import AppKit
import Observation
import DustEaterCore

/// App-wide selection spanning every `CleanupItem` on screen - Cleanup's
/// finding groups today, Explore's type browser once item 6 lands. One
/// selection set, one tray, one Review screen: selecting from a second
/// source must never create a second, parallel delete path.
///
/// Owned by the shell (`ContentView`), not by `CleanupView`, so it survives
/// the Cleanup -> Review -> Receipt stage change intact.
///
/// Stores full `CleanupItem` values, not a bare `Set<String>` of ids: Review
/// and the tray need each selected item's size/safety/finding without
/// re-resolving ids against whatever findings array happens to be current,
/// which matters once a mid-flight rescan or a partial commit can change
/// that array out from under a stale id set.
@Observable
@MainActor
final class SelectionStore {
    private(set) var entries: [String: CleanupItem] = [:]

    /// Starts empty and is never seeded - no caller sets an initial
    /// selection. There is no "select all" affordance outside a group's own
    /// checkbox.
    init() {}

    var count: Int { entries.count }

    var totalBytes: Int64 {
        entries.values.reduce(0) { $0 + $1.sizeBytes }
    }

    var containsCaution: Bool {
        entries.values.contains { $0.safety == .caution }
    }

    var containsUserContent: Bool {
        entries.values.contains { $0.isUserContent }
    }

    var items: [CleanupItem] {
        Array(entries.values)
    }

    func contains(_ id: String) -> Bool {
        entries[id] != nil
    }

    /// Refuses `.reportOnly` items, same guard `PurgeSelection.toggle` and
    /// `DuplicateSelectionState.toggle` both already enforce - there is no
    /// delete action for a report-only item anywhere in the app, so it must
    /// never be representable as "selected."
    func toggle(_ item: CleanupItem) {
        guard !item.isReportOnly else { return }
        if entries[item.id] != nil {
            entries.removeValue(forKey: item.id)
        } else {
            entries[item.id] = item
        }
    }

    func setAll(in finding: CleanupFinding, selected: Bool) {
        for item in finding.actionableItems {
            if selected {
                entries[item.id] = item
            } else {
                entries.removeValue(forKey: item.id)
            }
        }
    }

    func remove(id: String) {
        entries.removeValue(forKey: id)
    }

    func clear() {
        entries.removeAll()
    }

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

    func selectAllState(for finding: CleanupFinding) -> SelectAllState {
        let actionable = finding.actionableItems
        guard !actionable.isEmpty else { return .none }
        let selectedCount = actionable.filter { contains($0.id) }.count
        if selectedCount == 0 { return .none }
        if selectedCount == actionable.count { return .all }
        return .mixed
    }
}
