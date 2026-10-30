import XCTest

final class FriendsUITests: XCTestCase {
    @MainActor func testPendingRemovalIndicatorAndManualRetryAtLargeText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--test-removal-outbox", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["Friends"].waitForExistence(timeout: 15)); app.tabBars.buttons["Friends"].tap()
        XCTAssertTrue(app.staticTexts["1 removal waiting to sync"].waitForExistence(timeout: 10))
        let retry = app.buttons["retryRemovals"]
        for _ in 0..<8 { if retry.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(retry.isHittable, app.debugDescription); XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Pending removal at large text"; shot.lifetime = .keepAlways; add(shot)
        retry.tap()
        XCTAssertTrue(app.staticTexts["removalsSynced"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["retryRemovals"].exists)
    }

    @MainActor func testFeedAutomaticallyPagesAndRetriesWithoutLosingFirstPage() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--reset-test-data","--test-friend-feed","--test-feed-error"]
        app.launch();XCTAssertTrue(app.tabBars.buttons["Friends"].waitForExistence(timeout:15));app.tabBars.buttons["Friends"].tap()
        XCTAssertTrue(app.staticTexts["Fixture recap 1"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["Page requests: 1"].exists,"Only the first page should load before scrolling")
        let retry=app.buttons["retryFriendsFeed"]
        for _ in 0..<25 { if retry.isHittable { break };app.swipeUp() }
        XCTAssertTrue(retry.waitForExistence(timeout:10));XCTAssertTrue(retry.isHittable)
        XCTAssertFalse(app.staticTexts["Fixture recap 23"].exists)
        let errorShot=XCTAttachment(screenshot:app.screenshot());errorShot.name="Feed page error retains loaded activity";errorShot.lifetime = .keepAlways;add(errorShot)
        retry.tap()
        let end=app.descendants(matching:.any)["friendsFeedEnd"].firstMatch
        for _ in 0..<10 { if end.isHittable { break };app.swipeUp() }
        XCTAssertTrue(end.waitForExistence(timeout:10));XCTAssertTrue(end.isHittable)
        XCTAssertTrue(app.staticTexts["Fixture recap 23"].exists)
        let endShot=XCTAttachment(screenshot:app.screenshot());endShot.name="End of friends feed";endShot.lifetime = .keepAlways;add(endShot)
        for _ in 0..<25 { if app.staticTexts["Fixture recap 1"].isHittable { break };app.swipeDown() }
        XCTAssertTrue(app.staticTexts["Fixture recap 1"].exists,"Failed page must not remove the first page")
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Paged friends feed";shot.lifetime = .keepAlways;add(shot)
    }
    @MainActor func testEmptyFeedKeepsExistingEmptyStateAtLargeText() {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--reset-test-data","--test-friend-feed","--test-empty-feed","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch();XCTAssertTrue(app.tabBars.buttons["Friends"].waitForExistence(timeout:15));app.tabBars.buttons["Friends"].tap()
        XCTAssertTrue(app.staticTexts["A little encouragement goes a long way."].waitForExistence(timeout:10))
        XCTAssertFalse(app.descendants(matching:.any)["friendsFeedEnd"].firstMatch.exists)
        XCTAssertFalse(app.buttons["retryFriendsFeed"].exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Empty feed at accessibility text size";shot.lifetime = .keepAlways;add(shot)
    }
    @MainActor func testSuggestedFriendsAddDismissAndInlineRetryAtLargeText() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--ui-testing","--reset-test-data","--test-friend-suggestions","--test-suggestion-error","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch();XCTAssertTrue(app.tabBars.buttons["Friends"].waitForExistence(timeout:15));app.tabBars.buttons["Friends"].tap()
        let addButton=app.buttons["suggestionAdd-00000000-0000-0000-0000-000000000003"]
        func reveal(_ element:XCUIElement) {
            for _ in 0..<12 { if element.isHittable { return };app.swipeUp() }
        }
        reveal(addButton);XCTAssertTrue(addButton.waitForExistence(timeout:10),app.debugDescription);addButton.tap()
        let retry=app.buttons["Retry for Alex Boulder"]
        XCTAssertTrue(retry.waitForExistence(timeout:10));reveal(retry);retry.tap()
        let sent=NSPredicate(format:"label == %@","Request sent to Alex Boulder")
        expectation(for:sent,evaluatedWith:addButton);waitForExpectations(timeout:10)
        XCTAssertFalse(addButton.isEnabled)
        XCTAssertGreaterThanOrEqual(addButton.frame.height,44)
        XCTAssertLessThan(addButton.frame.height,140,"Sent must stay readable rather than wrapping letter by letter")
        let dismiss=app.buttons["suggestionDismiss-00000000-0000-0000-0000-000000000004"]
        reveal(dismiss);dismiss.tap()
        let removed=NSPredicate(format:"exists == false")
        expectation(for:removed,evaluatedWith:dismiss);waitForExpectations(timeout:10)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Suggested friends at large text";shot.lifetime = .keepAlways;add(shot)
    }
    @MainActor func testEmptySuggestionsHaveNoSection() {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--reset-test-data","--test-friend-suggestions","--test-empty-suggestions"]
        app.launch();XCTAssertTrue(app.tabBars.buttons["Friends"].waitForExistence(timeout:15));app.tabBars.buttons["Friends"].tap()
        XCTAssertTrue(app.staticTexts["Activity"].waitForExistence(timeout:10))
        XCTAssertFalse(app.staticTexts["Suggested friends"].exists)
    }

    @MainActor func testSearchInputClearAndRetryAtLargeText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--test-friend-search", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Friends"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Friends"].tap()
        let field = app.textFields["friendSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for _ in 0..<4 { if field.isHittable { break }; app.swipeUp() }
        field.tap(); field.typeText("@climb_buddy\n")
        // The isolated test has no backend: it must offer retry, keep input, and never manufacture people.
        XCTAssertTrue(app.staticTexts["Search couldn’t connect."].waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, "@climb_buddy")
        app.buttons["clearFriendSearch"].tap()
        XCTAssertTrue(app.staticTexts["Search a name or username to find a friend."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["clearFriendSearch"].exists)
        XCTAssertFalse(app.buttons["Add friend"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Add friends search at accessibility text size"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testUnconfiguredFriendsIsHonestAndJournalRemainsAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Friends"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Friends"].tap()
        XCTAssertTrue(app.staticTexts["Friends is coming next"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add friend"].exists)
        app.tabBars.buttons["Journal"].tap()
        XCTAssertTrue(app.buttons["startSession"].waitForExistence(timeout: 10), app.debugDescription)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Journal remains available with Friends unconfigured"; shot.lifetime = .keepAlways
        add(shot)
    }
}
