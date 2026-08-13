import QuickLookThumbnailing
import SwiftUI
import DustEaterCore

/// Shows a real image thumbnail for a file, falling back to the existing
/// generic Finder icon (`NSWorkspace.shared.icon(forFile:)`) both while the
/// real thumbnail is loading and for anything `ImageFileDetector` doesn't
/// consider an image - never a blank tile, matching the "no dead ends"
/// standard already applied to `QuickLookPreviewPane`.
///
/// The icon *is* the loading state: there's no separate spinner/placeholder
/// visual language to design, since the icon is already a correct,
/// meaningful thing to show and the swap to a real thumbnail reads as a
/// smooth upgrade rather than a flash.
struct ThumbnailImageView: View {
    let path: String
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: DustEaterTheme.Radius.sm))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .frame(width: size, height: size)
            }
        }
        // Keyed on `path`, not a bare `.task` - this view is reused as
        // list rows scroll (SwiftUI identity, not literal `NSView`/cell
        // reuse, but the same principle applies), so a bare `.task` would
        // only ever fire once per view *identity*, silently leaving a
        // stale thumbnail showing if the same row instance gets bound to a
        // different path. Keying on `path` reissues (and cancels the
        // previous) request whenever it changes.
        .task(id: path) {
            image = await ThumbnailCache.shared.thumbnail(forPath: path, size: size)
        }
        .accessibilityLabel(Text((path as NSString).lastPathComponent))
    }
}

/// Generates and caches `QLThumbnailGenerator` thumbnails, keyed on path and
/// size. An actor, not a lock or bare dictionary, for two reasons: it's the
/// natural way to be Swift 6 strict-concurrency safe with no extra
/// ceremony, and the `inFlight` map means two simultaneous requests for the
/// same path/size (e.g. a duplicate set's hero preview and its sidebar row
/// loading at once) share one `QLThumbnailGenerator` call instead of
/// issuing a redundant second one.
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private var cache: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    func thumbnail(forPath path: String, size: CGFloat) async -> NSImage? {
        guard ImageFileDetector.isImage(atPath: path) else { return nil }

        let key = "\(path)#\(Int(size))"
        if let cached = cache[key] { return cached }
        if let existing = inFlight[key] { return await existing.value }

        let task = Task<NSImage?, Never> {
            await Self.generate(path: path, size: size)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result {
            cache[key] = result
        }
        return result
    }

    /// `.thumbnail`, not `.icon` - `.icon` overlays OS decorations (a
    /// page-curl corner, app badge) meant for Finder icon view, not a
    /// clean content preview of the image itself.
    private static func generate(path: String, size: CGFloat) async -> NSImage? {
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                continuation.resume(returning: thumbnail?.nsImage)
            }
        }
    }
}
