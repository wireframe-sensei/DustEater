import Foundation

/// How confidently a purge target can be removed, defined by what the user
/// loses if the level is wrong - not by how the bytes were produced.
public enum PurgeSafetyLevel: Sendable, CaseIterable, Equatable {
    /// Regenerates transparently on next use. No user action, no
    /// perceptible cost.
    case safe
    /// Regenerates, but only after an explicit command plus real network or
    /// CPU time. Every `.rebuildable` `PurgeTargetDefinition` carries a
    /// non-nil `rebuildCommand` so "rebuildable" is a promise the user can
    /// act on, not a reassuring adjective.
    case rebuildable
    /// Can destroy something with no regeneration path at all, or breaks a
    /// live tool's state. Never bulk-selected - see `PurgeCatalog.isDenied`
    /// and the individual-toggle-only UI contract this level implies.
    case caution
    /// The size is shown and no delete action is ever offered. Every
    /// `.reportOnly` `PurgeTargetDefinition` carries a non-nil `hint`
    /// describing what to do instead. This exists as its own case (not an
    /// `isDeletable: Bool` alongside the other three) so a "Docker card
    /// with a delete button" is unrepresentable in the type, not merely
    /// discouraged in the view.
    case reportOnly
}

/// The developer or creative-app tool a `PurgeTargetDefinition` belongs to,
/// for grouping into `PurgeCategory` cards.
public enum PurgeCategoryID: String, Sendable, CaseIterable {
    case xcode, simulators, packageManagers, projectArtifacts, containers, adobe, finalCut, audio

    public var displayName: String {
        switch self {
        case .xcode: return "Xcode"
        case .simulators: return "iOS Simulator"
        case .packageManagers: return "Package Managers"
        case .projectArtifacts: return "Project Build Artifacts"
        case .containers: return "Docker"
        case .adobe: return "Adobe Creative Cloud"
        case .finalCut: return "Final Cut Pro"
        case .audio: return "Logic Pro & GarageBand"
        }
    }

    public var systemImage: String {
        switch self {
        case .xcode: return "hammer"
        case .simulators: return "iphone"
        case .packageManagers: return "shippingbox"
        case .projectArtifacts: return "folder.badge.gearshape"
        case .containers: return "cube"
        case .adobe: return "paintpalette"
        case .finalCut: return "film"
        case .audio: return "waveform"
        }
    }
}

/// One catalog entry: a known path (or, for tree-discovered targets, a
/// pattern already resolved to a path) plus the editorial judgement about
/// what it costs to delete it.
///
/// `safety` is stored here rather than derived from the path, because it
/// encodes knowledge no predicate can compute - "an `.xcarchive` holds the
/// dSYM needed to symbolicate a crash from a build that may have shipped" is
/// not something `FileOperations.isSystemProtected` can know. Storing it
/// also makes the catalog a single reviewable list where every judgement
/// call for a destructive feature is auditable on one screen.
public struct PurgeTargetDefinition: Sendable, Identifiable {
    public var id: String { path }

    public let path: String
    public let title: String
    public let detail: String
    public let categoryID: PurgeCategoryID
    public let safety: PurgeSafetyLevel
    /// The exact command that regenerates this target. Non-nil for every
    /// `.rebuildable` definition - see `PurgeSafetyLevel.rebuildable`.
    public let rebuildCommand: String?
    /// What the user should do instead of deleting through this screen.
    /// Non-nil for every `.reportOnly` definition.
    public let hint: String?
    /// When set, deletion is refused while the named app is running
    /// (`FileOperations.isAppRunning`). Deleting a media cache out from
    /// under a live editing session corrupts the open document in a way no
    /// path predicate can detect.
    public let blockingAppBundleID: String?

