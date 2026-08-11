import Foundation
import Testing
@testable import DustEaterCore

struct FileOperationsTests {
    /// `/Users` itself, and any account's home folder directly under it,
    /// must never be deletable from within the app - previously neither was
    /// in the protected list at all.
    @Test func protectsUsersDirectoryAndHomeFolders() {
        #expect(FileOperations.isSystemProtected(path: "/Users"))
        #expect(FileOperations.isSystemProtected(path: "/Users/someone"))
        #expect(FileOperations.isSystemProtected(path: "/Users/anotherAccount"))
    }

    /// The default folders macOS creates in every home directory - deleting
    /// one wholesale (not its contents, the folder itself) is almost always
    /// a mistake.
    @Test func protectsDefaultUserFoldersByExactPath() {
        let defaultFolders = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Library"]
        for folder in defaultFolders {
            #expect(FileOperations.isSystemProtected(path: "/Users/someone/\(folder)"), "\(folder) should be protected")
        }
    }

    /// Protection of a default folder is by exact path, not by prefix - the
    /// whole point of the app is clearing out clutter inside Downloads,
    /// Documents, etc., so individual items inside them must stay deletable.
    @Test func allowsDeletingItemsInsideDefaultUserFolders() {
        #expect(!FileOperations.isSystemProtected(path: "/Users/someone/Downloads/installer.dmg"))
        #expect(!FileOperations.isSystemProtected(path: "/Users/someone/Documents/report.pdf"))
        #expect(!FileOperations.isSystemProtected(path: "/Users/someone/Desktop/notes.txt"))
    }

    /// A custom, non-default folder directly in the home directory (e.g.
    /// "Projects") is not one of the folders macOS creates automatically,
    /// so it stays deletable like any other user-created folder.
    @Test func allowsDeletingCustomFoldersInHomeDirectory() {
        #expect(!FileOperations.isSystemProtected(path: "/Users/someone/Projects"))
        #expect(!FileOperations.isSystemProtected(path: "/Users/someone/Projects/old-repo"))
    }

    @Test func stillProtectsExistingSystemPaths() {
        #expect(FileOperations.isSystemProtected(path: "/System"))
        #expect(FileOperations.isSystemProtected(path: "/System/Library/CoreServices"))
        #expect(FileOperations.isSystemProtected(path: "/Library"))
        #expect(FileOperations.isSystemProtected(path: "/Applications"))
        #expect(FileOperations.isSystemProtected(path: "/usr/bin"))
        #expect(FileOperations.isSystemProtected(path: "/private/tmp"))
    }

    @Test func canDeleteMirrorsIsSystemProtected() {
        #expect(!FileOperations.canDelete(at: "/Users/someone"))
        #expect(!FileOperations.canDelete(at: "/Users/someone/Downloads"))
        #expect(FileOperations.canDelete(at: "/Users/someone/Downloads/installer.dmg"))
        #expect(FileOperations.canDelete(at: "/Users/someone/Projects"))
    }

    /// canDeleteAppBundle allows direct children of /Applications ending in .app
    @Test func canDeleteAppBundleAllowsDirectApplicationsChildren() {
        #expect(FileOperations.canDeleteAppBundle(at: "/Applications/Safari.app"))
        #expect(FileOperations.canDeleteAppBundle(at: "/Applications/MyApp.app"))
    }

    /// canDeleteAppBundle allows direct children of ~/Applications ending in .app
    @Test func canDeleteAppBundleAllowsHomeApplicationsChildren() {
        let homeDir = NSHomeDirectory()
        let appPath = (homeDir as NSString).appendingPathComponent("Applications/MyApp.app")
        #expect(FileOperations.canDeleteAppBundle(at: appPath))
    }

    /// canDeleteAppBundle rejects nested bundles (e.g. helper apps inside Xcode.app)
    @Test func canDeleteAppBundleRejectsNestedBundles() {
        #expect(!FileOperations.canDeleteAppBundle(at: "/Applications/Xcode.app/Contents/XPCServices/Helper.app"))
    }

    /// canDeleteAppBundle rejects paths not ending in .app
    @Test func canDeleteAppBundleRejectsNonAppPaths() {
        #expect(!FileOperations.canDeleteAppBundle(at: "/Applications/Safari"))
        #expect(!FileOperations.canDeleteAppBundle(at: "/Applications/MyFolder"))
    }

    /// canDeleteAppBundle rejects /System/Applications children
    /// (they're not direct children of /Applications)
    @Test func canDeleteAppBundleRejectsSystemApplications() {
        #expect(!FileOperations.canDeleteAppBundle(at: "/System/Applications/Notes.app"))
    }
}
