import Testing
@testable import DustEaterCore

struct ProjectDetectorTests {
    private func dir(_ name: String, path: String, children: [FileNode] = []) -> FileNode {
        FileNode(name: name, path: path, size: 0, isDirectory: true, children: children)
    }

    private func file(_ name: String, path: String) -> FileNode {
        FileNode(name: name, path: path, size: 1, isDirectory: false)
    }

    @Test func findsProjectRootMarkedByDotGit() {
        let git = dir(".git", path: "/x/repo/.git")
        let nodeModules = dir("node_modules", path: "/x/repo/node_modules")
        let repo = dir("repo", path: "/x/repo", children: [git, nodeModules])
        let root = dir("x", path: "/x", children: [repo])

        let found = ProjectDetector.projectRoot(forDirectoryContaining: "/x/repo", in: root)

        #expect(found?.path == "/x/repo")
        #expect(found?.name == "repo")
    }

    @Test func findsProjectRootMarkedByPackageJSON() {
        let packageJSON = file("package.json", path: "/x/app/package.json")
        let app = dir("app", path: "/x/app", children: [packageJSON])
        let root = dir("x", path: "/x", children: [app])

        let found = ProjectDetector.projectRoot(forDirectoryContaining: "/x/app", in: root)

        #expect(found?.path == "/x/app")
    }

    @Test func findsProjectRootMarkedByXcodeprojSuffix() {
        let xcodeproj = dir("MyApp.xcodeproj", path: "/x/App/MyApp.xcodeproj")
        let app = dir("App", path: "/x/App", children: [xcodeproj])
        let root = dir("x", path: "/x", children: [app])

        let found = ProjectDetector.projectRoot(forDirectoryContaining: "/x/App", in: root)

        #expect(found?.path == "/x/App")
    }

    /// The whole point: a monorepo's own `.git` at the top wins over any
    /// individual package's own nested `package.json` - one project, not
    /// one per package.
    @Test func outermostMarkerWinsOverNestedPackageManifest() {
        let git = dir(".git", path: "/x/monorepo/.git")
        let packageJSONInner = file("package.json", path: "/x/monorepo/apps/web/package.json")
        let nodeModulesInner = dir("node_modules", path: "/x/monorepo/apps/web/node_modules")
        let web = dir("web", path: "/x/monorepo/apps/web", children: [packageJSONInner, nodeModulesInner])
        let apps = dir("apps", path: "/x/monorepo/apps", children: [web])
        let monorepo = dir("monorepo", path: "/x/monorepo", children: [git, apps])
        let root = dir("x", path: "/x", children: [monorepo])

        let found = ProjectDetector.projectRoot(forDirectoryContaining: "/x/monorepo/apps/web", in: root)

        #expect(found?.path == "/x/monorepo")
        #expect(found?.name == "monorepo")
    }

    @Test func returnsNilWhenNoAncestorHasAMarker() {
        let plain = dir("plain", path: "/x/plain")
        let root = dir("x", path: "/x", children: [plain])

        let found = ProjectDetector.projectRoot(forDirectoryContaining: "/x/plain", in: root)

        #expect(found == nil)
    }

    @Test func scanRootItselfCanBeTheProjectRoot() {
        let git = dir(".git", path: "/x/.git")
        let root = dir("x", path: "/x", children: [git])

        let found = ProjectDetector.projectRoot(forDirectoryContaining: "/x", in: root)

        #expect(found?.path == "/x")
    }
}
