import XCTest

final class ProjectNotebookUITests:XCTestCase {
    override func setUp() { continueAfterFailure=false }
    @MainActor private func tap(_ app:XCUIApplication,_ id:String) {
        let button=app.buttons[id].firstMatch
        if id == "highlightHolds" {
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["saveHoldHighlight"])
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            // tap waits for app quiescence; querying isHittable during sheet dismissal can throw.
            button.tap()
            return
        }
        for _ in 0..<10 { if button.isHittable { break };app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout:5),id);button.tap()
    }
    @MainActor func testPhotoMarkupAndPinnedNextMovePersistAndAppearWhileLogging() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--reset-test-data"]
        let bundle=Bundle(for:Self.self)
        let url=try XCTUnwrap(bundle.url(forResource:"route-photo",withExtension:"png") ?? bundle.url(forResource:"route-photo",withExtension:"png",subdirectory:"Fixtures"))
        app.launchEnvironment["CLIMB_TEST_PHOTO"]=try Data(contentsOf:url).base64EncodedString()
        app.launch();XCTAssertTrue(app.buttons["startSession"].waitForExistence(timeout:15))
        tap(app,"startSession");tap(app,"saveSession");tap(app,"resumeSession");tap(app,"addClimb")
        tap(app,"addRouteMediaFromFiles")
        let item=app.cells.matching(NSPredicate(format:"label BEGINSWITH %@","route-photo")).firstMatch
        if !item.isHittable {
            if app.buttons["Browse"].waitForExistence(timeout:5) { app.buttons["Browse"].tap() }
            if app.staticTexts["On My iPhone"].waitForExistence(timeout:5) { app.staticTexts["On My iPhone"].tap() }
            if app.staticTexts["Climb Log"].waitForExistence(timeout:5) { app.staticTexts["Climb Log"].tap() }
        }
        XCTAssertTrue(item.waitForExistence(timeout:10));item.tap()
        if app.buttons["Open"].waitForExistence(timeout:2) { app.buttons["Open"].tap() }
        tap(app,"saveClimb");tap(app,"Notebook and complete history")
        tap(app,"Add note")
        let note=app.descendants(matching:.any)["notebookText"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout:5))
        app.switches["pinNotebookNote"].coordinate(withNormalizedOffset:CGVector(dx:0.93,dy:0.5)).tap()
        XCTAssertEqual(app.switches["pinNotebookNote"].value as? String,"1")
        note.tap();note.typeText("Left foot high");app.navigationBars.buttons["Save"].tap()
        for _ in 0..<5 { if app.staticTexts["Next move"].exists { break };app.swipeDown() }
        XCTAssertTrue(app.staticTexts["Next move"].waitForExistence(timeout:5))
        tap(app,"editNotebookNote")
        XCTAssertEqual(app.descendants(matching:.any)["notebookText"].firstMatch.value as? String,"Left foot high")
        app.navigationBars.buttons["Cancel"].tap()
        for _ in 0..<5 { if app.buttons["annotateRoutePhoto"].firstMatch.isHittable { break };app.swipeDown() }
        tap(app,"annotateRoutePhoto")
        let canvas=app.descendants(matching:.any)["routeMarkupCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout:5))
        canvas.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.4)).press(forDuration:0.1,thenDragTo:canvas.coordinate(withNormalizedOffset:CGVector(dx:0.7,dy:0.6)))
        XCTAssertTrue(app.buttons["Undo stroke"].isEnabled)
        tap(app,"saveRouteMarkup")
        app.terminate();app.launchArguments=["--ui-testing"];app.launch()
        tap(app,"resumeSession")
        XCTAssertTrue(app.staticTexts["Next move"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Left foot high"].exists)
        tap(app,"Notebook and complete history")
        tap(app,"annotateRoutePhoto")
        XCTAssertTrue(app.buttons["Undo stroke"].waitForExistence(timeout:5));XCTAssertTrue(app.buttons["Undo stroke"].isEnabled)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Restored private route markup";shot.lifetime = .keepAlways;add(shot)
    }
    @MainActor func testSharedPhotoPairKeepsOriginalAndHighlightedAvailable() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--reset-test-data","--test-shared-route-photo"]
        let bundle=Bundle(for:Self.self)
        let url=try XCTUnwrap(bundle.url(forResource:"route-photo",withExtension:"png") ?? bundle.url(forResource:"route-photo",withExtension:"png",subdirectory:"Fixtures"))
        app.launchEnvironment["CLIMB_TEST_PHOTO"]=try Data(contentsOf:url).base64EncodedString()
        app.launch();app.tabBars.buttons["Friends"].tap()
        XCTAssertTrue(app.images["sharedRoutePhoto"].waitForExistence(timeout:15))
        XCTAssertEqual(app.images["sharedRoutePhoto"].label,"Highlighted climb photo")
        app.segmentedControls["sharedPhotoComparison"].buttons["Original"].tap()
        XCTAssertEqual(app.images["sharedRoutePhoto"].label,"Original climb photo")
        let original = XCTAttachment(screenshot:app.screenshot()); original.name = "Shared original photo"; original.lifetime = .keepAlways; add(original)
        app.segmentedControls["sharedPhotoComparison"].buttons["Highlighted"].tap()
        XCTAssertEqual(app.images["sharedRoutePhoto"].label,"Highlighted climb photo")
        let highlighted = XCTAttachment(screenshot:app.screenshot()); highlighted.name = "Shared highlighted photo"; highlighted.lifetime = .keepAlways; add(highlighted)
    }
    @MainActor func testHoldHighlightSaveResetCancelAndRelaunch() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--reset-test-data"]
        let bundle=Bundle(for:Self.self)
        let url=try XCTUnwrap(bundle.url(forResource:"route-photo",withExtension:"png") ?? bundle.url(forResource:"route-photo",withExtension:"png",subdirectory:"Fixtures"))
        app.launchEnvironment["CLIMB_TEST_PHOTO"]=try Data(contentsOf:url).base64EncodedString()
        app.launch();XCTAssertTrue(app.buttons["startSession"].waitForExistence(timeout:15))
        tap(app,"startSession");tap(app,"saveSession");tap(app,"resumeSession");tap(app,"addClimb")
        tap(app,"addRouteMediaFromFiles")
        let item=app.cells.matching(NSPredicate(format:"label BEGINSWITH %@","route-photo")).firstMatch
        if !item.isHittable {
            if app.buttons["Browse"].waitForExistence(timeout:5) { app.buttons["Browse"].tap() }
            if app.staticTexts["On My iPhone"].waitForExistence(timeout:5) { app.staticTexts["On My iPhone"].tap() }
            if app.staticTexts["Climb Log"].waitForExistence(timeout:5) { app.staticTexts["Climb Log"].tap() }
        }
        XCTAssertTrue(item.waitForExistence(timeout:10));item.tap()
        if app.buttons["Open"].waitForExistence(timeout:2) { app.buttons["Open"].tap() }
        tap(app,"saveClimb");tap(app,"Notebook and complete history")
        for _ in 0..<5 { if app.buttons["View route photo"].firstMatch.isHittable { break }; app.swipeDown() }
        tap(app,"View route photo")
        XCTAssertTrue(app.otherElements["routePhotoPreview"].exists || app.images["routePhotoPreview"].exists || app.descendants(matching:.any)["routePhotoPreview"].firstMatch.exists)
        XCTAssertFalse(app.buttons["resetHoldHighlight"].exists) // Highlighting is optional after importing the photo.
        tap(app,"highlightHolds")
        let canvas = app.descendants(matching:.any)["holdHighlightCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout:10))
        canvas.coordinate(withNormalizedOffset:CGVector(dx:0.125,dy:0.4)).tap()
        XCTAssertTrue(app.staticTexts["1 hold selected"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["highlightMarker1"].exists)
        tap(app,"includeMoreHolds")
        for _ in 0..<8 { if canvas.isHittable { break }; app.swipeDown() }
        canvas.coordinate(withNormalizedOffset:CGVector(dx:0.405,dy:0.412)).tap()
        XCTAssertTrue(app.staticTexts["2 holds selected"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["highlightMarker2"].exists)
        for _ in 0..<8 { if app.segmentedControls["highlightComparison"].isHittable { break }; app.swipeUp() }
        // Segments select a temporary presentation, without changing the selection count.
        app.segmentedControls["highlightComparison"].buttons["Original"].tap()
        XCTAssertTrue(app.staticTexts["2 holds selected"].exists)
        XCTAssertEqual(canvas.value as? String,"Original photo")
        app.segmentedControls["highlightComparison"].buttons["Highlighted"].tap()
        for _ in 0..<8 { if app.buttons["highlightMarker2"].isHittable { break }; app.swipeDown() }
        app.buttons["highlightMarker2"].tap()
        XCTAssertTrue(app.staticTexts["1 hold selected"].waitForExistence(timeout:5))
        let done = app.buttons["saveHoldHighlight"]
        let enabled = NSPredicate(format:"enabled == true")
        expectation(for:enabled,evaluatedWith:done);waitForExpectations(timeout:15)
        let selectedShot = XCTAttachment(screenshot: app.screenshot())
        selectedShot.name = "Selected hold color highlight"; selectedShot.lifetime = .keepAlways; add(selectedShot)
        app.sliders["highlightTolerance"].adjust(toNormalizedSliderPosition: 0.35)
        expectation(for:enabled,evaluatedWith:done);waitForExpectations(timeout:15)
        tap(app,"saveHoldHighlight")
        let comparison=app.segmentedControls["routePhotoComparison"]
        XCTAssertTrue(comparison.waitForExistence(timeout:10))
        comparison.buttons["Original"].tap(); comparison.buttons["Highlighted"].tap()
        tap(app,"highlightHolds")
        XCTAssertTrue(app.staticTexts["1 hold selected"].waitForExistence(timeout:10))
        for _ in 0..<8 { if app.switches["enableHoldHighlight"].isHittable { break }; app.swipeUp() }
        app.switches["enableHoldHighlight"].tap()
        tap(app,"saveHoldHighlight");tap(app,"highlightHolds")
        for _ in 0..<8 { if app.switches["enableHoldHighlight"].isHittable { break }; app.swipeUp() }
        XCTAssertEqual(app.switches["enableHoldHighlight"].value as? String,"0")
        app.switches["enableHoldHighlight"].tap()
        tap(app,"resetHoldHighlight")
        XCTAssertFalse(app.buttons["highlightMarker1"].exists)
        XCTAssertTrue(app.staticTexts["No color selected"].waitForExistence(timeout:5))
        app.navigationBars.buttons["Cancel"].tap()
        tap(app,"highlightHolds")
        XCTAssertTrue(app.staticTexts["1 hold selected"].waitForExistence(timeout:10))
        app.navigationBars.buttons["Cancel"].tap()
        app.terminate(); app.launchArguments=["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-UIUserInterfaceStyle", "Dark"]; app.launch()
        tap(app,"resumeSession"); tap(app,"View route photo"); tap(app,"highlightHolds")
        XCTAssertTrue(app.staticTexts["1 hold selected"].waitForExistence(timeout:10))
        tap(app,"resetHoldHighlight")
        expectation(for:enabled,evaluatedWith:app.buttons["saveHoldHighlight"]);waitForExpectations(timeout:15)
        tap(app,"saveHoldHighlight");tap(app,"highlightHolds")
        XCTAssertTrue(app.staticTexts["No color selected"].waitForExistence(timeout:10))
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Hold highlight reset";shot.lifetime = .keepAlways;add(shot)
    }
}
