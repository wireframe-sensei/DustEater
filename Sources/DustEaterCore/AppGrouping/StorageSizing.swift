import Foundation

enum StorageSizing {
    static func sizeOnDisk(atPath path: String) async -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }

        if !isDirectory.boolValue {
            return (try? await BlockingIO.run {
                let attributes = try FileManager.default.attributesOfItem(atPath: path)
                return (attributes[.size] as? NSNumber)?.int64Value ?? 0
            }) ?? 0
        }

        let scanner = DiskScanner()
        return await scanner.scan(rootPath: path).size
    }
}
