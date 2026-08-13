import Foundation

/// Pure grouping/partitioning logic for duplicate detection, kept free of
/// any I/O so it can be unit tested without touching the filesystem. The
/// actual hashing (which does read files) lives in `FileHasher`; this type
/// only ever sees hashes that have already been computed and handed to it.
enum DuplicatePartitioner {
    /// Groups files by exact logical size, applying the size floor and
    /// dropping any group that ends up with fewer than two files - a
    /// unique size can never have a duplicate.
    static func groupBySize(_ files: [InspectedFile], minimumSize: Int64) -> [[InspectedFile]] {
        let eligible = files.filter { $0.logicalSize >= minimumSize && $0.logicalSize > 0 }
        return Dictionary(grouping: eligible, by: \.logicalSize)
            .values
            .filter { $0.count > 1 }
            .map { $0 }
    }

    /// Collapses hard-link aliases within a group down to one representative
    /// per unique (device, inode) pair. Aliases point at the same on-disk
    /// bytes, so counting each as an independent copy would overstate
    /// reclaimable space.
    static func collapsingHardLinks(_ files: [InspectedFile]) -> [InspectedFile] {
        var seen = Set<HardLinkKey>()
        var result: [InspectedFile] = []
        result.reserveCapacity(files.count)
        for file in files {
            let key = HardLinkKey(deviceID: file.deviceID, inode: file.inode)
            if seen.insert(key).inserted {
                result.append(file)
            }
        }
        return result
    }

    private struct HardLinkKey: Hashable {
        let deviceID: UInt64
        let inode: UInt64
    }

    /// Partitions `files` by whatever digest `hash` returns for each one,
    /// dropping files `hash` couldn't produce a digest for (a read failure)
    /// and any resulting group of fewer than two members. Used identically
    /// for both the quick 4KB pass and the full SHA-256 pass - the only
    /// difference between them is which hash function the caller supplies.
    ///
    /// `files` is expected to already share whatever property the caller
    /// grouped on before calling this (e.g. logical size) - digest
    /// collisions across unrelated groups are the caller's concern, not
    /// this function's, since it only ever sees one group at a time.
    static func partition(_ files: [InspectedFile], by hash: (InspectedFile) -> String?) -> [[InspectedFile]] {
        var groups: [String: [InspectedFile]] = [:]
        for file in files {
            guard let digest = hash(file) else { continue }
            groups[digest, default: []].append(file)
        }
        return groups.values.filter { $0.count > 1 }.map { $0 }
    }
}
