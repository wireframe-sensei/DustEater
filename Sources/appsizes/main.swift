import DustEaterCore
import Foundation

func formatBytes(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unitIndex = 0
    while value >= 1024 && unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }
    return String(format: "%.2f %@", value, units[unitIndex])
}

let arguments = CommandLine.arguments
let appsDirectory = arguments.count > 1 ? (arguments[1] as NSString).expandingTildeInPath : "/Applications"

print("Scanning \(appsDirectory) for app bundles and their hidden storage...")
print(String(repeating: "-", count: 70))

let scanner = DiskScanner()
let root = await scanner.scan(rootPath: appsDirectory)

let appNodes = AppGrouper.findAppBundles(in: root)
print("Found \(appNodes.count) app bundle(s). Cross-referencing ~/Library...\n")

let entities = await AppGrouper.buildAppDiskEntities(from: appNodes)
let sorted = entities.sorted { $0.trueTotalSize > $1.trueTotalSize }

let nameWidth = 32
for entity in sorted.prefix(25) {
    let paddedName = entity.displayName.count > nameWidth
        ? String(entity.displayName.prefix(nameWidth - 1)) + "…"
        : entity.displayName.padding(toLength: nameWidth, withPad: " ", startingAt: 0)

    let bundleOnly = formatBytes(entity.appBundleSize).padding(toLength: 12, withPad: " ", startingAt: 0)
    let trueSize = formatBytes(entity.trueTotalSize).padding(toLength: 12, withPad: " ", startingAt: 0)

    print("\(paddedName) bundle: \(bundleOnly) true: \(trueSize)")

    if !entity.relatedItems.isEmpty {
        for item in entity.relatedItems.sorted(by: { $0.size > $1.size }) {
            print("    + \(item.category.rawValue): \(formatBytes(item.size))  (\(item.path))")
        }
    }
}

print()
print(String(repeating: "-", count: 70))

// Demonstrate the merge: the tree's own accounting should now reflect true sizes.
let merged = AppSizeMerger.mergeTrueSizes(into: root, using: entities)
let mergedTotal = merged.children.reduce(into: Int64(0)) { $0 += $1.size }
let rawTotal = root.children.reduce(into: Int64(0)) { $0 += $1.size }
print("Raw scanned total:   \(formatBytes(rawTotal))")
print("True size total:     \(formatBytes(mergedTotal))")
print("Hidden data found:   \(formatBytes(mergedTotal - rawTotal))")
