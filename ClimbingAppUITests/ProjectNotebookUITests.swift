import XCTest

final class ProjectNotebookUITests:XCTestCase {
    override func setUp() { continueAfterFailure=false }
    @MainActor private func tap(_ app:XCUIApplication,_ id:String) {
        let button=app.buttons[id].firstMatch
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
}