    public init(
        path: String,
        title: String,
        detail: String,
        categoryID: PurgeCategoryID,
        safety: PurgeSafetyLevel,
        rebuildCommand: String? = nil,
        hint: String? = nil,
        blockingAppBundleID: String? = nil
    ) {
        self.path = path
        self.title = title
        self.detail = detail
        self.categoryID = categoryID
        self.safety = safety
        self.rebuildCommand = rebuildCommand
        self.hint = hint
        self.blockingAppBundleID = blockingAppBundleID
    }
}

/// The fixed and tree-discovered catalog of developer and creative-app purge
/// targets, plus the deny list that overrides everything else.
public enum PurgeCatalog {
    /// Every fixed, well-known path this module knows about. `homeDirectory`
    /// is a parameter rather than an inline `NSHomeDirectory()` call so the
    /// whole catalog is testable against a fake home without touching the
    /// real one - the same DI shape as
    /// `LargeFileFinder.find(lastUsedDateProvider:)`.
    ///
    /// Two things deliberately do *not* appear here:
    /// - `~/Library/Developer/Xcode/Archives`, whose per-archive drill-in
    ///   list is built separately (see the Xcode Archives feature), not as
    ///   a single bulk-toggle definition.
    /// - `~/Library/Developer/Xcode/UserData` and
    ///   `~/Music/Audio Music Apps`, which are never enumerated at all - see
    ///   `isDenied`.
    public static func definitions(homeDirectory: String = NSHomeDirectory()) -> [PurgeTargetDefinition] {
        let home = homeDirectory
        return [
            // MARK: Xcode
            PurgeTargetDefinition(
                path: home + "/Library/Developer/Xcode/DerivedData",
                title: "DerivedData",
                detail: "Build intermediates and per-project indexes for every Xcode project you've opened.",
                categoryID: .xcode,
                safety: .rebuildable,
                rebuildCommand: "Reopen the project and build (Cmd-B)"
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Developer/Xcode/iOS DeviceSupport",
                title: "iOS DeviceSupport",
                detail: "Per-device-OS debug symbols, one folder per iOS version you've debugged on.",
                categoryID: .xcode,
                safety: .rebuildable,
                rebuildCommand: "Reconnect the device in Xcode"
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Developer/Xcode/watchOS DeviceSupport",
                title: "watchOS DeviceSupport",
                detail: "Per-device-OS debug symbols for Apple Watch.",
                categoryID: .xcode,
                safety: .rebuildable,
                rebuildCommand: "Reconnect the device in Xcode"
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Developer/Xcode/tvOS DeviceSupport",
                title: "tvOS DeviceSupport",
                detail: "Per-device-OS debug symbols for Apple TV.",
                categoryID: .xcode,
                safety: .rebuildable,
                rebuildCommand: "Reconnect the device in Xcode"
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Developer/Xcode/iOS Device Logs",
                title: "iOS Device Logs",
                detail: "Crash logs pulled from connected devices.",
                categoryID: .xcode,
                safety: .safe
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Caches/com.apple.dt.Xcode",
                title: "Xcode Cache",
                detail: "Xcode's own on-disk caches (module downloads, file-system cache).",
                categoryID: .xcode,
                safety: .safe
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Developer/DVTDownloads",
                title: "DVTDownloads",
                detail: "Downloaded platform components and documentation.",
                categoryID: .xcode,
                safety: .safe
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Caches/org.swift.swiftpm",
                title: "Swift Package Manager Cache",
                detail: "Resolved package checkouts and manifest cache.",
                categoryID: .xcode,
                safety: .rebuildable,
                rebuildCommand: "swift package resolve"
            ),

            // MARK: Simulators - all report-only, see module documentation
            // for why: runtimes are root-owned, mounted, and prefix-blocked
            // by `FileOperations.isSystemProtected`; the Devices folder
            // backs `simctl`'s own device set.
            PurgeTargetDefinition(
                path: "/Library/Developer/CoreSimulator/Images",
                title: "Simulator Runtimes",
                detail: "Downloaded iOS/watchOS/tvOS simulator runtime images.",
                categoryID: .simulators,
                safety: .reportOnly,
                hint: "Manage from Xcode: Settings > Platforms, or run `xcrun simctl runtime delete <id>`. These are mounted as read-only system volumes and cannot be deleted directly."
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Developer/CoreSimulator/Devices",
                title: "Simulator Devices",
                detail: "Per-simulator app containers and device state.",
                categoryID: .simulators,
                safety: .reportOnly,
                hint: "Run `xcrun simctl delete unavailable`, or remove individual simulators from Xcode's Devices window. Deleting this folder directly desynchronizes simctl's device set."
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Developer/CoreSimulator/Caches",
                title: "Simulator Caches",
                detail: "Shared dyld caches for simulator runtimes.",
                categoryID: .simulators,
                safety: .rebuildable,
                rebuildCommand: "Regenerates automatically on next simulator launch"
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Logs/CoreSimulator",
                title: "Simulator Logs",
                detail: "Simulator diagnostic logs.",
                categoryID: .simulators,
                safety: .safe
            ),

            // MARK: Package managers
            PurgeTargetDefinition(
                path: home + "/Library/Caches/Homebrew",
                title: "Homebrew Cache",
                detail: "Downloaded bottles and source archives.",
                categoryID: .packageManagers,
                safety: .safe
            ),
            PurgeTargetDefinition(
                path: home + "/.npm/_cacache",
                title: "npm Cache",
                detail: "Downloaded package tarballs.",
                categoryID: .packageManagers,
                safety: .safe
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Caches/Yarn",
                title: "Yarn Cache",
                detail: "Downloaded package tarballs.",
                categoryID: .packageManagers,
                safety: .safe
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Caches/bun",
                title: "Bun Cache",
                detail: "Downloaded package tarballs.",
                categoryID: .packageManagers,
                safety: .safe
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Caches/go-build",
                title: "Go Build Cache",
                detail: "Compiled package objects, keyed by source hash.",
                categoryID: .packageManagers,
                safety: .safe
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Caches/pip",
                title: "pip Cache",
                detail: "Downloaded wheel and source packages.",
                categoryID: .packageManagers,
                safety: .safe
            ),
            PurgeTargetDefinition(
                path: home + "/.gradle/daemon",
                title: "Gradle Daemon State",
                detail: "Background build-daemon working files.",
                categoryID: .packageManagers,
                safety: .safe
            ),
            PurgeTargetDefinition(
                path: home + "/.gradle/native",
                title: "Gradle Native Cache",
                detail: "Downloaded native-toolchain components.",
                categoryID: .packageManagers,
                safety: .safe
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Caches/CocoaPods",
                title: "CocoaPods Cache",
                detail: "Downloaded pod archives.",
                categoryID: .packageManagers,
                safety: .safe
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Caches/JetBrains",
                title: "JetBrains Cache",
                detail: "IDE indexes and downloaded components across JetBrains products.",
                categoryID: .packageManagers,
                safety: .safe
            ),
            PurgeTargetDefinition(
                path: home + "/.cargo/registry",
                title: "Cargo Registry",
                detail: "Downloaded crate sources and the crates.io index.",
                categoryID: .packageManagers,
                safety: .rebuildable,
                rebuildCommand: "cargo fetch"
            ),
            PurgeTargetDefinition(
                path: home + "/.gradle/caches",
                title: "Gradle Caches",
                detail: "Downloaded dependencies and build caches across all Gradle projects.",
                categoryID: .packageManagers,
                safety: .rebuildable,
                rebuildCommand: "./gradlew build (per project)"
            ),
            PurgeTargetDefinition(
                path: home + "/.m2/repository",
                title: "Maven Repository",
                detail: "Downloaded Maven dependencies.",
                categoryID: .packageManagers,
                safety: .rebuildable,
                rebuildCommand: "mvn dependency:resolve"
            ),
            PurgeTargetDefinition(
                path: home + "/.cocoapods/repos",
                title: "CocoaPods Specs",
                detail: "Local mirror of the CocoaPods spec repositories.",
                categoryID: .packageManagers,
                safety: .rebuildable,
                rebuildCommand: "pod repo update"
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Caches/deno",
                title: "Deno Cache",
                detail: "Downloaded modules and compiled output.",
                categoryID: .packageManagers,
                safety: .rebuildable,
                rebuildCommand: "deno cache"
            ),
            PurgeTargetDefinition(
                path: home + "/Library/pnpm/store",
                title: "pnpm Store",
                detail: "pnpm's global content-addressable package store. pnpm hard-links from this store into every project's node_modules - deleting it leaves dangling links until the next `pnpm install` in each project.",
                categoryID: .packageManagers,
                safety: .rebuildable,
                rebuildCommand: "pnpm install (per project)"
            ),
            PurgeTargetDefinition(
                path: home + "/.rustup/toolchains",
                title: "Rust Toolchains",
                detail: "Installed Rust toolchains. Removing one breaks any project pinned to it via rust-toolchain.toml until it's reinstalled.",
                categoryID: .packageManagers,
                safety: .caution
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Android/sdk/system-images",
                title: "Android Emulator Images",
                detail: "Downloaded Android emulator system images, re-downloadable via Android Studio's SDK Manager but multiple gigabytes per API level.",
                categoryID: .packageManagers,
                safety: .caution
            ),

            // MARK: Docker - report-only, see module documentation.
            PurgeTargetDefinition(
                path: home + "/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
                title: "Docker Desktop Disk",
                detail: "Every container, image, and volume Docker Desktop manages, in one sparse disk image.",
                categoryID: .containers,
                safety: .reportOnly,
                hint: "Reclaim from Docker Desktop: Settings > Resources > Advanced, or run `docker system prune -a`. Deleting this file directly destroys every container, image, and volume."
            ),

            // MARK: Adobe
            PurgeTargetDefinition(
                path: home + "/Library/Application Support/Adobe/Common/Media Cache Files",
                title: "Adobe Media Cache Files",
                detail: "Conformed audio/video peak and preview files shared across Premiere Pro and After Effects.",
                categoryID: .adobe,
                safety: .rebuildable,
                rebuildCommand: "Reconformed automatically the next time each project opens"
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Application Support/Adobe/Common/Media Cache",
                title: "Adobe Media Cache Database",
                detail: "The index database for the Media Cache Files above.",
                categoryID: .adobe,
                safety: .rebuildable,
                rebuildCommand: "Rebuilt automatically the next time each project opens"
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Application Support/Adobe/Common/Peak Files",
                title: "Adobe Peak Files",
                detail: "Audio waveform peak files.",
                categoryID: .adobe,
                safety: .safe
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Application Support/Adobe/Common/Analyzer Cache Files",
                title: "Adobe Analyzer Cache",
                detail: "Content-analysis cache used by Adobe Sensei features.",
                categoryID: .adobe,
                safety: .rebuildable,
                rebuildCommand: "Regenerated automatically on next analysis"
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Caches/Adobe Camera Raw 2",
                title: "Camera Raw Cache",
                detail: "Cached raw-image previews and thumbnails.",
                categoryID: .adobe,
                safety: .safe
            ),
            PurgeTargetDefinition(
                path: home + "/Library/Caches/Adobe",
                title: "Adobe App Caches",
                detail: "Miscellaneous per-app caches shared across the Creative Cloud suite.",
                categoryID: .adobe,
                safety: .safe
            ),
        ]
    }

