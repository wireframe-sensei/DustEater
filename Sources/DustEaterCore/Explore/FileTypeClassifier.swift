import Foundation
import UniformTypeIdentifiers
import os

/// Classifies a file into one of the eight `FileTypeCategory` buckets by its
/// extension. Called once per file during the main scan (`DiskScanner`), so
/// this is deliberately cheap: a source-code/document/archive extension
/// list is checked first (fast, predictable, and more precise than hoping a
/// UTType conformance chain lines up with what a user calls "a code file"),
/// then `UTType` conformance covers the physical-media buckets, whose
/// system-declared hierarchies (`.image`, `.movie`, `.audio`) are reliable
/// and don't need a hand-maintained list. Results are cached per extension
/// (not per file) behind a lock, since `UTType(filenameExtension:)` does
/// real work and a scan sees the same handful of extensions millions of
/// times over.
public enum FileTypeClassifier {
    /// `.app` bundles are classified structurally by `DiskScanner` (a whole
    /// bundle becomes one `.applications` entry, not descended into file by
    /// file) - this only ever classifies plain files, so `.applications`
    /// never appears here.
    public static func category(forFileName name: String) -> FileTypeCategory {
        let ext = (name as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return .other }

        return cache.withLock { cache in
            if let cached = cache[ext] { return cached }
            let category = classify(extension: ext)
            cache[ext] = category
            return category
        }
    }

    private static let cache = OSAllocatedUnfairLock<[String: FileTypeCategory]>(initialState: [:])

    private static func classify(extension ext: String) -> FileTypeCategory {
        if codeAndProjectExtensions.contains(ext) { return .codeAndProjects }
        if documentExtensions.contains(ext) { return .documents }
        if archiveExtensions.contains(ext) { return .archivesAndInstallers }

        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .movie) { return .videos }
            if type.conforms(to: .image) { return .photos }
            if type.conforms(to: .audio) { return .audio }
            if type.conforms(to: .pdf) { return .documents }
            if type.conforms(to: .archive) || type.conforms(to: .diskImage) { return .archivesAndInstallers }
        }

        return .other
    }

    /// Source, script, and project-config file extensions. Deliberately a
    /// maintained list rather than `UTType.sourceCode` conformance: many
    /// everyday project files (`.json`, `.yml`, `.xcodeproj`, `.gradle`)
    /// don't reliably conform to `.sourceCode` in the system's own UTType
    /// hierarchy, and precision matters most for this bucket - it's the
    /// one users most want to trust ("is this actually part of a project").
    private static let codeAndProjectExtensions: Set<String> = [
        "swift", "m", "mm", "h", "hpp", "hh", "c", "cc", "cpp", "cxx",
        "py", "rb", "go", "rs", "java", "kt", "kts", "scala",
        "js", "jsx", "ts", "tsx", "mjs", "cjs", "vue", "svelte",
        "json", "yaml", "yml", "toml", "xml", "plist",
        "html", "htm", "css", "scss", "sass", "less",
        "sh", "bash", "zsh", "fish", "pl", "php", "lua", "sql",
        "gradle", "xcodeproj", "xcworkspace", "pbxproj", "podspec",
        "makefile", "cmake", "dockerfile", "gemfile", "rakefile",
        "md", "markdown", "rst", "proto", "graphql", "vim",
    ]

    private static let documentExtensions: Set<String> = [
        "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "txt", "rtf", "rtfd", "pages", "numbers", "key",
        "csv", "epub", "odt", "ods", "odp",
    ]

    private static let archiveExtensions: Set<String> = [
        "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar",
        "pkg", "xip", "iso", "deb", "rpm",
    ]
}
