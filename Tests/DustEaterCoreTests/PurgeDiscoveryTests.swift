import Testing
@testable import DustEaterCore

struct PurgeDiscoveryTests {
    private func file(_ name: String, path: String, size: Int64) -> FileNode {
        FileNode(name: name, path: path, size: size, isDirectory: false)
    }

    private func dir(
        _ name: String,
        path: String,
        size: Int64,
        isSymlink: Bool = false,
        children: [FileNode] = []
    ) -> FileNode {
        FileNode(name: name, path: path, size: size, isDirectory: true, isSymlink: isSymlink, children: children)
    }

    @Test func findsNodeModulesAtDepthWithSizeFromTheNode() {
        let nodeModules = dir("node_modules", path: "/Users/x/Projects/app/node_modules", size: 500)
        let packageJSON = file("package.json", path: "/Users/x/Projects/app/package.json", size: 10)
        let app = dir("app", path: "/Users/x/Projects/app", size: 510, children: [nodeModules, packageJSON])
        let projects = dir("Projects", path: "/Users/x/Projects", size: 510, children: [app])
        let root = dir("x", path: "/Users/x", size: 510, children: [projects])

        let targets = PurgeCatalog.discover(in: root)

        #expect(targets.count == 1)
        #expect(targets.first?.path == "/Users/x/Projects/app/node_modules")
        #expect(targets.first?.sizeBytes == 500)
    }

    @Test func doesNotEmitNodeModulesNestedInsideAnAlreadyMatchedOne() {
        let inner = dir("node_modules", path: "/Users/x/app/node_modules/.bin/node_modules", size: 5)
        let outer = dir("node_modules", path: "/Users/x/app/node_modules", size: 100, children: [inner])
        let app = dir("app", path: "/Users/x/app", size: 100, children: [outer])
        let root = dir("x", path: "/Users/x", size: 100, children: [app])

        let targets = PurgeCatalog.discover(in: root)

        #expect(targets.count == 1)
        #expect(targets.first?.path == "/Users/x/app/node_modules")
    }

    @Test func targetDirectoryMatchedWithSiblingCargoToml() {
        let target = dir("target", path: "/Users/x/rustproj/target", size: 200)
        let cargoToml = file("Cargo.toml", path: "/Users/x/rustproj/Cargo.toml", size: 1)
        let project = dir("rustproj", path: "/Users/x/rustproj", size: 201, children: [target, cargoToml])
        let root = dir("x", path: "/Users/x", size: 201, children: [project])

        let targets = PurgeCatalog.discover(in: root)

        #expect(targets.count == 1)
        #expect(targets.first?.path == "/Users/x/rustproj/target")
    }

    @Test func targetDirectoryNotMatchedWithoutSiblingCargoToml() {
        let target = dir("target", path: "/Users/x/other/target", size: 50)
        let other = dir("other", path: "/Users/x/other", size: 50, children: [target])
        let root = dir("x", path: "/Users/x", size: 50, children: [other])

        #expect(PurgeCatalog.discover(in: root).isEmpty)
    }

    @Test func dotBuildRequiresSiblingPackageSwift() {
        let dotBuild = dir(".build", path: "/Users/x/swiftpkg/.build", size: 300)
        let packageSwift = file("Package.swift", path: "/Users/x/swiftpkg/Package.swift", size: 1)
        let project = dir("swiftpkg", path: "/Users/x/swiftpkg", size: 301, children: [dotBuild, packageSwift])
        let root = dir("x", path: "/Users/x", size: 301, children: [project])

        let targets = PurgeCatalog.discover(in: root)

        #expect(targets.count == 1)
        #expect(targets.first?.path == "/Users/x/swiftpkg/.build")
    }

    @Test func dotBuildNotMatchedWithoutPackageSwift() {
        let dotBuild = dir(".build", path: "/Users/x/other/.build", size: 50)
        let other = dir("other", path: "/Users/x/other", size: 50, children: [dotBuild])
        let root = dir("x", path: "/Users/x", size: 50, children: [other])

        #expect(PurgeCatalog.discover(in: root).isEmpty)
    }