    /// Directory names that mark a project-local build artifact, matched
    /// during `discover`'s tree walk. Distinct from `DeveloperArtifactFolders`
    /// (which this module does not reuse): that list is deliberately loose
    /// because it only ever *filters a display list*, and its own doc
    /// comment admits `target` over-matches. A sibling-file requirement here
    /// tightens exactly the entries that need it, because this module
    /// *deletes* what it matches.
    private static func discoveredDefinition(for node: FileNode, siblingNames: Set<String>) -> PurgeTargetDefinition? {
        let name = node.name
        let path = node.path

        if name == "node_modules" {
            return PurgeTargetDefinition(
                path: path,
                title: "node_modules",
                detail: "JavaScript/TypeScript dependency tree.",
                categoryID: .projectArtifacts,
                safety: .rebuildable,
                rebuildCommand: "npm install"
            )
        }
        if name == "target", siblingNames.contains("Cargo.toml") {
            return PurgeTargetDefinition(
                path: path,
                title: "target",
                detail: "Rust build output for this Cargo project.",
                categoryID: .projectArtifacts,
                safety: .rebuildable,
                rebuildCommand: "cargo build"
            )
        }
        if name == ".build", siblingNames.contains("Package.swift") {
            return PurgeTargetDefinition(
                path: path,
                title: ".build",
                detail: "Swift Package Manager build output for this package.",
                categoryID: .projectArtifacts,
                safety: .rebuildable,
                rebuildCommand: "swift build"
            )
        }
        if name == "Pods", siblingNames.contains("Podfile") {
            return PurgeTargetDefinition(
                path: path,
                title: "Pods",
                detail: "CocoaPods dependency tree for this project.",
                categoryID: .projectArtifacts,
                safety: .rebuildable,
                rebuildCommand: "pod install"
            )
        }
        if name == "__pycache__" || name == ".pytest_cache" || name == ".tox" {
            return PurgeTargetDefinition(
                path: path,
                title: name,
                detail: "Python bytecode or test cache.",
                categoryID: .projectArtifacts,
                safety: .safe
            )
        }
        if name == ".venv" || name == "venv" {
            guard siblingNames.contains("requirements.txt") || siblingNames.contains("pyproject.toml") else {
                return nil
            }
            return PurgeTargetDefinition(
                path: path,
                title: name,
                detail: "Python virtual environment for this project.",
                categoryID: .projectArtifacts,
                safety: .rebuildable,
                rebuildCommand: "pip install -r requirements.txt"
            )
        }
        if name == "Adobe Premiere Pro Video Previews"
            || name == "Adobe Premiere Pro Audio Previews"
            || name == "Adobe Premiere Pro Preview Files" {
            return PurgeTargetDefinition(
                path: path,
                title: name,
                detail: "Rendered preview media for a Premiere Pro project, generated next to the project file.",
                categoryID: .adobe,
                safety: .rebuildable,
                rebuildCommand: "Re-render the timeline in Premiere Pro",
                blockingAppBundleID: "com.adobe.PremierePro"
            )
        }

        return nil
    }

