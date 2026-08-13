import CryptoKit
import Darwin
import Foundation

/// Computes content hashes for duplicate detection. Every blocking read
/// goes through `BlockingIO.run`.
enum FileHasher {
    private static let quickHashSampleSize = 4096
    private static let chunkSize = 1 << 20 // 1 MB

    private struct ChunkReadResult: Sendable {
        let bytesRead: Int
        let buffer: [UInt8]
    }

    /// SHA-256 of the file's first 4 KB (or the whole file, if smaller).
    /// This is the quick pass 1 hash: reading 4 KB is orders of magnitude
    /// cheaper than a full read, at the cost of not distinguishing files
    /// that share their first 4 KB but differ later - `fullDigest` (pass 2)
    /// covers that for whatever survives this pass.
    static func headDigest(atPath path: String) async -> String? {
        let result = (try? await BlockingIO.run { () -> ChunkReadResult? in
            let fd = open(path, O_RDONLY)
            guard fd >= 0 else { return nil }
            defer { close(fd) }
            var buffer = [UInt8](repeating: 0, count: quickHashSampleSize)
            let bytesRead = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, quickHashSampleSize) }
            guard bytesRead >= 0 else { return nil }
            return ChunkReadResult(bytesRead: bytesRead, buffer: buffer)
        }) ?? nil
        guard let result else { return nil }
        return hexEncoded(SHA256.hash(data: result.buffer[0..<result.bytesRead]))
    }

    /// Full streaming SHA-256, read in fixed 1 MB chunks - never loads a
    /// whole file into memory, since candidates here are routinely 1 GB+.
    ///
    /// Each chunk is its own `BlockingIO.run` call, deliberately not one
    /// call wrapping the whole read loop: `BlockingIO.run` dispatches its
    /// closure onto a plain `DispatchQueue`, which does not carry Swift
    /// Concurrency's task-local cancellation state - a `Task.isCancelled`
    /// check placed *inside* one giant blocking closure would never
    /// actually fire, no matter how long the file. Checking between chunks,
    /// from this genuinely async context, is what makes hashing a 50 GB
    /// file abort within about one chunk's read time instead of running to
    /// completion regardless of Cancel.
    static func fullDigest(atPath path: String) async -> String? {
        let openedFD = try? await BlockingIO.run { () -> Int32 in
            open(path, O_RDONLY)
        }
        guard let fd = openedFD, fd >= 0 else { return nil }
        defer { close(fd) }

        var hasher = SHA256()
        while true {
            guard !Task.isCancelled else { return nil }

            let result = (try? await BlockingIO.run { () -> ChunkReadResult? in
                var buffer = [UInt8](repeating: 0, count: chunkSize)
                let bytesRead = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, chunkSize) }
                guard bytesRead >= 0 else { return nil }
                return ChunkReadResult(bytesRead: bytesRead, buffer: buffer)
            }) ?? nil
            guard let result else { return nil }
            if result.bytesRead == 0 { break }
            hasher.update(data: result.buffer[0..<result.bytesRead])
        }
        return hexEncoded(hasher.finalize())
    }

    private static func hexEncoded<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
