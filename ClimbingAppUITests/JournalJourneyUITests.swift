import XCTest

final class JournalJourneyUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    @MainActor private func launch(largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["startSession"].waitForExistence(timeout:15))
        return app
    }
    @MainActor private func tap(_ app: XCUIApplication, _ id: String) {
        let button = app.buttons[id].firstMatch
        for _ in 0..<8 { if button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout:5),id)
        button.tap()
    }
    @MainActor private func start(_ app: XCUIApplication) {
        tap(app,"startSession"); tap(app,"saveSession"); tap(app,"resumeSession")
    }
    @MainActor func testProjectsEmptyStateCreatesAndRecoversFilteredProjectAtLargeText() {
        let app = launch(largeText: true)
        app.tabBars.buttons["Projects"].tap()
        XCTAssertTrue(app.staticTexts["Save your first project"].waitForExistence(timeout: 5))
        tap(app, "projectsEmptyAction")
        XCTAssertTrue(app.navigationBars["Add climb"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Save your first project"].waitForExistence(timeout: 5))
        tap(app, "projectsEmptyAction")
        XCTAssertTrue(app.navigationBars["Add climb"].waitForExistence(timeout: 5))
        tap(app, "saveClimb")
        XCTAssertTrue(app.staticTexts["Boulder"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["projectsEmptyAction"].exists)
        app.buttons["projectStatusFilter"].tap(); app.buttons["Sent"].tap()
        XCTAssertTrue(app.staticTexts["No projects in this filter"].waitForExistence(timeout: 5))
        tap(app, "projectsEmptyAction")
        XCTAssertTrue(app.staticTexts["Boulder"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["projectsEmptyAction"].exists)
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.tabBars.buttons["Projects"].tap()
        XCTAssertTrue(app.staticTexts["Boulder"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Project created from empty state"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testUnnamedClimbDefaultsToUnknownDifficulty() {
        let app = launch()
        start(app); tap(app,"addClimb")
        XCTAssertFalse(app.textFields["customGrade"].exists)
        tap(app,"saveClimb")
        XCTAssertTrue(app.staticTexts["Unknown grade"].waitForExistence(timeout:5))
        tap(app,"logAttempt")
        XCTAssertTrue(app.staticTexts["1 attempt · 0 sends this session"].waitForExistence(timeout:5))
    }
    @MainActor func testProjectRetainsIdentityAndHistoryAcrossSessions() {
        let app = launch()
        start(app)
        tap(app,"addClimb")
        app.textFields["climbName"].tap(); app.textFields["climbName"].typeText("Heel hook project")
        app.switches["Save as a project"].tap()
        tap(app,"saveClimb"); tap(app,"logAttempt")
        tap(app,"finishSession"); tap(app,"confirmFinishSession")
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<8 { if app.buttons["startSession"].isHittable { break }; app.swipeDown() }
        start(app)
        tap(app,"chooseExistingClimb")
        app.staticTexts["Heel hook project"].firstMatch.tap()
        tap(app,"logSend")
        XCTAssertTrue(app.staticTexts["1 attempt · 1 send this session"].waitForExistence(timeout:5))
        tap(app,"Notebook and complete history")
        XCTAssertTrue(app.staticTexts["2 attempts across 2 sessions"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Earlier attempts or completion are known")).firstMatch.exists)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Project across two sessions"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testWholeSessionTotalsReplaceDetailedActivity() {
        let app = launch(); start(app); tap(app,"addClimb"); tap(app,"saveClimb"); tap(app,"logAttempt")
        tap(app,"addRecap")
        app.buttons["recapCoverage"].tap(); app.buttons["Whole-session totals"].tap()
        app.textFields["recapAttempts"].tap(); app.textFields["recapAttempts"].typeText("12")
        app.textFields["recapSends"].tap(); app.textFields["recapSends"].typeText("4")
        tap(app,"saveRecap")
        for _ in 0..<8 { if app.staticTexts["12"].isHittable { break }; app.swipeDown() }
        XCTAssertTrue(app.staticTexts["12"].exists)
        XCTAssertTrue(app.staticTexts["4"].exists)
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch(); tap(app,"resumeSession")
        XCTAssertTrue(app.staticTexts["12"].waitForExistence(timeout:5))
    }
    @MainActor func testPastRecapSendsOnlyKeepsAttemptsUnknownAtLargeText() {
        let app = launch(largeText:true)
        tap(app,"pastSession"); tap(app,"saveSession")
        let sends = app.textFields["recapSends"]
        for _ in 0..<12 { if sends.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(sends.waitForExistence(timeout:5)); sends.tap(); sends.typeText("4")
        tap(app,"saveRecap")
        tap(app,"Browse all history")
        app.staticTexts["Bouldering session"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Unknown"].waitForExistence(timeout:5))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Sends-only recap at accessibility text size"; shot.lifetime = .keepAlways; add(shot)
    }
}
