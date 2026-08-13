import Darwin
import Foundation

/// Wraps `lstat(2)` to gather the facts `FileNode` doesn't carry - logical
/// size, timestamps, device/inode - for the small candidate set the
/// duplicate and large-file inspectors actually need to look at.
///
/// This is deliberately *not* folded into the main scan
/// (`AttrListBulkReader`/`DiskScanner`): that scan runs over every file on
/// the target, batching a handful of cheap common attributes via
/// `getattrlistbulk` to stay fast at millions of entries. Timestamps aren't
/// among them, and adding them there would grow every `FileNode` in memory
/// for data almost none of them need. Here, candidates are pre-filtered by
/// `FileNode.size` first (thousands of files after a 1 MB floor, not
/// millions), and only those get an individual `lstat`.
///
/// `lstat`, not `stat`: this must never follow a symlink into a location it
/// doesn't actually occupy on disk. In practice symlinks are already
/// excluded before candidates reach here (`DiskScanner` skips them building
/// the tree), but using `lstat` keeps this reader correct on its own terms.
enum FileStatReader {
    /// Returns the stat facts for the file at `path`, or `nil` if it's a
    /// directory, a symlink, or the file is no longer there (a real
    /// possibility - the filesystem can change between the scan that built
    /// the tree and this on-demand stat).
    static func facts(atPath path: String) -> InspectedFile? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        guard (info.st_mode & S_IFMT) == S_IFREG else { return nil }

        let name = (path as NSString).lastPathComponent
        return InspectedFile(
            path: path,
            name: name,
            logicalSize: Int64(info.st_size),
            allocatedSize: Int64(info.st_blocks) * 512,
            modifiedAt: date(from: info.st_mtimespec),
            accessedAt: date(from: info.st_atimespec),
            createdAt: date(from: info.st_birthtimespec),
            deviceID: UInt64(bitPattern: Int64(info.st_dev)),
            inode: info.st_ino
        )
    }

    private static func date(from ts: timespec) -> Date {
        Date(timeIntervalSince1970: Double(ts.tv_sec) + Double(ts.tv_nsec) / 1_000_000_000)
    }
}
