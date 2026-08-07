import Dispatch
import Foundation

/// Bridges blocking, synchronous work (like the `getattrlistbulk` syscall)
/// into async Swift without consuming threads from Swift's cooperative
/// thread pool.
///
/// The cooperative pool is sized to the number of CPU cores and is meant for
/// non-blocking work; running syscalls that block on I/O directly inside
/// `async` functions can starve that pool once fan-out (directories scanned
/// concurrently) exceeds the core count, since there's no thread left to
/// service task orchestration or actor hops. Dispatching the blocking call
/// onto a separate, genuinely concurrent `DispatchQueue` (which can grow its
/// worker thread count) avoids that starvation and lets I/O-bound syscalls
/// overlap far beyond the core count.
enum BlockingIO {
    private static let queue = DispatchQueue(
        label: "com.dusteater.scan-io",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// Caps how many blocking syscalls run at once. This is safe to gate
    /// with a plain semaphore (unlike task fan-out in `DiskScanner`) because
    /// each call is a self-contained leaf operation that never needs to
    /// acquire a second permit from this same pool to complete — so there's
    /// no circular wait, just plain throttling of real OS thread usage.
    /// Higher limit allows more concurrent I/O for filesystem-heavy scanning.
    private static let concurrencyLimit = DispatchSemaphore(
        value: ProcessInfo.processInfo.activeProcessorCount * 32
    )

    static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                concurrencyLimit.wait()
                defer { concurrencyLimit.signal() }
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
