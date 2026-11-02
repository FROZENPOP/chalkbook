import XCTest

final class HealthInsightsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    @MainActor private func launch(fixture: Bool = false, empty: Bool = false, large: Bool = false, audit: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data"]
        if audit { app.launchArguments += ["--accessibility-audit", "session-log"] }
        if fixture { app.launchArguments.append("--health-insights-fixture") }
        if empty { app.launchArguments.append("--health-insights-empty") }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }
    @MainActor private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<20 {
            if element.exists && element.isHittable { return }
            if element.exists && element.frame.midY < app.frame.midY { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func openLog(_ app: XCUIApplication, _ title: String) {
        XCTAssertTrue(app.tabBars.buttons["Progress"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Progress"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        reveal(app, row); row.tap()
        XCTAssertTrue(app.navigationBars["Session log"].waitForExistence(timeout: 5))
    }
    @MainActor private func connect(_ app: XCUIApplication) {
        let button = app.buttons["connectHealthInsights"]
        if button.waitForExistence(timeout: 3) { reveal(app, button); button.tap() }
    }
    @MainActor func testUnavailableHealthIsHonestAndAsksForNothing() {
        let app = launch(audit: true)
        let message = app.staticTexts["Apple Health is unavailable on this device."]
        reveal(app, message)
        XCTAssertFalse(app.buttons["connectHealthInsights"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["healthEffortCard"].exists)
    }
    @MainActor func testLogPutsClimbingFirstAndHealthAtKeyStatistics() {
        let app = launch(fixture: true)
        openLog(app, "Health fixture session")
        let sends = app.staticTexts["sends"], heading = app.staticTexts["Key statistics"]
        XCTAssertTrue(sends.waitForExistence(timeout: 5))
        reveal(app, heading)
        XCTAssertLessThan(sends.frame.minY, heading.frame.minY)
        connect(app)
        let effort = app.descendants(matching: .any)["healthEffortCard"]
        reveal(app, effort)
        XCTAssertTrue(effort.waitForExistence(timeout: 10))
        XCTAssertTrue((effort.value as? String)?.contains("5.7 / 10") == true)
        let average = app.descendants(matching: .any)["healthAverageHeartRateCard"]
        reveal(app, average)
        XCTAssertTrue((average.value as? String)?.contains("144 bpm") == true)
        XCTAssertTrue((app.descendants(matching: .any)["healthMaximumHeartRateCard"].value as? String)?.contains("176 bpm") == true)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Session log key statistics"; shot.lifetime = .keepAlways; add(shot)
        reveal(app, app.descendants(matching: .any)["healthHeartRateChart"])
    }
    @MainActor func testUnlinkedLogOffersLinkAndShowsNoNumbers() {
        let app = launch(fixture: true)
        openLog(app, "Unlinked fixture session")
        reveal(app, app.buttons["linkHealthWorkout"])
        XCTAssertFalse(app.descendants(matching: .any)["healthEffortCard"].exists)
    }
    @MainActor func testHealthStaysOutOfTheJournalEntry() {
        let app = launch(fixture: true)
        XCTAssertTrue(app.tabBars.buttons["Journal"].waitForExistence(timeout: 15))
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Health fixture session")).firstMatch
        reveal(app, row); row.tap()
        XCTAssertTrue(app.staticTexts["Your climbs"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Key statistics"].exists)
        XCTAssertFalse(app.buttons["linkHealthWorkout"].exists)
    }
    @MainActor func testDeletingFromTheLogReturnsToProgress() {
        let app = launch(fixture: true)
        openLog(app, "Health fixture session")
        app.buttons["openJournalEntry"].tap()
        app.buttons["Session options"].tap()
        app.buttons["Delete session"].tap()
        XCTAssertTrue(app.buttons["Delete session"].waitForExistence(timeout: 5))
        app.buttons["Delete session"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Health fixture session")).firstMatch.exists)
    }
    @MainActor func testEmptyReadsAtAccessibilityTextSizeDoNotInventMetrics() {
        let app = launch(fixture: true, empty: true, large: true)
        openLog(app, "Health fixture session")
        connect(app)
        let message = app.staticTexts["healthInsightsMessage"]
        reveal(app, message)
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(message.label.contains("No accessible data found"))
        XCTAssertFalse(app.descendants(matching: .any)["healthEffortCard"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Empty Health reads at accessibility XXXL"; shot.lifetime = .keepAlways; add(shot)
    }
}
