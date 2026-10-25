import XCTest

final class FriendsUITests: XCTestCase {
    @MainActor func testUnconfiguredFriendsIsHonestAndJournalRemainsAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Friends"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Friends"].tap()
        XCTAssertTrue(app.staticTexts["Friends is coming next"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add friend"].exists)
        app.tabBars.buttons["Journal"].tap()
        XCTAssertTrue(app.buttons["startSession"].waitForExistence(timeout: 10), app.debugDescription)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Journal remains available with Friends unconfigured"; shot.lifetime = .keepAlways
        add(shot)
    }
}
