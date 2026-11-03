import XCTest
@testable import ClimbingApp

@MainActor final class SocialTests: XCTestCase {
    func testShareIsPrivateAndPayloadExcludesPrivateJournalFields() throws {
        let session = ClimbingSession(location: "Private gym address", notes: "Private notebook")
        let owner = UUID()
        let draft = SharedSession(session: session, owner: owner)
        XCTAssertEqual(draft.visibility, .private)
        XCTAssertEqual(draft.caption, "")
        XCTAssertEqual(Set(draft.rpcValues.keys), ["source_session_id", "visibility", "caption", "session_day", "attempts", "sends", "duration_minutes", "completeness"])
        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: draft.rpcValues), as: UTF8.self)
        XCTAssertFalse(encoded.contains("Private gym"))
        XCTAssertFalse(encoded.contains("Private notebook"))
        XCTAssertFalse(encoded.contains(owner.uuidString)) // Owner is assigned from server auth.uid(), never client input.
    }

    func testMissingSummaryValuesStayNullAndSharedCaptionIsIndependent() throws {
        let session = ClimbingSession(notes: "Local notes")
        session.durationKnown = false
        var draft = SharedSession(session: session, owner: UUID())
        draft.attempts = nil; draft.sends = 4; draft.caption = "A good session"
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: draft.rpcValues)) as? [String: Any])
        XCTAssertTrue(decoded["attempts"] is NSNull)
        XCTAssertTrue(decoded["duration_minutes"] is NSNull)
        XCTAssertEqual(decoded["sends"] as? Int, 4)
        session.notes = "Changed privately"
        XCTAssertEqual(draft.caption, "A good session")
    }

    func testUnconfiguredBackendDoesNotInventSocialDataOrClaimSuccess() async {
        let store = SocialStore(configuration: nil)
        let auth = AccountSession(vault: GuestAccountVault())
        await store.refresh(auth)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.me)
        XCTAssertTrue(store.people.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
        let removed = await store.removeShare(auth, sessionID: UUID())
        XCTAssertFalse(removed)
    }

    func testInvalidUsernameIsRejectedWithoutConnecting() async {
        let store = SocialStore(configuration: nil)
        let success = await store.saveProfile(AccountSession(vault: GuestAccountVault()), username: "bad name!", name: "Climber", isPrivate: true)
        XCTAssertFalse(success)
        XCTAssertEqual(store.errorMessage, SocialError.invalidProfile.localizedDescription)
    }

    func testCommentDecodesServerRowWithAndWithoutAuthor() throws {
        let row=#"{"id":"00000000-0000-0000-0000-000000000001","entry_id":"00000000-0000-0000-0000-000000000002","user_id":"00000000-0000-0000-0000-000000000003","body":"Nice send","created_at":"2026-11-02T04:12:33+00:00""#
        let saved=try SessionComment.decoder.decode(SessionComment.self,from:Data((row+"}").utf8))
        XCTAssertEqual(saved.body,"Nice send");XCTAssertNil(saved.author)
        XCTAssertEqual(saved.created_at,Date(timeIntervalSince1970:1_793_592_753))
        let listed=try SessionComment.decoder.decode(SessionComment.self,from:Data((row+#","author":{"id":"00000000-0000-0000-0000-000000000003","username":"alex","display_name":"Alex","is_private":true}}"#).utf8))
        XCTAssertEqual(listed.author?.display_name,"Alex")
    }
}
