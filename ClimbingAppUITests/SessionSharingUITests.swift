import XCTest

/// Sharing from the session editor. The audit social sample stands in for a signed-in Friends account; nothing reaches a server.
@MainActor final class SessionSharingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ screen: String, signedIn: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--accessibility-audit", screen] + (signedIn ? ["--audit-social-sample"] : [])
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Journal"].waitForExistence(timeout: 15))
        return app
    }
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<10 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.isHittable, element.debugDescription)
    }
    private func shows(_ picker: XCUIElement, _ value: String) -> Bool { (picker.value as? String) == value || picker.label.contains(value) }
    private func openSessionMenu(_ app: XCUIApplication) {
        let menu = app.buttons["Session options"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
    }
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    func testStartFormShowsVisibilityUnderGymDefaultingToFriendsOnlyWhenSignedIn() {
        var app = launch("home")
        app.buttons["startSession"].tap()
        let picker = app.buttons["sessionVisibility"], gym = app.buttons["gymPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(shows(picker, "Friends"), picker.debugDescription)
        XCTAssertGreaterThan(picker.frame.minY, gym.frame.maxY - 1)
        snapshot(app, "Start session with visibility")
        app.terminate()

        app = launch("home", signedIn: false)
        app.buttons["startSession"].tap()
        XCTAssertTrue(app.buttons["saveSession"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["sessionVisibility"].exists)
    }

    func testPastSessionSavesTheChosenVisibility() {
        let app = launch("home")
        app.buttons["pastSession"].tap()
        let picker = app.buttons["sessionVisibility"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(shows(picker, "Friends"), picker.debugDescription)
        app.buttons["gymPicker"].tap(); app.buttons["No gym / other location"].tap()
        let location = app.textFields["sessionLocation"]
        XCTAssertTrue(location.waitForExistence(timeout: 5)); location.tap(); location.typeText("Sharing recap")
        picker.tap(); app.buttons["Public"].tap()
        XCTAssertTrue(shows(picker, "Public"), picker.debugDescription)
        snapshot(app, "Past session with visibility")
        app.buttons["saveSession"].tap()
        XCTAssertTrue(app.buttons["saveRecap"].waitForExistence(timeout: 5))
        app.navigationBars["Recalled activity"].buttons["Cancel"].tap()
        let row = app.staticTexts["Sharing recap"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        openSessionMenu(app); app.buttons["Edit session"].tap()
        let saved = app.buttons["sessionVisibility"]
        reveal(app, saved)
        XCTAssertTrue(shows(saved, "Public"), saved.debugDescription)
    }

    func testSessionMenuHasOnlyEditAndDelete() {
        let app = launch("session")
        openSessionMenu(app)
        XCTAssertTrue(app.buttons["Edit session"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete session"].exists)
        XCTAssertFalse(app.buttons["Share / privacy"].exists)
        let items = app.collectionViews.firstMatch.buttons.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(items, ["Edit session", "Delete session"])
        snapshot(app, "Session options menu")
    }

    func testEditSessionHasFriendsAndAMediaRowPerClimb() {
        let app = launch("session")
        openSessionMenu(app); app.buttons["Edit session"].tap()
        XCTAssertTrue(app.navigationBars["Edit session"].waitForExistence(timeout: 5))
        let caption = app.textFields["shareCaption"]
        reveal(app, caption)
        XCTAssertTrue(shows(app.buttons["sessionVisibility"], "Friends"))
        for toggle in ["Attempts", "Sends", "Recorded duration", "Share photos"] { reveal(app, app.switches[toggle]) }
        snapshot(app, "Edit session Friends section")
        let rows = app.buttons.matching(identifier: "climbMedia")
        reveal(app, rows.firstMatch)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows.firstMatch.label.contains("Yellow slab"), rows.firstMatch.label)
        snapshot(app, "Edit session Photos and videos")
        rows.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit climb"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveClimb"].exists)
    }
}
