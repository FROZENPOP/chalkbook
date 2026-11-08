import XCTest

/// Actual screen implementations with isolated DEBUG fixtures, never real accounts or permissions.
@MainActor final class AccessibilityAuditUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func launch(_ screen: String, darkLarge: Bool = false, empty: Bool = false, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--accessibility-audit", screen] + extra
        if screen == "share" { app.launchArguments.append("--audit-social-sample") } // Edit session's Friends section needs a (sample) account
        if empty {
            app.launchArguments.append("--audit-empty")
            if screen == "feed" { app.launchArguments.append("--test-empty-feed") }
            if screen == "suggested" { app.launchArguments.append("--test-empty-suggestions") }
        }
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", darkLarge ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        if darkLarge { app.launchArguments += ["--audit-dark", "--audit-reduce-motion"] }
        app.launch()
        let ready: XCUIElement
        switch screen {
        case "feed": ready = empty ? app.staticTexts["A little encouragement goes a long way."] : app.staticTexts["Fixture recap 1"]
        case "suggested": ready = app.staticTexts["Suggested friends"]
        case "social-profile": ready = app.staticTexts["Alex Climber"]
        case "highlight": ready = app.descendants(matching: .any)["holdHighlightCanvas"].firstMatch
        case "history": ready = app.textFields["historySearch"]
        case "session-editor": ready = app.buttons["saveSession"]
        case "climb-editor": ready = app.buttons["saveClimb"]
        case "share": ready = app.buttons["saveSession"]
        case "annotation": ready = app.descendants(matching: .any)["routeMarkupCanvas"].firstMatch
        default: ready = app.navigationBars.firstMatch
        }
        XCTAssertTrue(ready.exists || ready.waitForExistence(timeout: 15), "Screen must be ready before auditing: \(screen)")
        if screen == "share" {
            let caption = app.textFields["shareCaption"]
            for _ in 0..<8 { if caption.exists && caption.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(caption.isHittable, "Friends section must be on screen before auditing")
        }
        XCTAssertTrue(app.tabBars.buttons["Journal"].exists)
        return app
    }

    private func audit(_ app: XCUIApplication, _ screen: String, partitionProbes: Bool = false, ignoring: XCUIAccessibilityAuditType = []) {
        XCTContext.runActivity(named: "Audit \(screen)") { activity in
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = screen; shot.lifetime = .keepAlways; activity.add(shot)
            do {
                // Static checks run before font probes alter layout. Forms rebuild their
                // rows for size changes, so the two font checks can now share one probe.
                let bars = nativeBars(app)
                // XXXL on compact screens makes native OCR/contrast work expensive. Keep
                // every category, but give contrast, OCR and each font probe their own call
                // instead of sharing the native per-call time budget. Other screens retain
                // the faster grouped probes. Unknown/new static categories remain included.
                let probes: [XCUIAccessibilityAuditType] = partitionProbes
                    ? [.contrast, .elementDetection, .all.subtracting([.contrast, .elementDetection, .textClipped, .dynamicType]), .textClipped, .dynamicType]
                    : [.all.subtracting([.textClipped, .dynamicType]), [.textClipped, .dynamicType]]
                for types in probes.map({ $0.subtracting(ignoring) }) {
                    print("AX-PROBE [\(screen)] types=\(types.rawValue)")
                    try performAudit(app, types: types, screen: screen, bars: bars)
                }
            } catch { XCTFail("Accessibility audit failed on \(screen): \(error)") }
        }
    }

    private func performAudit(_ app: XCUIApplication, types: XCUIAccessibilityAuditType, screen: String, bars: [NativeBar]) throws {
        for attempt in 0...1 {
            do {
                try app.performAccessibilityAudit(for: types) { issue in
                    print("AX-AUDIT [\(screen)] type=\(issue.auditType.rawValue) \(issue.compactDescription) detail=\(issue.detailedDescription) element=\(issue.element?.label ?? "unavailable") frame=\(issue.element?.frame.debugDescription ?? "unavailable")")
                    if self.systemContrastFalsePositive(issue, viewport: app.frame, bars: bars) { return true }
                    return false // Every other finding fails, including all clipping and Dynamic Type issues.
                }
                return
            } catch {
                // A runtime timeout is not a passing audit. Retry that probe once; real
                // findings are still recorded, and a second timeout fails the test.
                let failure = error as NSError
                guard attempt == 0, failure.domain == "com.apple.xcode.xctest.accessibilityAudit", failure.code == -56 else { throw error }
                print("AX-RETRY timed-out probe on \(screen)")
            }
        }
    }

    private struct NativeBar {
        let frame: CGRect
        let title: String
        let controls: [(label: String, frame: CGRect)]
    }
    private func nativeBars(_ app: XCUIApplication) -> [NativeBar] {
        let bars = (app.navigationBars.allElementsBoundByIndex + app.tabBars.allElementsBoundByIndex)
            .filter { $0.exists && $0.isHittable }.map { bar in
                NativeBar(frame: bar.frame, title: bar.identifier,
                          controls: bar.buttons.allElementsBoundByIndex.map { ($0.label, $0.frame) })
            }
        // The comment composer uses the same translucent bar material, so scrolled text under it samples the same way.
        let send = app.buttons["postComment"], field = app.textFields["commentField"]
        guard send.exists, field.exists else { return bars }
        let composer = send.frame.union(field.frame)
        return bars + [NativeBar(frame: CGRect(x: 0, y: composer.minY - 8, width: app.frame.width, height: composer.height + 16), title: "", controls: [])]
    }
    private func systemContrastFalsePositive(_ issue: XCUIAccessibilityAuditIssue, viewport: CGRect, bars: [NativeBar]) -> Bool {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27,
              issue.auditType == .contrast, let element = issue.element else { return false }
        let frame = element.frame, label = element.label
        let isBarElement = bars.contains { bar in
            (label == bar.title && bar.frame.intersects(frame)) || bar.controls.contains { $0.label == label && $0.frame.intersects(frame) }
        }
        // iOS 27 samples cached scroll text through translucent native bars. Only the
        // specific obscured contrast element is ignored; bar titles/actions and all
        // visible content still fail. Screenshots confirm the native occlusion.
        if !isBarElement && (frame.minY < viewport.minY || frame.maxY > viewport.maxY || bars.contains(where: { $0.frame.intersects(frame) })) {
            print("AX-SUPPRESSED contrast: native-bar-occluded element \(label) at \(frame)")
            return true
        }
        return false
    }

    func testJournalHeaderReflowsAtAccessibilityXXXL() {
        let app = launch("home", darkLarge: true)
        let brand = app.descendants(matching: .any)["journalBrand"].firstMatch
        let date = app.staticTexts["journalDate"]
        XCTAssertTrue(brand.exists)
        XCTAssertTrue(date.exists)
        XCTAssertGreaterThanOrEqual(date.frame.minY, brand.frame.maxY, "The date must sit below the brand at accessibility sizes, including SE width")
        XCTAssertGreaterThanOrEqual(brand.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(brand.frame.maxX, app.frame.maxX)
        XCTAssertLessThanOrEqual(date.frame.maxX, app.frame.maxX)
        app.terminate()
    }

    func testFeedEndWrapsAtAccessibilityXXXL() {
        let regular = launch("feed")
        audit(regular, "Feed footer regular text")
        regular.terminate()
        let app = launch("feed", darkLarge: true)
        let end = app.descendants(matching: .any)["friendsFeedEnd"].firstMatch
        let tabs = app.tabBars.firstMatch
        for _ in 0..<12 {
            if end.exists && end.frame.maxY <= tabs.frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(end.exists)
        XCTAssertGreaterThan(end.frame.height, 44, "The large-text footer must grow rather than compress its wrapped label")
        XCTAssertGreaterThanOrEqual(end.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(end.frame.maxX, app.frame.maxX)
        XCTAssertLessThanOrEqual(end.frame.maxY, tabs.frame.minY, "The footer must be fully revealable above the tab bar on SE")
        app.terminate()
    }

    func testFriendsPostsRequestsAndCommentsAudit() {
        for darkLarge in [false, true] {
            let label = darkLarge ? "dark XXXL" : "light"
            let posts = launch("friends", darkLarge: darkLarge, extra: ["--audit-social-sample"])
            XCTAssertTrue(posts.staticTexts["Alex Rivera"].waitForExistence(timeout: 15))
            audit(posts, "Friends posts \(label)")
            for _ in 0..<8 { if posts.buttons["openComments"].firstMatch.isHittable { break }; posts.swipeUp() }
            // Font probes grow the tall photo post and push later posts out of the lazy feed, so they read as
            // not scaling. Those posts are the same view the unscrolled audit above checks for font scaling.
            audit(posts, "Friends post actions \(label)", ignoring: .dynamicType)
            posts.buttons["openComments"].firstMatch.tap()
            XCTAssertTrue(posts.buttons["postComment"].waitForExistence(timeout: 5))
            audit(posts, "Comments \(label)")
            posts.terminate()
            let requests = launch("friends", darkLarge: darkLarge, extra: ["--audit-social-sample"])
            XCTAssertTrue(requests.staticTexts["Alex Rivera"].waitForExistence(timeout: 15))
            let tab = requests.buttons["Requests (2)"]
            for _ in 0..<6 { if tab.isHittable { break }; requests.swipeUp() }
            tab.tap()
            XCTAssertTrue(requests.staticTexts["Jordan Lee"].waitForExistence(timeout: 5))
            audit(requests, "Friend requests \(label)")
            requests.terminate()
        }
    }

    func testJournalBaselineAudit() {
        let app = launch("home"); audit(app, "Journal light"); app.terminate()
    }
    func testMainScreensLight() {
        for screen in ["history", "session", "session-editor", "climb-editor", "projects", "progress", "progress-stats", "session-log", "gyms", "settings", "friends"] {
            for scrolled in (["session", "session-editor", "climb-editor", "progress", "session-log", "settings", "feed", "share", "annotation", "highlight"].contains(screen) ? [false, true] : [false]) {
                let app = launch(screen)
                if scrolled { app.swipeUp() }
                audit(app, "\(screen) light\(scrolled ? " scrolled" : "")"); app.terminate()
            }
        }
    }
    func testSocialAndPhotoScreensLight() {
        for screen in ["feed", "add-friends", "suggested", "social-profile", "share", "annotation", "highlight"] {
            for scrolled in (["session", "session-editor", "climb-editor", "progress", "session-log", "settings", "feed", "share", "annotation", "highlight"].contains(screen) ? [false, true] : [false]) {
                let app = launch(screen)
                if scrolled { app.swipeUp() }
                audit(app, "\(screen) light\(scrolled ? " scrolled" : "")"); app.terminate()
            }
        }
    }
    func testCoreScreensDarkAccessibilityXXXL() {
        for screen in ["home", "session", "feed", "progress", "session-log"] {
            for scrolled in [false, true] {
                let anchor = ["home": "journalSessionActions", "session": "sessionClimbs", "progress": "progressLogs"][screen]
                let anchored = scrolled && anchor != nil
                let app = launch(screen, darkLarge: true, extra: anchored ? ["--audit-scroll-anchor", anchor!] : [])
                if scrolled && !anchored { app.swipeUp() }
                if anchored {
                    let heading = screen == "home" ? app.buttons["startSession"] : app.staticTexts[screen == "session" ? "Your climbs" : "Logs"]
                    XCTAssertTrue(heading.exists || heading.waitForExistence(timeout: 5))
                    XCTAssertTrue(heading.isHittable, "Named scroll checkpoint must be visible")
                    XCTAssertGreaterThanOrEqual(heading.frame.minY, app.navigationBars.firstMatch.frame.maxY - 1)
                    if screen == "session" { XCTAssertLessThanOrEqual(heading.frame.minY, app.navigationBars.firstMatch.frame.maxY + 32) }
                    XCTAssertLessThanOrEqual(heading.frame.maxY, app.tabBars.firstMatch.frame.minY + 1)
                    print("AX-VIEWPORT \(screen): \(heading.frame)")
                }
                audit(app, "\(screen) dark XXXL\(scrolled ? " scrolled" : "")", partitionProbes: anchored); app.terminate()
            }
        }
    }
    private func connectHealth(_ app: XCUIApplication) {
        let connect = app.buttons["connectHealthInsights"]
        if connect.waitForExistence(timeout: 3) {
            for _ in 0..<12 { if connect.isHittable { break }; app.swipeUp() }
            connect.tap()
        }
        let result = app.descendants(matching: .any)[app.launchArguments.contains("--health-insights-empty") ? "healthInsightsMessage" : "healthEffortCard"]
        XCTAssertTrue(result.exists || result.waitForExistence(timeout: 5), "Audit loaded Health results, not a transient loading state")
    }
    func testEditorControlsHaveAccessibleHitRegions() {
        let app = launch("session-editor")
        for button in [app.buttons["Cancel"], app.buttons["saveSession"]] {
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        app.terminate()
    }
    func testConsistencyCalendarCollapses() {
        let app = launch("progress")
        let toggle = app.buttons["consistencyToggle"], grid = app.descendants(matching: .any)["Climbing calendar"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 44)
        XCTAssertTrue(grid.exists)
        // Year → this week → its first day → back to the year.
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let firstDay = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'consistencyDay-'")).firstMatch
        XCTAssertTrue(firstDay.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(firstDay.frame.height, 44)
        // The previous-week button and a swipe both move between weeks.
        let thisWeek = firstDay.identifier
        app.buttons["consistencyPreviousWeek"].tap()
        XCTAssertNotEqual(firstDay.identifier, thisWeek)
        firstDay.swipeLeft()
        XCTAssertEqual(firstDay.identifier, thisWeek)
        XCTAssertFalse(app.buttons["consistencyNextWeek"].isEnabled)
        firstDay.swipeRight()
        XCTAssertNotEqual(firstDay.identifier, thisWeek)
        app.buttons["consistencyNextWeek"].tap()
        XCTAssertEqual(firstDay.identifier, thisWeek)
        // Last week is all rest days, so a tap explains the day instead of opening a log.
        app.buttons["consistencyPreviousWeek"].tap()
        firstDay.tap()
        XCTAssertEqual(app.staticTexts["consistencyDetail"].label, firstDay.label)
        audit(app, "progress week")
        app.buttons["consistencyYear"].tap()
        XCTAssertTrue(grid.waitForExistence(timeout: 2))
        toggle.tap()
        XCTAssertTrue(grid.waitForNonExistence(timeout: 2))
        XCTAssertEqual(toggle.value as? String, "Collapsed")
        // Expand again so the stored state doesn't hide the calendar from later audits.
        toggle.tap()
        XCTAssertTrue(grid.waitForExistence(timeout: 2))
        app.terminate()
    }
    func testCalendarDayOpensItsSessionLog() {
        let app = launch("progress")
        let grid = app.descendants(matching: .any)["Climbing calendar"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let climbed = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'consistencyDay-' AND label CONTAINS '1 session'")).firstMatch
        // The seeded session is two hours old, so just after midnight on a week's first day it sits in last week.
        if !climbed.waitForExistence(timeout: 2) { app.buttons["consistencyPreviousWeek"].tap() }
        XCTAssertTrue(climbed.waitForExistence(timeout: 2))
        climbed.tap()
        XCTAssertTrue(app.navigationBars["Session log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Audit gym"].exists)
        app.terminate()
    }
    func testHistorySwipeDeletesSessionAfterConfirming() {
        let app = launch("history")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Audit gym'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Delete"].tap()
        app.buttons["Delete session"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your story starts here"].exists)
        app.terminate()
    }
    /// Large text, because the page has to be long enough to scroll. It starts scrolled to the logs, with the calendar just above.
    func testDragOnCalendarTilesScrollsThePage() {
        let app = launch("progress", darkLarge: true, extra: ["--audit-scroll-anchor", "progressLogs"])
        let grid = app.descendants(matching: .any)["Climbing calendar"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let firstDay = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'consistencyDay-'")).firstMatch
        XCTAssertTrue(firstDay.waitForExistence(timeout: 2))
        let top = firstDay.frame.minY
        firstDay.swipeDown()
        XCTAssertGreaterThan(firstDay.frame.minY, top)
    }
    func testSessionLogWithHealthAndEmptyReads() {
        for empty in [false, true] {
            for scrolled in [false, true] {
                let app = launch("session-log", extra: ["--health-insights-fixture"] + (empty ? ["--health-insights-empty"] : []))
                connectHealth(app)
                if scrolled { app.swipeUp() }
                audit(app, "Health \(empty ? "no accessible data" : "optional cards")\(scrolled ? " scrolled" : "")")
                app.terminate()
            }
        }
    }
    func testEmptyStatesAndSaveErrorBanner() {
        for screen in ["home", "history", "projects", "friends", "feed"] {
            let app = launch(screen, empty: true); audit(app, "\(screen) empty"); app.terminate()
        }
        let app = launch("home", extra: ["--audit-save-error"])
        XCTAssertTrue(app.staticTexts["Couldn’t save"].waitForExistence(timeout: 5)); audit(app, "Save error banner"); app.terminate()
    }
}