    /// Project-local targets found by one iterative walk of an already
    /// scanned tree - no second directory walk, no second permission
    /// prompt, sizes come straight off the nodes. Never descends into a
    /// match, so a `node_modules` nested inside another never becomes its
    /// own row, and a `.fcpbundle`'s or `.logicx`'s interior is never
    /// individually enumerated.
    public static func discover(in root: FileNode) -> [PurgeTarget] {
        var results: [PurgeTarget] = []
        var stack: [FileNode] = [root]

        while let node = stack.popLast() {
            guard node.isDirectory else { continue }
            let siblingNames = Set(node.children.map { $0.name })

            for child in node.children {
                guard child.isDirectory, !child.isSymlink, !child.isSyntheticGroupingNode else { continue }
                guard !isDenied(path: child.path) else { continue }

                if BundleProtection.isBundleLikeDirectory(child.name) {
                    if child.name.hasSuffix(".fcpbundle"), let target = fcpBundleTarget(child) {
                        results.append(target)
                    } else if child.name.hasSuffix(".logicx"), let target = logicxBundleTarget(child) {
                        results.append(target)
                    }
                    continue // never descend into any bundle interior
                }

                if let definition = discoveredDefinition(for: child, siblingNames: siblingNames) {
                    results.append(PurgeTarget(definition: definition, sizeBytes: child.size))
                    continue // never descend into a matched target
                }

                stack.append(child)
            }
        }

        return results
    }

