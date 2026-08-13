import Foundation

/// Shared bundle-interior protection for the duplicate and large-file
/// inspectors, and for the delete step both eventually funnel through.
///
/// This can't be left to `FileOperations.isSystemProtected`: that only
/// blocks fixed system paths like `/Applications`, not a user-writable
/// `.app`/`.framework`/similar package sitting in `~/Downloads` or
/// `~/Desktop` - exactly where users keep the apps they might scan. Deleting
/// one file out of a signed bundle invalidates its code signature and can
/// silently break the app, even though the bundle itself sits entirely
/// outside every path `FileOperations` protects.
enum BundleProtection {
    private static let protectedSuffixes = [
        ".app", ".framework", ".bundle", ".xpc", ".plugin", ".appex",
        ".photoslibrary", ".sparsebundle",
        // Creative-suite library packages. None of these end in ".bundle"
        // despite being package directories, so each needs its own suffix -
        // "Wedding.fcpbundle".hasSuffix(".bundle") is false. Deleting a
        // single file out of one of these (a render file, a project asset)
        // can corrupt the whole library the same way deleting one file out
        // of a signed .app breaks its code signature.
        ".fcpbundle", ".imovielibrary", ".theater", ".tvlibrary",
        ".logicx", ".band",
    ]

    /// True when `name` (a single path component, not a full path) marks a
    /// structured package whose interior must never be treated as an
    /// inspectable or deletable candidate.
    static func isBundleLikeDirectory(_ name: String) -> Bool {
        protectedSuffixes.contains { name.hasSuffix($0) }
    }

    /// True when any component of `path` is a bundle-like directory - the
    /// full-path equivalent of `isBundleLikeDirectory`, for call sites that
    /// only have a path string and not a tree walk to carry state through
    /// (e.g. a final check right before deletion).
    static func isInsideBundle(atPath path: String) -> Bool {
        let components = (path as NSString).pathComponents
        // Exclude the last component: a bundle checking whether *it itself*
        // is bundle-like isn't "inside" anything - only its contents are.
        return components.dropLast().contains { isBundleLikeDirectory($0) }
    }
}
