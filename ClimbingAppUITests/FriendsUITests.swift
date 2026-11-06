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

    @MainActor private func launchSocialSample(_ extra:[String]=[]) -> XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--ui-testing","--reset-test-data","--accessibility-audit","friends","--audit-social-sample"]+extra
        app.launch();XCTAssertTrue(app.staticTexts["Alex Rivera"].waitForExistence(timeout:15))
        return app
    }

    @MainActor func testPostHidesMissingDurationAndCommentsCanBeAddedAndDeleted() {
        continueAfterFailure=false
        let app=launchSocialSample()
        XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS '1h 35m'")).firstMatch.exists)
        reveal(app.buttons["commentPreview"].firstMatch,in:app)
        XCTAssertTrue(app.buttons["commentPreview"].firstMatch.label.contains("What was the beta on the top move?"),"Recent comments show on the post")
        for _ in 0..<4 { if app.staticTexts["Sam Okafor"].exists { break };app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Quick board session after work."].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["Duration not recorded"].exists)
        for _ in 0..<4 { if app.staticTexts["Finally sent the blue slab project!"].isHittable { break };app.swipeDown() }
        let open=app.buttons["Comments, 2"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout:5));reveal(open,in:app);open.tap()
        XCTAssertTrue(app.staticTexts["What was the beta on the top move?"].waitForExistence(timeout:5))
        let send=app.buttons["postComment"]
        XCTAssertFalse(send.isEnabled,"An empty comment can't be posted")
        let field=app.textFields["commentField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout:5));field.tap();field.typeText("Send it again")
        send.tap()
        XCTAssertTrue(app.staticTexts["Send it again"].waitForExistence(timeout:5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["Comments, 3"].firstMatch.waitForExistence(timeout:5))
        reveal(app.buttons["Comments, 3"].firstMatch,in:app)
        XCTAssertTrue(app.buttons["commentPreview"].firstMatch.label.contains("Send it again"),"A new comment appears on the post")
        XCTAssertTrue(app.buttons["commentPreview"].firstMatch.label.contains("View all 3 comments"))
        app.buttons["Comments, 3"].firstMatch.tap()
        let options=app.buttons.matching(identifier:"commentOptions").element(boundBy:2)
        XCTAssertTrue(options.waitForExistence(timeout:5));options.tap()
        XCTAssertFalse(app.buttons["Block climber"].exists,"You can't block yourself")
        app.buttons["Delete comment"].firstMatch.tap()
        let confirm=app.sheets.buttons["Delete comment"].firstMatch
        if confirm.waitForExistence(timeout:3) { confirm.tap() } else { app.buttons["Delete comment"].firstMatch.tap() }
        let gone=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:app.staticTexts["Send it again"])
        XCTAssertEqual(XCTWaiter.wait(for:[gone],timeout:5),.completed)
    }

    @MainActor func testCommentsAndPostsCanEachBeReported() {
        continueAfterFailure=false
        let app=launchSocialSample()
        let options=app.buttons["postOptions"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout:5));reveal(options,in:app);options.tap()
        app.buttons["Report post"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Report post"].waitForExistence(timeout:5))
        app.navigationBars.buttons.firstMatch.tap()
        let open=app.buttons.matching(identifier:"openComments").firstMatch
        XCTAssertTrue(open.waitForExistence(timeout:5));reveal(open,in:app);open.tap()
        let comment=app.buttons.matching(identifier:"commentOptions").firstMatch
        XCTAssertTrue(comment.waitForExistence(timeout:5));comment.tap()
        app.buttons["Report comment"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Report comment"].waitForExistence(timeout:5))
    }

    /// Scrolls a short way at a time so a post's controls end up clear of the tab bar.
    @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication) {
        for _ in 0..<8 where !(element.isHittable && element.frame.maxY < app.frame.maxY-120) {
            app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.7)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.45)))
        }
    }

    @MainActor func testPostShowsItsPhotoAndOpensThemAll() {
        continueAfterFailure=false
        let app=launchSocialSample()
        let photo=app.buttons["viewSharedRoutePhotos"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout:5))
        XCTAssertEqual(photo.label,"View 3 climb photos")
        reveal(photo,in:app);photo.tap()
        XCTAssertTrue(app.staticTexts["Route photo 3"].waitForExistence(timeout:5))
    }

    @MainActor func testFailedCommentKeepsTheDraft() {
        continueAfterFailure=false
        let app=launchSocialSample(["--test-comment-error"])
        let open=app.buttons["Comments, 2"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout:5));reveal(open,in:app);open.tap()
        let field=app.textFields["commentField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout:5));field.tap();field.typeText("Keep this draft")
        app.buttons["postComment"].tap()
        XCTAssertTrue(app.staticTexts["commentError"].waitForExistence(timeout:5))
        XCTAssertEqual(field.value as? String,"Keep this draft")
    }

    @MainActor func testRequestsShowAcceptDeclineAndSentState() {
        continueAfterFailure=false
        let app=launchSocialSample()
        app.buttons["Requests (2)"].tap()
        XCTAssertTrue(app.staticTexts["Jordan Lee"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["Accept"].exists);XCTAssertTrue(app.buttons["Decline"].exists)
        XCTAssertTrue(app.staticTexts["Priya Varma"].exists);XCTAssertTrue(app.staticTexts["Request sent"].exists)
    }
}
