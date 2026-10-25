import XCTest
@testable import ClimbingApp

@MainActor final class FriendSearchTests: XCTestCase {
    func testUsernameNormalizationAndLiteralUnderscoreWithoutQueryInjection() throws {
        let query = try XCTUnwrap(FriendSearchQuery("  @Climb_Buddy  "))
        XCTAssertEqual(query.username, "climb_buddy")
        let components = try XCTUnwrap(URLComponents(string: query.path))
        let filters = try XCTUnwrap(components.queryItems)
        XCTAssertEqual(filters.first { $0.name == "username" }?.value, "ilike.climb\\_buddy*")
        XCTAssertEqual(filters.first { $0.name == "limit" }?.value, "30")
        for invalid in ["", "@a", "someone&select=*", "foo,bar", "%", "hello world", String(repeating: "a", count: 25)] {
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
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(10))
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
