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

/// Carries a value across an isolation boundary without the compiler
/// checking it for `Sendable`.
///
/// Needed because `NSImage` carries a `Sendable` conformance on the macOS 26
/// SDK but is explicitly `@_nonSendable` on the macOS 15 SDK that
/// `release.yml`'s x86_64 job builds against, and every target is
/// `.swiftLanguageMode(.v6)`. So `QLThumbnailGenerator`'s hop back from its
/// background queue compiles fine on a current SDK and is a hard error on
/// the older one. A plain generic struct has no `T: Sendable` constraint
/// (unlike `Task<Success, Failure>`, which does - that is exactly why
/// wrapping the `Task` itself could not work), so this compiles identically
/// against both SDKs.
///
/// Sound in fact, not just to the compiler: QuickLook hands back a freshly
/// created image that nothing else retains, and it is only ever read on the
/// main actor afterwards. Transferred, never shared.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
}

/// Generates and caches `QLThumbnailGenerator` thumbnails, keyed on path and
/// size. `@MainActor` rather than an `actor`: every cached value is an
/// `NSImage` handed straight to SwiftUI, so the main actor is where these
/// are consumed anyway, and it keeps the cache lookup itself off any
/// isolation boundary.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var cache: [String: NSImage] = [:]

    func thumbnail(forPath path: String, size: CGFloat) async -> NSImage? {
        guard ImageFileDetector.isImage(atPath: path) else { return nil }

        let key = "\(path)#\(Int(size))"
        if let cached = cache[key] { return cached }

        let result = await Self.generate(path: path, size: size).value
        if let result {
            cache[key] = result
        }
        return result
    }

    /// `.thumbnail`, not `.icon` - `.icon` overlays OS decorations (a
    /// page-curl corner, app badge) meant for Finder icon view, not a
    /// clean content preview of the image itself.
    ///
    /// `nonisolated` on purpose: QuickLook genuinely calls back on a
    /// background queue, so claiming main-actor isolation here would be a
    /// promise the runtime does not keep, and it is what makes the
    /// `MainActor.run` hop for `backingScaleFactor` below meaningful rather
    /// than redundant.
    nonisolated private static func generate(
        path: String,
        size: CGFloat
    ) async -> UncheckedSendableBox<NSImage?> {
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                continuation.resume(returning: UncheckedSendableBox(value: thumbnail?.nsImage))
            }
        }
    }
}
