import SwiftUI
import AppKit
import DustEaterCore

// MARK: - NSOutlineView Data Source
class FileTreeDataSource: NSObject, NSOutlineViewDataSource {
    var root: FileNode
    var expandedPaths: Set<String> = []

    init(root: FileNode) {
        self.root = root
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let node = item as? FileNode ?? root
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let node = item as? FileNode ?? root
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? FileNode else { return false }
        return node.isDirectory && !node.children.isEmpty
    }
}

// MARK: - NSOutlineView Delegate
class FileTreeDelegate: NSObject, NSOutlineViewDelegate {
    var onSelectNode: (FileNode) -> Void = { _ in }
    var expandedPaths: Set<String> = []
    weak var outlineView: NSOutlineView?

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }

        let cell = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("FileCell"), owner: self) as? FileTreeCell
            ?? FileTreeCell()

        cell.node = node
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView,
              let selectedItem = outlineView.item(atRow: outlineView.selectedRow) as? FileNode else {
            return
        }
        onSelectNode(selectedItem)
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return true
    }
}

// MARK: - Custom Cell View
class FileTreeCell: NSTableCellView {
    var node: FileNode? {
        didSet {
            updateCell()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCell()
    }

    private func setupCell() {
        // Use NSTableCellView's built-in textField
        let textField = NSTextField()
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isEditable = false
        textField.font = .systemFont(ofSize: 13)
        textField.lineBreakMode = .byTruncatingTail
        self.textField = textField

        // Add size field on the right
        let sizeField = NSTextField()
        sizeField.isBezeled = false
        sizeField.drawsBackground = false
        sizeField.isEditable = false
        sizeField.font = .systemFont(ofSize: 11)
        sizeField.textColor = .secondaryLabelColor
        sizeField.alignment = .right
        addSubview(sizeField)
        self.sizeField = sizeField
    }

    override func layout() {
        super.layout()

        // Position size field on the right
        if let sizeField = sizeField {
            let width = bounds.width
            let height = bounds.height
            sizeField.frame = NSRect(x: width - 80, y: 0, width: 76, height: height)
        }

        // Position text field to the right of icon
        if let textField = textField {
            let height = bounds.height
            textField.frame = NSRect(x: 24, y: 0, width: bounds.width - 110, height: height)
        }
    }

    private weak var sizeField: NSTextField?

    private func updateCell() {
        guard let node = node else { return }

        textField?.stringValue = node.name
        imageView?.image = NSImage(systemSymbolName: node.isDirectory ? "folder.fill" : "doc.fill", accessibilityDescription: nil)
        sizeField?.stringValue = ByteFormatter.string(fromBytes: node.size)
    }
}

// MARK: - SwiftUI Wrapper
struct FileTreeOutlineView: NSViewRepresentable {
    let root: FileNode
    @Binding var selectedPath: String?
    let onSelectNode: (FileNode) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView = NSOutlineView()
        outlineView.delegate = context.coordinator.delegate
        outlineView.dataSource = context.coordinator.dataSource

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileColumn"))
        column.width = 300
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.headerView = nil
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.selectionHighlightStyle = .regular

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.automaticallyAdjustsContentInsets = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let outlineView = nsView.documentView as? NSOutlineView else { return }

        context.coordinator.delegate.onSelectNode = onSelectNode
        context.coordinator.delegate.outlineView = outlineView

        // Update data source if root changed
        context.coordinator.dataSource.root = root
        outlineView.reloadData()

        // Update selection
        if let selectedPath = selectedPath, let node = root.find(path: selectedPath) {
            let row = outlineView.row(forItem: node)
            if row >= 0 {
                outlineView.selectRowIndexes([row], byExtendingSelection: false)

                // Expand all parents
                var currentNode = node.parent(in: root)
                while let parent = currentNode {
                    outlineView.expandItem(parent)
                    currentNode = parent.parent(in: root)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(root: root)
    }

    class Coordinator {
        let dataSource: FileTreeDataSource
        let delegate: FileTreeDelegate

        init(root: FileNode) {
            self.dataSource = FileTreeDataSource(root: root)
            self.delegate = FileTreeDelegate()
        }
    }
}

// MARK: - FileNode Extension
private extension FileNode {
    func find(path: String) -> FileNode? {
        if self.path == path { return self }
        for child in children {
            if let found = child.find(path: path) {
                return found
            }
        }
        return nil
    }

    func parent(in root: FileNode) -> FileNode? {
        if self.path == root.path { return nil }

        func findParent(_ node: FileNode) -> FileNode? {
            for child in node.children {
                if child.path == self.path { return node }
                if let found = findParent(child) { return found }
            }
            return nil
        }

        return findParent(root)
    }
}
