import XCTest
import Foundation
@testable import ClimbingApp

/// Normal CI has no network dependency. For local photos use the documented Mac harness.
final class HoldHighlightFixtureTests: XCTestCase {
    private func fixtureDirectory(_ path: String?) throws -> URL {
        guard let path, FileManager.default.fileExists(atPath:path) else { throw XCTSkip("No local hold-highlight fixtures. Run scripts/download_hold_fixtures.py and the Mac evaluation harness.") }
        return URL(fileURLWithPath:path)
    }
    func testMissingFixtureDirectoryIsASkipRatherThanFailure() {
        XCTAssertThrowsError(try fixtureDirectory("/missing-fixtures-\(UUID().uuidString)")) { XCTAssertTrue($0 is XCTSkip) }
        XCTAssertThrowsError(try fixtureDirectory(nil)) { XCTAssertTrue($0 is XCTSkip) }
    }
    func testOptionalRealPhotoPipeline() throws {
        let folder = try fixtureDirectory(ProcessInfo.processInfo.environment["HOLD_HIGHLIGHT_FIXTURES"])
        let data = try Data(contentsOf:folder.appending(path:"tokyo_wall.jpg"))
        let output = try HoldHighlight.render(HoldHighlight.load(data),settings:.init(x:0.405,y:0.48,tolerance:0.35))
        XCTAssertLessThanOrEqual(max(output.width,output.height),1024)
    }
}
