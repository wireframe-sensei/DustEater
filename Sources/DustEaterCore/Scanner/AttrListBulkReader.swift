import Darwin

/// One raw entry returned by a single `getattrlistbulk` call, before we've
/// decided what to do with it (recurse, sum, skip).
struct RawDirEntry {
    let name: String
    let isDirectory: Bool
    let isSymlink: Bool
    /// On-disk allocated size in bytes, as reported by the filesystem.
    let allocSize: Int64
    /// Inode number used to deduplicate hard-linked files
    let inode: UInt64
}

enum AttrListError: Error, CustomStringConvertible {
    case openFailed(path: String, errno: Int32)
    case bulkFailed(errno: Int32)

    var description: String {
        switch self {
        case .openFailed(let path, let err):
            return "open(\(path)) failed: \(String(cString: strerror(err)))"
        case .bulkFailed(let err):
            return "getattrlistbulk failed: \(String(cString: strerror(err)))"
        }
    }
}

/// Low-level wrapper around the `getattrlistbulk(2)` syscall.
///
/// This batch-fetches directory entries and their metadata (name, object
/// type, on-disk allocated size) in a single kernel call per buffer-full,
/// which is dramatically faster than `FileManager`'s enumerator or `stat`-ing
/// each entry individually, because it avoids one syscall round-trip per file.
enum AttrListBulkReader {

    /// Attempts to open `path` without reading its contents, purely to
    /// distinguish *why* a root scan target is inaccessible: nonexistent
    /// (`ENOENT`) vs. permission/TCC denied (`EACCES`/`EPERM`) vs. some
    /// other failure. Returns `0` on success. This is a cheap two-syscall
    /// check safe to call inline (unlike a full `listDirectory`, which can
    /// block on very large directories).
    static func probeAccess(atPath path: String) -> Int32 {
        let fd = open(path, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return 0
        }
        return errno
    }

    /// Lists the immediate children of `path` using `getattrlistbulk`.
    /// Does not recurse and does not follow symlinks.
    static func listDirectory(atPath path: String) throws -> [RawDirEntry] {
        let fd = open(path, O_RDONLY, 0)
        guard fd >= 0 else {
            throw AttrListError.openFailed(path: path, errno: errno)
        }
        defer { close(fd) }

        // Request: common attrs (name, object type, inode) + file attrs (allocated size).
        // ATTR_CMN_RETURNED_ATTRS MUST be requested so we can tell which
        // attributes the kernel actually filled in for each entry.
        // Inode is used to detect and deduplicate hard-linked files.
        var attrList = attrlist()
        attrList.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrList.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
            | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_OBJTYPE)
            | attrgroup_t(ATTR_CMN_ERROR)
            | attrgroup_t(ATTR_CMN_FILEID)
        attrList.fileattr = attrgroup_t(ATTR_FILE_ALLOCSIZE)

        let bufferSize = 1 << 16 // 64 KiB, large enough to batch hundreds of entries
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var results: [RawDirEntry] = []
        results.reserveCapacity(256)

        readLoop: while true {
            let entryCount: Int32 = buffer.withUnsafeMutableBytes { rawBuf in
                getattrlistbulk(fd, &attrList, rawBuf.baseAddress, bufferSize, 0)
            }

            if entryCount < 0 {
                throw AttrListError.bulkFailed(errno: errno)
            }
            if entryCount == 0 {
                break readLoop
            }

            buffer.withUnsafeBytes { rawBuf in
                var cursor = rawBuf.baseAddress!
                for _ in 0..<entryCount {
                    let entryStart = cursor
                    let entryLength = cursor.loadUnaligned(as: UInt32.self)
                    var fieldPtr = cursor + MemoryLayout<UInt32>.size

                    // ATTR_CMN_RETURNED_ATTRS is always emitted first when requested,
                    // regardless of bit position, immediately after the length field.
                    let returned = fieldPtr.loadUnaligned(as: attribute_set_t.self)
                    fieldPtr += MemoryLayout<attribute_set_t>.size

                    var name: String?
                    var objType: UInt32 = 0
                    var hadError = false
                    var allocSize: Int64 = 0
                    var inode: UInt64 = 0

                    // Remaining common attrs are packed in ascending bit order.
                    if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 {
                        let ref = fieldPtr.loadUnaligned(as: attrreference_t.self)
                        // attr_dataoffset is relative to the address of the
                        // attrreference_t struct itself, not the entry start.
                        let namePtr = fieldPtr + Int(ref.attr_dataoffset)
                        name = String(cString: namePtr.assumingMemoryBound(to: CChar.self))
                        fieldPtr += MemoryLayout<attrreference_t>.size
                    }
                    if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                        objType = fieldPtr.loadUnaligned(as: UInt32.self)
                        fieldPtr += MemoryLayout<UInt32>.size
                    }
                    if returned.commonattr & attrgroup_t(ATTR_CMN_ERROR) != 0 {
                        let err = fieldPtr.loadUnaligned(as: UInt32.self)
                        hadError = err != 0
                        fieldPtr += MemoryLayout<UInt32>.size
                    }
                    if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
                        inode = fieldPtr.loadUnaligned(as: UInt64.self)
                        fieldPtr += MemoryLayout<UInt64>.size
                    }
                    if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
                        allocSize = fieldPtr.loadUnaligned(as: Int64.self)
                        fieldPtr += MemoryLayout<Int64>.size
                    }

                    if !hadError, let name, name != "." && name != ".." {
                        let isDir = objType == UInt32(VDIR.rawValue)
                        let isLink = objType == UInt32(VLNK.rawValue)
                        results.append(
                            RawDirEntry(
                                name: name,
                                isDirectory: isDir,
                                isSymlink: isLink,
                                allocSize: isDir ? 0 : allocSize,
                                inode: inode
                            )
                        )
                    }

                    cursor = entryStart + Int(entryLength)
                }
            }
        }

        return results
    }
}
