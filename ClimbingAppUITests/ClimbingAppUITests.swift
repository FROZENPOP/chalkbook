import XCTest

final class ClimbingAppUITests: XCTestCase {
    @MainActor
    func testSessionLoggingPersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data"]
        app.launch()
        XCTAssertTrue(app.buttons["startSession"].waitForExistence(timeout: 10))
        app.buttons["startSession"].tap()
        let location = app.textFields["sessionLocation"]
        XCTAssertTrue(location.waitForExistence(timeout: 5))
        location.tap()
        location.typeText("Test Gym")
        app.buttons["saveSession"].tap()
        XCTAssertTrue(app.buttons["resumeSession"].waitForExistence(timeout: 5))
        app.buttons["resumeSession"].tap()
        app.buttons["addClimb"].tap()
        app.textFields["climbName"].tap()
        app.textFields["climbName"].typeText("Blue slab")
        app.buttons["saveClimb"].tap()
        let attempt = app.buttons["logAttempt"].firstMatch
        XCTAssertTrue(attempt.waitForExistence(timeout: 5))
        attempt.tap()
        let send = app.buttons["logSend"].firstMatch
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: send)
        waitForExpectations(timeout: 5)
        send.tap()
        XCTAssertTrue(app.staticTexts["2 attempts · 1 sends this session"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["resumeSession"].waitForExistence(timeout: 10))
        app.buttons["resumeSession"].tap()
        XCTAssertTrue(app.staticTexts["Blue slab"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 attempts · 1 sends this session"].exists)
        let finish = app.buttons["finishSession"]
        if !finish.isHittable { app.swipeUp() }
        finish.tap()
        app.buttons["confirmFinishSession"].tap()
        XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let history = app.buttons["Browse all history"]
        for _ in 0..<5 { if history.isHittable { break }; app.swipeUp() }
        history.tap()
        XCTAssertTrue(app.staticTexts["Test Gym"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Every attempt counts."].waitForExistence(timeout: 5))
    }
}
