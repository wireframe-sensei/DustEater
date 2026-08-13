import Testing
@testable import DustEaterCore

struct BundleProtectionTests {
    @Test func isBundleLikeDirectoryMatchesAppBundles() {
        #expect(BundleProtection.isBundleLikeDirectory("Xcode.app"))
        #expect(BundleProtection.isBundleLikeDirectory("Foundation.framework"))
    }

    @Test func isBundleLikeDirectoryMatchesCreativeLibraryPackages() {
        // Regression: "Wedding.fcpbundle".hasSuffix(".bundle") is false, so
        // these were previously unprotected despite being package
        // directories like .app/.framework.
        #expect(BundleProtection.isBundleLikeDirectory("Wedding.fcpbundle"))
        #expect(BundleProtection.isBundleLikeDirectory("Vacation.imovielibrary"))
        #expect(BundleProtection.isBundleLikeDirectory("MyShow.theater"))
        #expect(BundleProtection.isBundleLikeDirectory("MyShow.tvlibrary"))
        #expect(BundleProtection.isBundleLikeDirectory("Song.logicx"))
        #expect(BundleProtection.isBundleLikeDirectory("Jam.band"))
    }

    @Test func isBundleLikeDirectoryRejectsOrdinaryNames() {
        #expect(!BundleProtection.isBundleLikeDirectory("Documents"))
        #expect(!BundleProtection.isBundleLikeDirectory("node_modules"))
    }

    @Test func isInsideBundleDetectsFileWithinFCPLibrary() {
        #expect(BundleProtection.isInsideBundle(
            atPath: "/Users/x/Movies/Wedding.fcpbundle/Event 1/Render Files/a.mov"
        ))
    }

    @Test func isInsideBundleRejectsTheBundleItself() {
        // A bundle checking whether it itself is "inside" a bundle should
        // be false - isInsideBundle excludes the last path component.
        #expect(!BundleProtection.isInsideBundle(atPath: "/Users/x/Movies/Wedding.fcpbundle"))
    }

    @Test func isInsideBundleRejectsOrdinaryPath() {
        #expect(!BundleProtection.isInsideBundle(atPath: "/Users/x/Documents/report.pdf"))
    }
}
