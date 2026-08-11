import Foundation

enum VendorFolderExpander {
    struct Entry {
        let matchName: String
        let path: String
        let isVendorSibling: Bool
    }

    static func vendorName(fromBundleIdentifier bundleIdentifier: String) -> String? {
        let parts = bundleIdentifier.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return parts[1].lowercased()
    }

    static func listEntries(in directoryPath: String, vendorNames: Set<String>, knownNames: Set<String>) -> [Entry] {
        let fileManager = FileManager.default
        guard let topLevel = try? fileManager.contentsOfDirectory(atPath: directoryPath) else { return [] }

        var entries: [Entry] = []
        for name in topLevel {
            let path = (directoryPath as NSString).appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
                  !knownNames.contains(name.lowercased()),
                  vendorNames.contains(name.lowercased()),
                  let children = try? fileManager.contentsOfDirectory(atPath: path), !children.isEmpty
            else {
                entries.append(Entry(matchName: name, path: path, isVendorSibling: false))
                continue
            }
            for childName in children {
                entries.append(Entry(matchName: childName, path: (path as NSString).appendingPathComponent(childName), isVendorSibling: true))
            }
        }
        return entries
    }
}