    @Test func podsRequiresSiblingPodfile() {
        let pods = dir("Pods", path: "/Users/x/iosapp/Pods", size: 400)
        let podfile = file("Podfile", path: "/Users/x/iosapp/Podfile", size: 1)
        let project = dir("iosapp", path: "/Users/x/iosapp", size: 401, children: [pods, podfile])
        let root = dir("x", path: "/Users/x", size: 401, children: [project])

        let targets = PurgeCatalog.discover(in: root)

        #expect(targets.count == 1)
        #expect(targets.first?.path == "/Users/x/iosapp/Pods")
    }

    @Test func podsNotMatchedWithoutPodfile() {
        let pods = dir("Pods", path: "/Users/x/other/Pods", size: 50)
        let other = dir("other", path: "/Users/x/other", size: 50, children: [pods])
        let root = dir("x", path: "/Users/x", size: 50, children: [other])

        #expect(PurgeCatalog.discover(in: root).isEmpty)
    }

    @Test func gitDirectoryIsNeverEmitted() {
        let gitObjects = dir("objects", path: "/Users/x/repo/.git/objects", size: 900)
        let git = dir(".git", path: "/Users/x/repo/.git", size: 900, children: [gitObjects])
        let repo = dir("repo", path: "/Users/x/repo", size: 900, children: [git])
        let root = dir("x", path: "/Users/x", size: 900, children: [repo])

        #expect(PurgeCatalog.discover(in: root).isEmpty)
    }

    @Test func symlinkedDirectoriesAreSkipped() {
        let symlinkedNodeModules = dir(
            "node_modules",
            path: "/Users/x/app/node_modules",
            size: 100,
            isSymlink: true
        )
        let app = dir("app", path: "/Users/x/app", size: 100, children: [symlinkedNodeModules])
        let root = dir("x", path: "/Users/x", size: 100, children: [app])

        #expect(PurgeCatalog.discover(in: root).isEmpty)
    }

    @Test func fcpBundleProducesOneReportOnlyTargetSummingRenderAndTranscodedMedia() {
        let clip = file("clip1.mov", path: "/Users/x/Movies/Wedding.fcpbundle/Event 1/Render Files/clip1.mov", size: 1000)
        let renderFiles = dir("Render Files", path: "/Users/x/Movies/Wedding.fcpbundle/Event 1/Render Files", size: 1000, children: [clip])
        let proxy = file("proxy1.mov", path: "/Users/x/Movies/Wedding.fcpbundle/Event 1/Transcoded Media/proxy1.mov", size: 2000)
        let transcodedMedia = dir("Transcoded Media", path: "/Users/x/Movies/Wedding.fcpbundle/Event 1/Transcoded Media", size: 2000, children: [proxy])
        // Original camera media must never contribute to the reported size -
        // it's the user's source footage, not generated data.
        let originalMedia = dir("Original Media", path: "/Users/x/Movies/Wedding.fcpbundle/Event 1/Original Media", size: 5000)
        let event = dir("Event 1", path: "/Users/x/Movies/Wedding.fcpbundle/Event 1", size: 8000, children: [renderFiles, transcodedMedia, originalMedia])
        let bundle = dir("Wedding.fcpbundle", path: "/Users/x/Movies/Wedding.fcpbundle", size: 8000, children: [event])
        let movies = dir("Movies", path: "/Users/x/Movies", size: 8000, children: [bundle])
        let root = dir("x", path: "/Users/x", size: 8000, children: [movies])

        let targets = PurgeCatalog.discover(in: root)

        #expect(targets.count == 1)
        #expect(targets.first?.path == "/Users/x/Movies/Wedding.fcpbundle")
        #expect(targets.first?.sizeBytes == 3000)
        #expect(targets.first?.safety == .reportOnly)
    }
}
