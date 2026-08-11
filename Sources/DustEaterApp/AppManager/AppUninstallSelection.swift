import Foundation
import DustEaterCore

struct AppUninstallSelection {
    var includeAppBundle: Bool
    var includedItemPaths: Set<String>

    enum SelectAllState {
        case all
        case none
        case mixed
    }

    init(entity: AppDiskEntity) {
        self.includeAppBundle = true
        self.includedItemPaths = Set(entity.relatedItems.map(\.path))
    }

    init(orphan: OrphanedAppData) {
        self.includeAppBundle = false
        self.includedItemPaths = Set(orphan.items.map(\.path))
    }

    init(resetting source: AppRowItem.AppRowItemSource) {
        switch source {
        case .installed(let entity):
            self = AppUninstallSelection(entity: entity)
        case .orphaned(let orphan):
            self = AppUninstallSelection(orphan: orphan)
        case .developerTool(let tool):
            self = AppUninstallSelection(orphan: tool)
        }
    }

    func selectAllState(totalRelatedCount: Int, includesBundle: Bool) -> SelectAllState {
        let totalSelectable = totalRelatedCount + (includesBundle ? 1 : 0)
        let totalSelected = includedItemPaths.count + (includeAppBundle && includesBundle ? 1 : 0)

        if totalSelected == 0 {
            return .none
        } else if totalSelected == totalSelectable {
            return .all
        } else {
            return .mixed
        }
    }
}
