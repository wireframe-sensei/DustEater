import CoreServices
import Dispatch

/// Watches a directory subtree for filesystem changes using FSEvents - the
/// same kernel-level mechanism Spotlight and Time Machine use, so watching
/// an entire scanned root (even a whole volume) is cheap: no polling, no
/// per-directory file descriptors.
///
/// Deliberately reports only "something changed" via `onChange`, not what
/// changed - reconciling a live change into the existing `FileNode` tree
/// would need size/itemCount deltas propagated through every ancestor plus
/// treemap cache invalidation, which `FileNode` doesn't support today (see
/// CLAUDE.md). `ScanCoordinator` turns this signal into a "Rescan" prompt
/// instead of attempting that reconciliation.
///
/// `@unchecked Sendable`: the only mutable state is `stream`, touched only
/// from `init`/`stop`/`deinit`, which the sole caller (`ScanCoordinator`, a
/// `@MainActor` type) only ever does from the main actor. The FSEvents
/// callback itself never touches `self` across the concurrency boundary -
/// it only forwards the already-`@MainActor @Sendable` `onChange` closure
/// into a `Task` that hops onto that actor before calling it.
final class FileSystemWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor @Sendable () -> Void

    init(path: String, onChange: @escaping @MainActor @Sendable () -> Void) {
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fileSystemWatcherCallback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0, // seconds - coalesces bursts (e.g. a build running under
                 // the watched folder) into a single callback rather than
                 // flipping the flag on every individual write.
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagIgnoreSelf)
            // `IgnoreSelf` is load-bearing, not incidental: without it, an
            // in-app delete (already reconciled into the tree via
            // `FileNode.removingNode(atPath:)`) would immediately trigger a
            // spurious "files changed, rescan?" prompt about a change the
            // app already knows about and already applied.
        ) else {
            self.stream = nil
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    fileprivate func handleEvent() {
        let callback = onChange
        Task { @MainActor in
            callback()
        }
    }

    deinit {
        stop()
    }
}

/// Free function, not a closure - FSEvents requires a `@convention(c)`
/// callback, which can't capture context. `self` travels through instead via
/// the `info` opaque pointer set up in `FileSystemWatcher.init`.
private func fileSystemWatcherCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    Unmanaged<FileSystemWatcher>.fromOpaque(info).takeUnretainedValue().handleEvent()
}
