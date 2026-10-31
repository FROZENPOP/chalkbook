import XCTest
@testable import ClimbingApp

@MainActor final class FriendSearchTests: XCTestCase {
    func testNameAndUsernameNormalizationUseStructuredRPCParameters() throws {
        let query = try XCTUnwrap(FriendSearchQuery("  @Climb_Buddy  "))
        XCTAssertEqual(query.term, "climb_buddy")
        XCTAssertEqual(query.path,"/rest/v1/rpc/search_climbers")
        XCTAssertEqual(query.rpcValues["search_text"] as? String,"climb_buddy")
        XCTAssertEqual(FriendSearchQuery("Ana María")?.term,"ana maría")
        XCTAssertEqual(FriendSearchQuery("Matt & Kim 🧗")?.term,"matt & kim 🧗")
        XCTAssertEqual(FriendSearchQuery("someone&select=*")?.rpcValues["search_text"] as? String,"someone&select=*")
        for invalid in ["", "@a", "%", "bad\u{0000}name", String(repeating: "a", count: 61)] {
            XCTAssertNil(FriendSearchQuery(invalid))
        }
    }

    func testEmptyOrInvalidQueryDoesNotCallServer() async {
        let search = FriendSearch()
        await search.search("@") { _ in XCTFail("Should not search"); return [] }
        XCTAssertEqual(search.state, .idle)
        XCTAssertTrue(search.results.isEmpty)
    }

    func testErrorClearsResultsAndRetryRecoversWithoutInventingMatches() async {
        let search = FriendSearch()
        await search.search("climber", delay: .zero) { _ in throw SocialError.server }
        XCTAssertEqual(search.state, .failed)
        XCTAssertTrue(search.results.isEmpty)
        await search.search("climber", delay: .zero) { _ in [] }
        XCTAssertEqual(search.state, .results)
        XCTAssertTrue(search.results.isEmpty)
    }

    func testOlderResponseCannotReplaceNewerSearchOrClearedQuery() async {
        let search = FriendSearch()
        let older = Task {
            await search.search("older", delay: .zero) { _ in
                try? await Task.sleep(for: .milliseconds(60))
                return [SocialProfile(id: UUID(), username: "older", display_name: "Old fixture", is_private: true)]
            }
        }
        // The older search must claim its revision first; a fixed sleep can lose that race on slow CI machines.
        while search.state != .loading { await Task.yield() }
        await search.search("newer", delay: .zero) { _ in [SocialProfile(id: UUID(), username: "newer", display_name: "New fixture", is_private: true)] }
        await older.value
        XCTAssertEqual(search.results.map(\.username), ["newer"])
        await search.search("") { _ in XCTFail("Clearing should not call the server"); return [] }
        XCTAssertEqual(search.state, .idle)
        XCTAssertTrue(search.results.isEmpty)
    }

    func testCancelledDebounceDoesNotFetch() async {
        let search = FriendSearch()
        let task = Task { await search.search("climber", delay: .seconds(5)) { _ in XCTFail("Cancelled debounce fetched"); return [] } }
        await Task.yield()
        task.cancel()
        await task.value
        XCTAssertTrue(search.results.isEmpty)
    }
}
