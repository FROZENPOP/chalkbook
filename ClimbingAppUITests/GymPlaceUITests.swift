import XCTest

final class GymPlaceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    @MainActor private func openGyms() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--reset-test-data"]
        app.launch()
        XCTAssertTrue(app.profileButton.waitForExistence(timeout:15))
        app.profileButton.tap()
        app.buttons["savedGyms"].tap()
        app.buttons["addSavedGym"].tap()
        XCTAssertTrue(app.textFields["gymName"].waitForExistence(timeout:5))
        return app
    }
    @MainActor func testManualGymAddressAndRemovedBulkDelete() {
        let app = openGyms()
        app.textFields["gymName"].tap();app.textFields["gymName"].typeText("Private training wall\n")
        app.textFields["gymAddress"].tap();app.textFields["gymAddress"].typeText("My garage")
        app.buttons["saveGym"].tap()
        XCTAssertTrue(app.staticTexts["My garage"].waitForExistence(timeout:5))
        app.staticTexts["Private training wall"].tap()
        XCTAssertEqual(app.textFields["gymAddress"].value as? String,"My garage")
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<6 { app.swipeUp() }
        XCTAssertFalse(app.buttons["Delete all climbing data"].exists)
    }
    @MainActor func testLivePlaceSuggestionFillsGymNameAndAddress() throws {
        let app = openGyms()
        app.textFields["gymName"].tap();app.textFields["gymName"].typeText("Brooklyn Boulders")
        let suggestion = app.buttons.matching(identifier:"gymPlaceSuggestion").firstMatch
        guard suggestion.waitForExistence(timeout:25) else { throw XCTSkip("Live Apple Maps service did not return a suggestion on this host; manual entry remains tested.") }
        suggestion.tap()
        let name = app.textFields["gymName"].value as? String ?? ""
        let address = app.textFields["gymAddress"].value as? String ?? ""
        XCTAssertFalse(name.isEmpty)
        XCTAssertFalse(address.isEmpty);XCTAssertNotEqual(address,"Address or city (optional)")
        let screenshot = XCTAttachment(screenshot:app.screenshot());screenshot.name="Gym populated from Apple Maps";screenshot.lifetime = .keepAlways;add(screenshot)
        app.buttons["saveGym"].tap()
        XCTAssertTrue(app.staticTexts[address].waitForExistence(timeout:5))
    }
}
