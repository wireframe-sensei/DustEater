import Foundation

/// Finds `.app` bundles in a scanned tree and computes each one's "true"
/// disk footprint by cross-referencing its bundle identifier against the
/// `~/Library` directories macOS uses for hidden per-app storage.
public enum AppGrouper {
    /// Depth-first search for directory nodes that look like app bundles.
    /// Does not descend into a found `.app` looking for nested ones (e.g. a
    /// helper app under `Contents/XPCServices`), since those are part of
    /// the parent app's own footprint, not independent installs.
    public static func findAppBundles(in node: FileNode) -> [FileNode] {
        guard node.isDirectory else { return [] }

        if node.name.hasSuffix(".app") {
            return [node]
        }

        return node.children.flatMap { findAppBundles(in: $0) }
    }

    /// Builds an `AppDiskEntity` for every app bundle found, scanning each
    /// candidate related-storage path concurrently.
    public static func buildAppDiskEntities(
        from appNodes: [FileNode],
        homeDirectory: String = NSHomeDirectory()
    ) async -> [AppDiskEntity] {
        await withTaskGroup(of: AppDiskEntity.self) { group in
            for appNode in appNodes {
                group.addTask {
                    await buildEntity(for: appNode, homeDirectory: homeDirectory)
                }
            }
            var results: [AppDiskEntity] = []
            results.reserveCapacity(appNodes.count)
            for await entity in group {
                results.append(entity)
            }
            return results
        }
    }

    private struct Candidate {
        let path: String
        let category: RelatedStorageCategory
    }

    private static func candidatePaths(bundleIdentifier: String?, displayName: String, home: String) -> [Candidate] {
        var candidates: [Candidate] = []
        if let bundleIdentifier {
            candidates.append(Candidate(path: "\(home)/Library/Containers/\(bundleIdentifier)", category: .containers))
            candidates.append(Candidate(path: "\(home)/Library/Caches/\(bundleIdentifier)", category: .caches))
            candidates.append(Candidate(
                path: "\(home)/Library/Application Support/\(bundleIdentifier)",
                category: .applicationSupport
            ))
            candidates.append(Candidate(
                path: "\(home)/Library/Saved Application State/\(bundleIdentifier).savedState",
                category: .savedState
            ))
            candidates.append(Candidate(
                path: "\(home)/Library/Preferences/\(bundleIdentifier).plist",
                category: .preferences
            ))
        }
        // Application Support conventionally keys off bundle ID, but a
        // number of (mostly older) apps use their display name instead.
        candidates.append(Candidate(
            path: "\(home)/Library/Application Support/\(displayName)",
            category: .applicationSupport
        ))
        return candidates
    }

    private static func buildEntity(for appNode: FileNode, homeDirectory: String) async -> AppDiskEntity {
        let info = await AppBundleInspector.inspect(appPath: appNode.path)
        let candidates = candidatePaths(
            bundleIdentifier: info.bundleIdentifier,
            displayName: info.displayName,
            home: homeDirectory
        )

        let relatedItems: [RelatedStorageItem] = await withTaskGroup(of: RelatedStorageItem?.self) { group in
            for candidate in candidates {
                group.addTask {
                    guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
                    let size = await sizeOnDisk(atPath: candidate.path)
                    guard size > 0 else { return nil }
                    return RelatedStorageItem(category: candidate.category, path: candidate.path, size: size)
                }
            }
            var items: [RelatedStorageItem] = []
            for await item in group where item != nil {
                items.append(item!)
            }
            return items
        }

        return AppDiskEntity(
            displayName: info.displayName,
            bundleIdentifier: info.bundleIdentifier,
            appPath: appNode.path,
            appBundleSize: appNode.size,
            relatedItems: relatedItems
        )
    }

    /// A single preferences `.plist` is a file, not a directory `DiskScanner`
    /// can recurse into, so allocated size is read directly for those.
    private static func sizeOnDisk(atPath path: String) async -> Int64 {
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
