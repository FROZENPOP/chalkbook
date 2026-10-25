import XCTest

final class FriendsUITests: XCTestCase {
    @MainActor func testSearchInputClearAndRetryAtLargeText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--test-friend-search", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Friends"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Friends"].tap()
        let field = app.textFields["friendSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for _ in 0..<4 { if field.isHittable { break }; app.swipeUp() }
        field.tap(); field.typeText("@climb_buddy\n")
        // The isolated test has no backend: it must offer retry, keep input, and never manufacture people.
        XCTAssertTrue(app.staticTexts["Search couldn’t connect."].waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, "@climb_buddy")
        app.buttons["clearFriendSearch"].tap()
        XCTAssertTrue(app.staticTexts["Know their username? Start typing above."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["clearFriendSearch"].exists)
        XCTAssertFalse(app.buttons["Add friend"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Add friends search at accessibility text size"; shot.lifetime = .keepAlways; add(shot)
    }

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
