import Testing
import Foundation
@testable import DustEaterCore

struct PurgeCatalogTests {
    private let fakeHome = "/Users/testuser"

    @Test func everyNonReportOnlyDefinitionIsDeletable() {
        // The highest-value test in this suite: catches anyone adding a
        // definition under a hard-blocked path (e.g. /opt/homebrew,
        // anywhere under /Library) that could never actually be deleted
        // through FileOperations.
        for definition in PurgeCatalog.definitions(homeDirectory: fakeHome) where definition.safety != .reportOnly {
            #expect(
                FileOperations.canDelete(at: definition.path),
                "\(definition.path) is not deletable via FileOperations"
            )
        }
    }

    @Test func noDefinitionIsDenied() {
        for definition in PurgeCatalog.definitions(homeDirectory: fakeHome) {
            #expect(
                !PurgeCatalog.isDenied(path: definition.path, homeDirectory: fakeHome),
                "\(definition.path) is on the deny list"
            )
        }
    }

    @Test func everyRebuildableDefinitionHasARebuildCommand() {
        for definition in PurgeCatalog.definitions(homeDirectory: fakeHome) where definition.safety == .rebuildable {
            #expect(definition.rebuildCommand != nil, "\(definition.path) is .rebuildable with no rebuildCommand")
        }
    }

    @Test func everyReportOnlyDefinitionHasAHintAndNoRebuildCommand() {
        for definition in PurgeCatalog.definitions(homeDirectory: fakeHome) where definition.safety == .reportOnly {
            #expect(definition.hint != nil, "\(definition.path) is .reportOnly with no hint")
            #expect(definition.rebuildCommand == nil, "\(definition.path) is .reportOnly but has a rebuildCommand")
        }
    }

    @Test func definitionIDsAreUnique() {
        let ids = PurgeCatalog.definitions(homeDirectory: fakeHome).map(\.id)
        #expect(ids.count == Set(ids).count)
    }

    @Test func isDeniedTrueForAudioMusicApps() {
        #expect(PurgeCatalog.isDenied(path: fakeHome + "/Music/Audio Music Apps", homeDirectory: fakeHome))
    }

    @Test func isDeniedTrueForFileNestedInsideAudioMusicApps() {
        #expect(PurgeCatalog.isDenied(
            path: fakeHome + "/Music/Audio Music Apps/Sampler/Kit.exs",
            homeDirectory: fakeHome
        ))
    }

    @Test func isDeniedTrueForXcodeUserData() {
        #expect(PurgeCatalog.isDenied(
            path: fakeHome + "/Library/Developer/Xcode/UserData",
            homeDirectory: fakeHome
        ))
    }

    @Test func isDeniedTrueForAdobePremiereAutoSave() {
        #expect(PurgeCatalog.isDenied(
            path: "/Volumes/External/Project/Adobe Premiere Pro Auto-Save/Project.prproj",
            homeDirectory: fakeHome
        ))
    }

    @Test func isDeniedFalseForDerivedData() {
        #expect(!PurgeCatalog.isDenied(
            path: fakeHome + "/Library/Developer/Xcode/DerivedData",
            homeDirectory: fakeHome
        ))
    }
}
