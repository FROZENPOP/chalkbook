import XCTest

/// Paced walkthroughs of the DEBUG screenshot demo (fake people, fake climbs), one per README GIF.
/// `scripts/record_readme_gifs.sh` records the simulator while each runs; they also pass on their own.
final class ReadmeDemoUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Set by the record script (as TEST_RUNNER_README_DEMO_MARKERS) to start and stop the recording around the flow.
    private let markers = ProcessInfo.processInfo.environment["README_DEMO_MARKERS"].map { URL(fileURLWithPath: $0) }
    private let media = ProcessInfo.processInfo.environment["CHALKBOOK_DEMO_MEDIA"]
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "marketing/demo-media").path

    @MainActor private func launch(tab: Int, ready: XCUIElement? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--screenshot-demo", "--start-tab", "\(tab)"]
        app.launchEnvironment["CHALKBOOK_DEMO_MEDIA"] = media
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        if let ready { XCTAssertTrue(ready.waitForExistence(timeout: 10)) }
        pause(1.5) // seeding, photo decoding and highlighting settle before the recording starts
        return app
    }

    /// Tells the recorder the screen is ready and waits until it is recording.
    private func cue(_ name: String) {
        guard let markers else { return }
        FileManager.default.createFile(atPath: markers.appending(path: "\(name).ready").path, contents: nil)
        let go = markers.appending(path: "\(name).go").path
        let deadline = Date.now.addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: go) {
            XCTAssertLessThan(Date.now, deadline, "recorder never started")
            pause(0.1)
        }
        pause(0.6) // covered by the GIF's half-second trim
    }
    private func end(_ name: String) {
        pause(0.6)
        guard let markers else { return }
        FileManager.default.createFile(atPath: markers.appending(path: "\(name).done").path, contents: nil)
    }
    private func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    /// A slow drag rather than a flick, so the scroll reads smoothly in the GIF. Positive `by` scrolls down.
    @MainActor private func scroll(_ app: XCUIApplication, by fraction: Double) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fraction > 0 ? 0.72 : 0.3))
        let to = from.withOffset(CGVector(dx: 0, dy: -fraction * app.frame.height))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: 600, thenHoldForDuration: 0.25)
    }
    // Taps without a separate existence wait (tap fails if the element is missing), and screens are checked
    // after end(), so query time stays out of the recording.

    /// Journal: open the most recent session and scroll through its climbs.
    @MainActor func testJournalSession() {
        let app = launch(tab: 0, ready: element("browseHistory"))
        cue("journal")
        pause(0.4)
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'climbs sent'")).firstMatch.tap()
        pause(0.8)
        scroll(app, by: 0.35); pause(0.2)
        scroll(app, by: 0.35)
        end("journal")
        XCTAssertTrue(app.staticTexts["Your climbs"].exists)
    }

    /// Projects: browse the active projects and their route photos, then open one.
    @MainActor func testProjects() {
        let app = launch(tab: 1, ready: element("projectStatusFilter"))
        cue("projects")
        pause(0.4)
        scroll(app, by: 0.3); pause(0.3)
        // The second card is fully on screen after the scroll, so the tap needs no automatic scroll.
        app.buttons.matching(NSPredicate(format: "label CONTAINS ' · Active'")).element(boundBy: 1).tap()
        // The detail redraws the highlighted photo; hold until it replaces the "Opening photo…" spinner.
        // Polled by hand: an XCTNSPredicateExpectation checks only once a second.
        let opening = app.activityIndicators.matching(NSPredicate(format: "label CONTAINS 'Opening photo'")).firstMatch
        let deadline = Date.now.addingTimeInterval(10)
        while opening.exists { XCTAssertLessThan(Date.now, deadline, "route photo never loaded"); pause(0.1) }
        pause(0.8)
        scroll(app, by: 0.35)
        end("projects")
        XCTAssertTrue(app.buttons["tryProject"].exists)
    }

    /// Progress: the consistency calendar, then Stats across each time range.
    @MainActor func testProgress() {
        let app = launch(tab: 2, ready: element("openStats"))
        cue("progress")
        pause(0.8)
        app.buttons["openStats"].tap()
        pause(0.5)
        app.segmentedControls.buttons["90 days"].tap()
        pause(0.6)
        app.segmentedControls.buttons["All time"].tap()
        pause(0.5)
        scroll(app, by: 0.3)
        end("progress")
        XCTAssertTrue(app.navigationBars["Stats"].exists)
    }

    /// Friends: scroll the activity feed and open a post.
    @MainActor func testFriends() {
        let app = launch(tab: 3, ready: element("openComments"))
        cue("friends")
        pause(0.4)
        scroll(app, by: 0.35); pause(0.2)
        scroll(app, by: 0.35); pause(0.2)
        // Theo's post (three comments) is on screen after two scrolls; opening it avoids an automatic scroll.
        app.buttons.matching(NSPredicate(format: "identifier == 'openComments' AND label == 'Comments, 3'")).firstMatch.tap()
        pause(0.8)
        scroll(app, by: 0.3)
        end("friends")
        XCTAssertTrue(app.navigationBars["Comments"].exists)
    }

    @MainActor private func element(_ identifier: String) -> XCUIElement {
        XCUIApplication().descendants(matching: .any)[identifier].firstMatch
    }
}