    /// Report-only: Final Cut Pro knows which renders are still referenced
    /// by a library and this module does not, and transcoded/proxy media is
    /// sometimes the only viewable copy once the originals go offline. See
    /// module documentation for the full reasoning.
    private static func fcpBundleTarget(_ bundle: FileNode) -> PurgeTarget? {
        let totalBytes = sumMatchingDescendants(of: bundle, matching: ["Render Files", "Transcoded Media"])
        guard totalBytes > 0 else { return nil }
        let definition = PurgeTargetDefinition(
            path: bundle.path,
            title: bundle.name,
            detail: "Render files and transcoded/proxy media inside this Final Cut Pro library.",
            categoryID: .finalCut,
            safety: .reportOnly,
            hint: "Reveal in Finder, then in Final Cut Pro: File > Delete Generated Library Files."
        )
        return PurgeTarget(definition: definition, sizeBytes: totalBytes)
    }

    /// Report-only, and for the same reason as FCP above: the internal
    /// directory names are not verified against a real Logic Pro
    /// installation, so a wrong guess here should cost a missing number,
    /// never an attempted deletion.
    private static func logicxBundleTarget(_ bundle: FileNode) -> PurgeTarget? {
        let totalBytes = sumMatchingDescendants(of: bundle, matching: ["Freeze Files", "Undo Data"])
        guard totalBytes > 0 else { return nil }
        let definition = PurgeTargetDefinition(
            path: bundle.path,
            title: bundle.name,
            detail: "Freeze renders and undo history inside this Logic Pro project.",
            categoryID: .audio,
            safety: .reportOnly,
            hint: "Open in Logic Pro to manage freeze files. Undo history is safe to lose once the project is closed."
        )
        return PurgeTarget(definition: definition, sizeBytes: totalBytes)
    }

