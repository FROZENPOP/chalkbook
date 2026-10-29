import XCTest

final class HealthInsightsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    @MainActor private func launch(fixture: Bool = false, empty: Bool = false, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data"]
        if fixture { app.launchArguments.append("--health-insights-fixture") }
        if empty { app.launchArguments.append("--health-insights-empty") }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Progress"].waitForExistence(timeout: 15))
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
    @MainActor private func tap(_ app: XCUIApplication, _ id: String) {
        let button = app.buttons[id].firstMatch; reveal(app, button); button.tap()
    }
    @MainActor private func enable(_ app: XCUIApplication) {
        let toggle = app.switches["showHealthInsights"]
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        tap(app, "connectHealthInsights")
    }
    @MainActor func testHealthIsOffByDefaultAndUnavailableIsHonest() {
        let app = launch()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertEqual(app.switches["showHealthInsights"].value as? String, "0")
        XCTAssertFalse(app.buttons["connectHealthInsights"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["healthInsightsHeading"].exists)
        app.switches["showHealthInsights"].coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let connect = app.buttons["connectHealthInsights"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5));XCTAssertFalse(connect.isEnabled)
        XCTAssertTrue(app.staticTexts["Apple Health is unavailable on this device."].exists)
    }
    @MainActor func testWeeklyAndLinkedSessionCardsWithFakeReaderAndUnlinkedSessionHasNone() {
        let app = launch(fixture: true)
        app.tabBars.buttons["Progress"].tap(); enable(app)
        let calories = app.staticTexts["432.0 kcal"].firstMatch
        reveal(app, calories)
        XCTAssertTrue(calories.waitForExistence(timeout: 5))
        app.swipeUp()
        let trendShot = XCTAttachment(screenshot: app.screenshot());trendShot.name = "Linked workout weekly calorie trend";trendShot.lifetime = .keepAlways;add(trendShot)
        let recovery = app.staticTexts["Recovery context"]
        reveal(app, recovery)
        XCTAssertTrue(app.staticTexts["58.0 bpm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["54.0 ms"].exists)
        let weeklyShot = XCTAttachment(screenshot: app.screenshot());weeklyShot.name = "Private weekly Health insights";weeklyShot.lifetime = .keepAlways;add(weeklyShot)
        app.tabBars.buttons["Journal"].tap()
        let unlinked = app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Unlinked fixture session")).firstMatch
        reveal(app, unlinked);unlinked.tap()
        XCTAssertFalse(app.buttons["viewSessionHealthInsights"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["healthEffortCard"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        let linked = app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Health fixture session")).firstMatch
        reveal(app, linked);linked.tap()
        let effort = app.staticTexts["Climb effort estimate"].firstMatch
        reveal(app, effort)
        XCTAssertTrue(effort.waitForExistence(timeout: 10))
        let ring = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value == %@", "Climb effort estimate", "5.7 out of 10")).firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        reveal(app, ring)
        let effortShot = XCTAttachment(screenshot: app.screenshot());effortShot.name = "Transparent app effort estimate";effortShot.lifetime = .keepAlways;add(effortShot)
        let heart = app.staticTexts["Heart rate"].firstMatch
        reveal(app, heart)
        XCTAssertTrue(app.staticTexts["Average: 144 bpm"].exists)
        XCTAssertTrue(app.staticTexts["Maximum: 176 bpm"].exists)
        app.swipeUp()
        let sessionShot = XCTAttachment(screenshot: app.screenshot());sessionShot.name = "Linked workout heart-rate card";sessionShot.lifetime = .keepAlways;add(sessionShot)
    }
    @MainActor func testEmptyReadsAtAccessibilityTextSizeDoNotInventMetrics() {
        let app = launch(fixture: true, empty: true, large: true)
        app.tabBars.buttons["Progress"].tap(); enable(app)
        let message = app.staticTexts["healthInsightsMessage"]
        reveal(app, message)
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(message.label.contains("No accessible data found"))
        XCTAssertFalse(app.staticTexts["5.7"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot());shot.name = "Empty Health reads at accessibility XXXL";shot.lifetime = .keepAlways;add(shot)
    }
}
