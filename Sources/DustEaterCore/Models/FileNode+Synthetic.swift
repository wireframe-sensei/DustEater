import Foundation

public extension FileNode {
    /// True for the synthetic "Associated App Data" node `AppSizeMerger`
    /// injects - never a real path, must not be passed to `FileOperations`,
    /// `NSWorkspace`, or the pasteboard. Category children are unaffected.
    var isSyntheticGroupingNode: Bool {
        path.contains("/\u{0}")
    }
}
