import UniformTypeIdentifiers

/// Detects whether a file is a raster/vector image, by extension - used to
/// decide when the duplicate/large-file inspector should generate a real
/// thumbnail instead of showing a generic file-type icon.
///
/// Extension-based, not content-sniffed: this only needs to be right for
/// files that already have a normal image extension (`.jpg`, `.png`,
/// `.heic`, ...) - a mis-extensioned file just falls back to the generic
/// icon, which is a fine failure mode for a purely cosmetic decision.
public enum ImageFileDetector {
    public static func isImage(atPath path: String) -> Bool {
        let ext = (path as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image)
    }
}
