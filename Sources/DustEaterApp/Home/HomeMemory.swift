import Foundation

/// One completed scan's remembered facts about a path - either a volume
/// root (read by the estimate row) or a folder (read by the recent-folder
/// pills). One record shape serves both; which list a path shows up in is
/// decided at read time by whether the path matches a currently mounted
/// volume root, not by anything stored here.
struct RecordedScan: Codable {
    let itemCount: Int
    let sizeBytes: Int64
    let scannedAt: Date
}

/// Persists what Home needs to remember across launches: how big a scan of
/// a given path turned out to be last time, keyed by path. Same plain
/// UserDefaults-backed pattern as `OnboardingStore`/`ProtectedAppsStore`,
/// just JSON-encoded since the value isn't a single primitive.
enum HomeMemory {
    private static let key = "DustEater.HomeMemory.RecordedScans"
    /// Caps unbounded growth from a machine with years of varied scan
    /// targets - Home only ever shows a handful of recent folders anyway,
    /// so nothing needs more history than this.
    private static let maxEntries = 20

    static func record(path: String, itemCount: Int, sizeBytes: Int64) {
        var all = allScans()
        all[path] = RecordedScan(itemCount: itemCount, sizeBytes: sizeBytes, scannedAt: Date())
        if all.count > maxEntries {
            let newest = all.sorted { $0.value.scannedAt > $1.value.scannedAt }.prefix(maxEntries)
            all = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        save(all)
    }

    static func scan(atPath path: String) -> RecordedScan? {
        allScans()[path]
    }

    /// Most-recently-scanned folders, excluding whatever matches a
    /// currently mounted volume root - those are what the volume cards'
    /// own estimate row reads instead, via `scan(atPath:)`. A path that
    /// used to be a mounted volume (an external drive since unplugged, for
    /// instance) is still eligible here, since it no longer appears in
    /// `volumePaths`.
    static func recentFolders(excluding volumePaths: Set<String>, limit: Int) -> [(path: String, scan: RecordedScan)] {
        allScans()
            .filter { !volumePaths.contains($0.key) }
            .sorted { $0.value.scannedAt > $1.value.scannedAt }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }

    private static func allScans() -> [String: RecordedScan] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: RecordedScan].self, from: data) else { return [:] }
        return decoded
    }

    private static func save(_ scans: [String: RecordedScan]) {
        guard let data = try? JSONEncoder().encode(scans) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
