import XCTest

@MainActor final class WelcomeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testFirstLaunchOffersAppleGoogleAndGuest() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--show-welcome"]
        app.launch()
        let guest = app.buttons["continueAsGuest"]
        XCTAssertTrue(guest.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["appleLogin"].exists || app.staticTexts["appleSetupMessage"].exists)
        XCTAssertTrue(app.buttons["googleLogin"].exists || app.staticTexts["googleSetupMessage"].exists)
        XCTAssertFalse(app.tabBars.buttons["Journal"].exists, "The welcome replaces the app until a choice is made")
        try app.performAccessibilityAudit { issue in
            print("AX-AUDIT [welcome] \(issue.compactDescription) element=\(issue.element?.label ?? "unavailable")"); return false
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Welcome"; shot.lifetime = .keepAlways; add(shot)

        guest.tap()
        XCTAssertTrue(app.tabBars.buttons["Journal"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Friends"].tap()
        XCTAssertTrue(app.buttons["Sign in to find friends"].waitForExistence(timeout: 5) || app.staticTexts["Friends is coming next"].exists)
        app.tabBars.buttons["Journal"].tap()
        app.profileButton.tap()
        XCTAssertTrue(app.buttons["openLogin"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You’re using Chalkbook as a guest"].exists)
    }
}
