import Testing
@testable import DustEaterCore

struct DeveloperArtifactFoldersTests {
    @Test func isDeveloperArtifactDirectoryMatchesKnownNames() {
        #expect(DeveloperArtifactFolders.isDeveloperArtifactDirectory("node_modules"))
        #expect(DeveloperArtifactFolders.isDeveloperArtifactDirectory(".git"))
        #expect(DeveloperArtifactFolders.isDeveloperArtifactDirectory(".pnpm-store"))
    }

    @Test func isDeveloperArtifactDirectoryIsCaseInsensitive() {
        #expect(DeveloperArtifactFolders.isDeveloperArtifactDirectory("NODE_MODULES"))
        #expect(DeveloperArtifactFolders.isDeveloperArtifactDirectory("DerivedData"))
    }

    @Test func isDeveloperArtifactDirectoryRejectsOrdinaryNames() {
        #expect(!DeveloperArtifactFolders.isDeveloperArtifactDirectory("Documents"))
        #expect(!DeveloperArtifactFolders.isDeveloperArtifactDirectory("Photos"))
    }

    @Test func pathContainsDeveloperArtifactDetectsNestedDirectory() {
        #expect(DeveloperArtifactFolders.pathContainsDeveloperArtifact("/Users/x/ProjectA/node_modules/lodash/index.js"))
        #expect(DeveloperArtifactFolders.pathContainsDeveloperArtifact("/Users/x/repo/.git/objects/ab/cdef"))
    }

    @Test func pathContainsDeveloperArtifactRejectsOrdinaryPath() {
        #expect(!DeveloperArtifactFolders.pathContainsDeveloperArtifact("/Users/x/Documents/report.pdf"))
    }

    @Test func pathContainsDeveloperArtifactRespectsComponentBoundary() {
        // A folder literally named "node_modules_backup" is not
        // "node_modules" - matching must be on exact path components, not
        // a substring check.
        #expect(!DeveloperArtifactFolders.pathContainsDeveloperArtifact("/Users/x/node_modules_backup/file.txt"))
    }

    @Test func pathContainsDeveloperArtifactDetectsCargoBuildOutput() {
        // Regression case: a real Tauri (Rust + JS) project's Cargo build
        // directory - compiled object files and build-script binaries
        // under `target/debug/` - was showing up as duplicate/large-file
        // noise because "target" was missing from the list entirely.
        #expect(DeveloperArtifactFolders.pathContainsDeveloperArtifact(
            "/Users/x/repo/src-tauri/target/debug/deps/mylib.0llgz4iq.rcgu.o"
        ))
        #expect(DeveloperArtifactFolders.pathContainsDeveloperArtifact(
            "/Users/x/repo/src-tauri/target/debug/build/mylib-60d73ab6/build-script-build"
        ))
    }
}