    /// Sums the sizes of descendants whose name matches `names`, without
    /// descending further once a match is found - `FileNode.size` for a
    /// directory already sums every descendant, so recursing into a match
    /// would double-count.
    private static func sumMatchingDescendants(of node: FileNode, matching names: Set<String>) -> Int64 {
        var total: Int64 = 0
        for child in node.children {
            if names.contains(child.name) {
                total += child.size
                continue
            }
            if child.isDirectory {
                total += sumMatchingDescendants(of: child, matching: names)
            }
        }
        return total
    }

    /// A hard refusal layered on top of `FileOperations.canDelete`, for
    /// paths that are user-writable and unprotected today but must never be
    /// enumerated by this module:
    /// - `~/Music/Audio Music Apps` - user sampler instruments, patches, and
    ///   **recorded audio**. Nothing in `FileOperations` protects this today.
    /// - `~/Library/Developer/Xcode/UserData` - code snippets, key bindings,
    ///   breakpoints, and themes: years of personal configuration, not a
    ///   cache.
    /// - Any path containing an `Adobe Premiere Pro Auto-Save` component -
    ///   project recovery data sitting one directory away from the preview
    ///   caches `discover` does match, and the single most likely way this
    ///   module could destroy someone's actual work.
    public static func isDenied(path: String, homeDirectory: String = NSHomeDirectory()) -> Bool {
        let normalizedPath = (path as NSString).standardizingPath
        let normalizedHome = (homeDirectory as NSString).standardizingPath

        let deniedRoots = [
            normalizedHome + "/Music/Audio Music Apps",
            normalizedHome + "/Library/Developer/Xcode/UserData",
        ]
        let isUnderDeniedRoot = deniedRoots.contains { deniedRoot in
            normalizedPath == deniedRoot || normalizedPath.hasPrefix(deniedRoot + "/")
        }
        if isUnderDeniedRoot { return true }

        return (path as NSString).pathComponents.contains("Adobe Premiere Pro Auto-Save")
    }
}
