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

func formatDuration(_ seconds: Double) -> String {
    String(format: "%.3fs", seconds)
}

let arguments = CommandLine.arguments
let targetPath = arguments.count > 1 ? (arguments[1] as NSString).expandingTildeInPath : NSHomeDirectory()

var isDir: ObjCBool = false
guard FileManager.default.fileExists(atPath: targetPath, isDirectory: &isDir), isDir.boolValue else {
    print("Error: '\(targetPath)' is not a directory.")
    exit(1)
}

print("Benchmarking scan of: \(targetPath)")
print(String(repeating: "-", count: 60))

// --- DustEater: getattrlistbulk + TaskGroup ---
let scanner = DiskScanner()
let fastStart = DispatchTime.now()
let fastNode = await scanner.scan(rootPath: targetPath)
let fastEnd = DispatchTime.now()
let fastDuration = Double(fastEnd.uptimeNanoseconds - fastStart.uptimeNanoseconds) / 1_000_000_000

print("📊 DustEater scanner (getattrlistbulk + TaskGroup)")
print("📊   Time:  \(formatDuration(fastDuration))")
print("📊   Items: \(fastNode.itemCount)")
print("📊   Size:  \(formatBytes(fastNode.size))")
print()
print("📊 Top entries:")
let sorted = fastNode.sortedBySize()
for child in sorted.children.prefix(5) {
    let marker = child.isDirectory ? "📁" : "📄"
    print("📊   \(marker) \(formatBytes(child.size).padding(toLength: 12, withPad: " ", startingAt: 0)) \(child.name)")
}
