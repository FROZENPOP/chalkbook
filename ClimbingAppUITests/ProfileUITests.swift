import XCTest

final class ProfileUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    @MainActor func testPrivacyPolicyOpensFromSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--reset-test-data"]
        app.launch()
        XCTAssertTrue(app.profileButton.waitForExistence(timeout:15))
        app.profileButton.tap()
        let link = app.buttons["privacyPolicy"]
        for _ in 0..<6 { if link.exists && link.isHittable { break };app.swipeUp() }
        link.tap()
        XCTAssertTrue(app.webViews.staticTexts["The short version"].waitForExistence(timeout:10))
        XCTAssertTrue(app.webViews.staticTexts["Keeping and deleting your data"].exists)
    }
    @MainActor func testProfileNameBioPhotoEditAndRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--reset-test-data"]
        let bundle = Bundle(for:Self.self)
        let fixture = try XCTUnwrap(bundle.url(forResource:"route-photo",withExtension:"png") ?? bundle.url(forResource:"route-photo",withExtension:"png",subdirectory:"Fixtures"))
        app.launchEnvironment["CLIMB_TEST_PHOTO"] = try Data(contentsOf:fixture).base64EncodedString()
        app.launch()
        XCTAssertTrue(app.profileButton.waitForExistence(timeout:15))
        app.profileButton.tap();app.buttons["editProfile"].tap()
        let name = app.textFields["profileName"]
        XCTAssertTrue(name.waitForExistence(timeout:5));name.tap();name.typeText("Test climber")
        let bio = app.descendants(matching:.any)["profileBio"].firstMatch
        bio.tap();bio.typeText("Working on footwork")
        let files = app.buttons["profilePhotoFromFiles"]
        for _ in 0..<5 { if files.isHittable { break };app.swipeDown() }
        files.tap()
        let photo = app.cells.matching(NSPredicate(format:"label BEGINSWITH %@","route-photo")).firstMatch
        if !photo.isHittable {
            if app.buttons["Browse"].waitForExistence(timeout:5) { app.buttons["Browse"].tap() }
            if app.staticTexts["On My iPhone"].waitForExistence(timeout:5) { app.staticTexts["On My iPhone"].tap() }
            if app.staticTexts["Sendr"].waitForExistence(timeout:5) { app.staticTexts["Sendr"].tap() }
        }
        XCTAssertTrue(photo.waitForExistence(timeout:10));photo.tap()
        if app.buttons["Open"].waitForExistence(timeout:2) { app.buttons["Open"].tap() }
        XCTAssertTrue(app.buttons["removeProfilePhoto"].waitForExistence(timeout:10))
        app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.staticTexts["Test climber"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Working on footwork"].exists)
        app.terminate();app.launchArguments = ["--ui-testing"];app.launch()
        app.profileButton.tap()
        XCTAssertTrue(app.staticTexts["Test climber"].waitForExistence(timeout:5))
        app.buttons["editProfile"].tap()
        let editName = app.textFields["profileName"]
        editName.tap();editName.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:12)+"Updated climber")
        let remove = app.buttons["removeProfilePhoto"]
        for _ in 0..<5 { if remove.isHittable { break };app.swipeDown() }
        remove.tap();app.buttons["saveProfile"].tap()
        XCTAssertTrue(app.staticTexts["Updated climber"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["signOut"].exists, "Guest profiles must not show sign out")
    }
}
