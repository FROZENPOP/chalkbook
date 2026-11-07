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
        XCTAssertEqual(store.errorMessage, "Usernames are 3–24 lowercase letters, numbers or underscores.")
    }

    func testProfileInputNamesEachProblem() {
        func problem(_ username: String = "alice", _ name: String = "Alice", _ bio: String = "") -> String? { ProfileInput.problem(username: username, name: name, bio: bio) }
        XCTAssertNil(problem())
        XCTAssertNil(problem("Alice_99", "Alicé 🧗", "Line one\nLine two"), "Usernames are lowercased; emoji, accents and line breaks in a bio are fine")
        XCTAssertEqual(problem("support"), "That username is reserved. Choose another one.")
        XCTAssertEqual(problem("chalkbook_team"), "That username is reserved. Choose another one.")
        XCTAssertEqual(problem("a"), "Usernames are 3–24 lowercase letters, numbers or underscores.")
        XCTAssertEqual(problem("bob';drop table--"), "Usernames are 3–24 lowercase letters, numbers or underscores.")
        XCTAssertEqual(problem("alice", "  "), "Enter a display name of 1–60 characters.")
        XCTAssertEqual(problem("alice", "Bob\u{202E}evil"), "Your display name has hidden or formatting characters. Retype it without them.")
        XCTAssertEqual(problem("alice", "Zero\u{200B}width"), "Your display name has hidden or formatting characters. Retype it without them.")
        XCTAssertEqual(problem("alice", "Chalkbook Support"), "Display names can’t include “Chalkbook”.")
        XCTAssertEqual(problem("alice", "Alice", String(repeating: "a", count: 241)), "Keep your bio to 240 characters or fewer.")
        XCTAssertEqual(problem("alice", "Alice", "safe\u{202E}evil"), "Your bio has hidden or formatting characters. Retype it without them.")
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
