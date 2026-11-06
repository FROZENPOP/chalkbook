import XCTest

/// App Review launch fixes, checked on the DEBUG audit fixtures (no real accounts or network).
@MainActor final class LaunchFixesUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ screen: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--accessibility-audit", screen] + extra
        app.launch()
        return app
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    func testPostMenuOffersBlockWithConfirmation() {
        let app = launch("friends", ["--audit-social-sample"])
        XCTAssertTrue(app.staticTexts["Alex Rivera"].waitForExistence(timeout: 15))
        let options = app.buttons["postOptions"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 5)); reveal(options, in: app); options.tap()
        let block = app.buttons["Block climber"].firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 5), "A stranger's post can be blocked from its menu")
        XCTAssertTrue(app.buttons["Report post"].exists)
        shoot(app, "Post menu")
        block.tap()
        XCTAssertTrue(app.staticTexts["Block this climber?"].waitForExistence(timeout: 5), "Blocking asks first")
        XCTAssertTrue(app.buttons["Block climber"].firstMatch.exists)
        shoot(app, "Block confirmation")
    }

    func testOpeningShareClearsAnEarlierPhotoNotice() {
        let app = launch("share", ["--test-stale-photo-notice"])
        XCTAssertTrue(app.textFields["Separate public caption"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.alerts["Shared"].waitForExistence(timeout: 3), "A notice from an earlier share must not pop up")
        shoot(app, "Share opens without a stale notice")
    }

    func testSettingsHasContactSupportLink() {
        let app = launch("settings")
        let support = app.descendants(matching: .any)["contactSupport"].firstMatch // a Link may not be a button
        for _ in 0..<6 where !support.isHittable { app.swipeUp() }
        XCTAssertTrue(support.waitForExistence(timeout: 5))
        XCTAssertTrue(support.isHittable)
        XCTAssertEqual(support.label, "Contact support")
        XCTAssertEqual(support.value as? String, "chalkbook.support@gmail.com")
        XCTAssertGreaterThanOrEqual(support.frame.height, 44)
        shoot(app, "Settings contact support")
    }

    /// Scrolls a short way at a time so a post's controls end up clear of the tab bar.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !(element.isHittable && element.frame.maxY < app.frame.maxY - 120) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        }
    }
}
