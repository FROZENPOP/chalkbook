import XCTest

final class GymFeatureUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data"]
        let bundle = Bundle(for: Self.self)
        for (key, name, ext) in [("CLIMB_TEST_PHOTO", "route-photo", "png"), ("CLIMB_TEST_VIDEO", "route-video", "mov")] {
            let url = bundle.url(forResource: name, withExtension: ext) ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
            if let url, let data = try? Data(contentsOf: url) { app.launchEnvironment[key] = data.base64EncodedString() }
        }
        app.launch()
        XCTAssertTrue(app.buttons["startSession"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func addGym(_ app: XCUIApplication, name: String, custom: Bool) {
        app.buttons["gymPicker"].tap()
        app.buttons["Add a new gym…"].tap()
        let nameField = app.textFields["gymName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap(); nameField.typeText(name + "\n")
        if custom {
            app.buttons["gymScale"].tap()
            app.buttons["Custom scale"].firstMatch.tap()
            let scale = app.textFields["customScaleName"]
            for _ in 0..<4 { if scale.isHittable { break }; app.swipeUp() }
            scale.tap(); scale.typeText("Color circuits")
            let order = app.descendants(matching: .any)["customGradeOrder"].firstMatch
            order.tap(); order.typeText("Green, Blue, Red")
        }
        app.buttons["saveGym"].tap()
        XCTAssertTrue(app.buttons["gymPicker"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCustomGymAutoselectManualGradeAndAddAnotherGym() {
        let app = launch()
        app.buttons["startSession"].tap()
        addGym(app, name: "Circuit Works", custom: true)
        XCTAssertTrue(app.staticTexts["Circuit Works"].exists)
        app.buttons["saveSession"].tap()
        app.buttons["resumeSession"].tap()
        app.buttons["addClimb"].tap()
        XCTAssertTrue(app.staticTexts["Circuit Works"].exists)
        let grade = app.textFields["customGrade"]
        XCTAssertTrue(grade.waitForExistence(timeout: 5))
        XCTAssertEqual(grade.value as? String, "Green")
        grade.tap()
        grade.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "Circuit 3+")
        app.buttons["saveClimb"].tap()
        XCTAssertTrue(app.staticTexts["Circuit 3+"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Circuit Works · Color circuits"].exists)
        app.buttons["addClimb"].tap()
        addGym(app, name: "Sloper Studio", custom: false)
        XCTAssertTrue(app.staticTexts["Sloper Studio"].exists)
        XCTAssertFalse(app.textFields["customGrade"].exists)
        app.buttons["saveClimb"].tap()
        XCTAssertTrue(app.staticTexts["Sloper Studio"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["resumeSession"].tap()
        XCTAssertTrue(app.staticTexts["Circuit 3+"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAccountPortalExplainsPendingProviderSetup() {
        let app = launch()
        app.buttons["openSettings"].tap()
        app.buttons["openLogin"].tap()
        let setup = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Account setup is still being completed")).firstMatch
        for _ in 0..<3 { if setup.isHittable { break }; app.scrollViews.firstMatch.swipeUp() }
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Login portal visual check"; before.lifetime = .keepAlways; add(before)
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        XCTAssertTrue(setup.waitForExistence(timeout: 10))
        app.scrollViews.firstMatch.swipeDown()
        XCTAssertFalse(app.buttons["Sign in with Apple"].isEnabled)
        XCTAssertFalse(app.buttons["Sign in"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Apple and Google login portal"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["openLogin"].exists)
    }

    @MainActor
    func testRouteMediaPickerAvailable() {
        let app = launch()
        app.buttons["startSession"].tap()
        app.buttons["saveSession"].tap()
        app.buttons["resumeSession"].tap()
        app.buttons["addClimb"].tap()
        let media = app.buttons["addRouteMedia"]
        for _ in 0..<8 { if media.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(media.isHittable)
        media.tap()
        let cancelButtons = app.buttons.matching(NSPredicate(format: "label == 'Cancel'"))
        XCTAssertTrue(cancelButtons.firstMatch.waitForExistence(timeout: 10))
        guard let cancel = cancelButtons.allElementsBoundByIndex.last(where: { $0.isHittable }) else {
            XCTFail("The photo picker should have a usable Cancel button"); return
        }
        cancel.tap()
        let files = app.buttons["addRouteMediaFromFiles"]
        for _ in 0..<8 { if files.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(files.isHittable)
        files.tap()
        let browse = app.buttons.matching(NSPredicate(format: "label == 'Browse' OR label == 'Recents' OR label == 'On My iPhone'")).firstMatch
        _ = browse.waitForExistence(timeout: 10)
        XCTAssertTrue(app.buttons["Browse"].waitForExistence(timeout: 10))
        if app.buttons["Browse"].exists { app.buttons["Browse"].tap() }
        // The app's chooser is open. Clean up without depending on the system
        // document browser's changing Cancel accessibility representation.
        app.terminate()
    }

    @MainActor
    private func chooseRouteFile(_ app: XCUIApplication, name: String) {
        let files = app.buttons["addRouteMediaFromFiles"]
        for _ in 0..<8 { if files.isHittable { break }; app.swipeUp() }
        files.tap()
        let item = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        if !item.isHittable {
            if app.buttons["Browse"].waitForExistence(timeout: 5) { app.buttons["Browse"].tap() }
            let phone = app.staticTexts["On My iPhone"]
            if phone.waitForExistence(timeout: 5) { phone.tap() }
            let folder = app.staticTexts["Climb Log"]
            if folder.waitForExistence(timeout: 3) { folder.tap() }
        }
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        let open = app.buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
    }

    @MainActor
    func testPhotoAndVideoAttachmentsFromFilesPersist() {
        let app = launch()
        app.buttons["startSession"].tap()
        app.buttons["saveSession"].tap()
        app.buttons["resumeSession"].tap()
        app.buttons["addClimb"].tap()
        chooseRouteFile(app, name: "route-photo")
        XCTAssertTrue(app.buttons["View route photo"].waitForExistence(timeout: 10))
        chooseRouteFile(app, name: "route-video")
        XCTAssertTrue(app.buttons["Play route video"].waitForExistence(timeout: 10))
        app.buttons["saveClimb"].tap()
        XCTAssertTrue(app.buttons["View route photo"].waitForExistence(timeout: 5))
        app.buttons["View route photo"].tap()
        XCTAssertTrue(app.images["Route photo"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["Play route video"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["resumeSession"].tap()
        XCTAssertTrue(app.buttons["View route photo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Play route video"].exists)
    }
}
