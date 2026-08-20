import Foundation

/// Editorial copy - a title, a one-line description, and the exact command
/// that regenerates it - for a directory name that marks a project-local
/// dependency tree or build output. The single source both
/// `PurgeCatalog.discoveredDefinition` (Developer Kit's real, deletable
/// per-project targets, sibling-file-guarded because that module deletes
/// what it matches) and `DiskScanner`'s type-index classification (Explore's
/// Code & Projects folder rows, report-only, matched by name alone because a
/// mislabeled browse row costs nothing) key off of - two different
/// precision requirements, one shared table of what each name actually
/// means, so the rebuild command shown never drifts between the two
/// screens.
///
/// Deliberately a plain top-level file, not nested under `DeveloperKit/`:
/// `DiskScanner` (`Scanner/`) referencing something under `DeveloperKit/`
/// would be a foundational-scanning-depends-on-a-feature layering
/// violation. Both sides depend on this instead.
public enum DependencyDirectoryCatalog {
    public static func editorialInfo(forName name: String) -> (title: String, detail: String, rebuildCommand: String)? {
        switch name {
        case "node_modules":
            return ("node_modules", "JavaScript/TypeScript dependency tree.", "npm install")
        case "target":
            return ("target", "Rust build output for this Cargo project.", "cargo build")
        case ".build":
            return (".build", "Swift Package Manager build output for this package.", "swift build")
        case "Pods":
            return ("Pods", "CocoaPods dependency tree for this project.", "pod install")
        case ".venv", "venv":
            return (name, "Python virtual environment for this project.", "pip install -r requirements.txt")
        case ".next":
            return (".next", "Next.js build output for this project.", "npm run build")
        case "dist":
            return ("dist", "Build output for this project.", "npm run build")
        case "build":
            return ("build", "Build output for this project.", "npm run build")
        case "DerivedData":
            return ("DerivedData", "Xcode build output for this project.", "Reopen the project and build (Cmd-B)")
        default:
            return nil
        }
    }
}
