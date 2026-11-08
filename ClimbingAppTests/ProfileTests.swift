import XCTest
@testable import ClimbingApp

@MainActor
final class ProfileTests: XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.appending(path:UUID().uuidString) }
    func testProfileEditsPhotoRemovalAndDeferredSetupPersistAcrossReopening() throws {
        let directory = root();defer { try? FileManager.default.removeItem(at:directory) }
        let bundle = Bundle(for:Self.self)
        let fixture = try XCTUnwrap(bundle.url(forResource:"route-photo",withExtension:"png") ?? bundle.url(forResource:"route-photo",withExtension:"png",subdirectory:"Fixtures"))
        let photo = try ProfilePhoto.prepare(Data(contentsOf:fixture))
        let store = ProfileStore(key:"guest",directory:directory)
        XCTAssertTrue(store.save(name:"  Ana  ",bio:"Working on slabs",photo:photo))
        let reopened = ProfileStore(key:"guest",directory:directory)
        XCTAssertEqual(reopened.profile?.name,"Ana");XCTAssertEqual(reopened.profile?.photo,photo)
        XCTAssertTrue(reopened.save(name:"New name",bio:"",photo:nil))
        let edited = ProfileStore(key:"guest",directory:directory)
        XCTAssertEqual(edited.profile?.name,"New name");XCTAssertNil(edited.profile?.photo)
        XCTAssertTrue(edited.save(name:"Later",bio:"",photo:nil,setupComplete:false))
        XCTAssertEqual(ProfileStore(key:"guest",directory:directory).profile?.setupComplete,false)
    }
    func testProfilesAreIsolatedByAccountAndGuest() {
        let directory = root();defer { try? FileManager.default.removeItem(at:directory) }
        let first = String(repeating:"a",count:64), second = String(repeating:"b",count:64)
        XCTAssertTrue(ProfileStore(key:first,directory:directory).save(name:"Private name",bio:"",photo:nil))
        XCTAssertNil(ProfileStore(key:second,directory:directory).profile)
        XCTAssertNil(ProfileStore(key:"guest",directory:directory).profile)
        XCTAssertEqual(ProfileStore(key:first,directory:directory).profile?.name,"Private name")
    }
    func testInvalidInputAndFailedWriteDoNotClaimSuccess() throws {
        let directory = root();defer { try? FileManager.default.removeItem(at:directory) }
        XCTAssertThrowsError(try ProfileStore.validate(name:" ",bio:"",photo:nil))
        XCTAssertThrowsError(try ProfileStore.validate(name:"Ana",bio:String(repeating:"a",count:501),photo:nil))
        XCTAssertThrowsError(try ProfilePhoto.prepare(Data([1,2,3])))
        XCTAssertThrowsError(try ProfilePhoto.prepare(Data(repeating:0,count:ProfilePhoto.maximumImportBytes+1)))
        try Data("not a directory".utf8).write(to:directory)
        let store = ProfileStore(key:"guest",directory:directory)
        XCTAssertFalse(store.save(name:"Keep my draft",bio:"",photo:nil))
        XCTAssertNil(store.profile);XCTAssertNotNil(store.errorMessage)
    }
    func testDamagedProfileIsPreservedAndCannotBeOverwrittenByRetry() throws {
        let directory = root();defer { try? FileManager.default.removeItem(at:directory) }
        let folder = directory.appending(path:"guest")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let file = folder.appending(path:"profile.json"), bad = Data("broken profile".utf8)
        try bad.write(to:file)
        let store = ProfileStore(key:"guest",directory:directory)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.retrySave(name:"Overwrite",bio:"",photo:nil))
        XCTAssertEqual(try Data(contentsOf:file),bad)
        let invalid = ProfileStore(key:"../outside",directory:directory)
        invalid.retryLoading()
        XCTAssertNotNil(invalid.errorMessage)
        XCTAssertFalse(invalid.save(name:"Invalid",bio:"",photo:nil))
    }
    private func fixturePhoto() throws -> Data {
        let bundle = Bundle(for:Self.self)
        let fixture = try XCTUnwrap(bundle.url(forResource:"route-photo",withExtension:"png") ?? bundle.url(forResource:"route-photo",withExtension:"png",subdirectory:"Fixtures"))
        return try ProfilePhoto.prepare(Data(contentsOf:fixture))
    }
    func testNotNowKeepsAnExistingProfile() throws {
        let directory = root();defer { try? FileManager.default.removeItem(at:directory) }
        let store = ProfileStore(key:"guest",directory:directory)
        XCTAssertTrue(store.save(name:"Ana",bio:"Working on slabs",photo:try fixturePhoto()))
        let saved = store.profile
        XCTAssertTrue(ProfileEditorView.notNow(store,accountName:"Apple Name"))
        XCTAssertEqual(store.profile,saved)
        XCTAssertEqual(ProfileStore(key:"guest",directory:directory).profile,saved)
    }
    func testNotNowWithoutAProfileSavesTheFallbackName() {
        let directory = root();defer { try? FileManager.default.removeItem(at:directory) }
        let store = ProfileStore(key:"guest",directory:directory)
        XCTAssertTrue(ProfileEditorView.notNow(store,accountName:"  Ana Climber  "))
        XCTAssertEqual(store.profile?.name,"Ana Climber");XCTAssertEqual(store.profile?.setupComplete,false)
        let unnamed = ProfileStore(key:String(repeating:"c",count:64),directory:directory)
        XCTAssertTrue(ProfileEditorView.notNow(unnamed,accountName:nil))
        XCTAssertEqual(unnamed.profile?.name,"Climber")
    }
    func testUnpreparableFriendsPhotoShowsAnErrorAndSavesNothing() throws {
        let directory = root();defer { try? FileManager.default.removeItem(at:directory) }
        let store = ProfileStore(key:"guest",directory:directory)
        XCTAssertTrue(store.save(name:"Ana",bio:"Working on slabs",photo:try fixturePhoto()))
        let saved = store.profile
        var friendsCalls = 0
        XCTAssertThrowsError(try ProfileEditorView.save(store,name:"Ana B",bio:"New bio",photo:Data([1,2,3]),retry:false,syncFriends:true) { _ in friendsCalls += 1 }) {
            XCTAssertEqual($0.localizedDescription,"This photo couldn’t be prepared for Friends. Choose a smaller photo and try again.")
        }
        XCTAssertEqual(friendsCalls,0)
        XCTAssertEqual(store.profile,saved);XCTAssertNil(store.errorMessage)
        XCTAssertEqual(ProfileStore(key:"guest",directory:directory).profile,saved)
    }
    func testFailedFriendActionKeepsItsOwnMessage() async throws {
        let social = SocialStore(configuration:nil)
        let auth = AccountSession(vault:GuestAccountVault())
        let result = await FriendPersonRow.act(social,auth:auth,target:UUID(),action:"request")
        let failure = try XCTUnwrap(result)
        let cause = try XCTUnwrap(social.errorMessage)
        XCTAssertEqual(failure,"Couldn’t update this request. \(cause)")
        // A later call elsewhere clears or replaces the shared store message; the row keeps the text it captured.
        social.errorMessage = nil
        XCTAssertEqual(failure,"Couldn’t update this request. \(cause)")
        social.errorMessage = "Another request failed."
        XCTAssertFalse(failure.contains("Another request failed."))
    }
}
