import SwiftData
import XCTest
@testable import ClimbingApp

@MainActor
final class ScreenshotDemoTests: XCTestCase {
    private let media = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "marketing/demo-media")
    private var profiles: URL!
    private var container: ModelContainer? // the context needs its container alive

    override func setUpWithError() throws {
        profiles = FileManager.default.temporaryDirectory.appending(path: "ScreenshotDemoTests-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: profiles) }

    private func seeded() throws -> ModelContext {
        let store = try Persistence.container(inMemory: true); container = store
        let context = store.mainContext
        try ScreenshotDemo.seed(context, enabled: true, media: media, profileDirectory: profiles)
        return context
    }

    func testSeedIsNoOpWithoutTheLaunchFlags() throws {
        XCTAssertFalse(ScreenshotDemo.enabled)
        XCTAssertFalse(SocialAuditSample.enabled)
        XCTAssertFalse(AccessibilityAuditFixtures.enabled)
        let store = try Persistence.container(inMemory: true); container = store
        let context = store.mainContext
        try ScreenshotDemo.seed(context, profileDirectory: profiles)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ClimbingSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SavedGym>()), 0)
        XCTAssertNil(ProfileStore(key: "guest", directory: profiles).profile)
    }

    func testSeedCoversAboutThreeMonthsWithAWeeklyStreak() throws {
        let sessions = try seeded().fetch(FetchDescriptor<ClimbingSession>(sortBy: [SortDescriptor(\.startedAt)]))
        XCTAssertGreaterThanOrEqual(sessions.count, 30)
        let days = sessions.last!.startedAt.timeIntervalSince(sessions.first!.startedAt) / 86_400
        XCTAssertTrue((80...95).contains(days), "\(days) days")
        XCTAssertLessThan(Date.now.timeIntervalSince(sessions.last!.startedAt), 3 * 86_400, "The journal is current")
        XCTAssertTrue(sessions.allSatisfy { $0.isComplete && $0.durationMinutes != nil && !$0.recordedAttempts.isEmpty })
        XCTAssertGreaterThanOrEqual(ConsistencyCalendar(sessions: sessions.map { ($0.day, $0.attemptCount) }).currentWeekStreak, 12)
        XCTAssertEqual(Set(sessions.map(\.location)).count, 3)
    }

    func testHardestSendRisesAndAProjectWasSentRecently() throws {
        let context = try seeded()
        let attempts = try context.fetch(FetchDescriptor<ClimbAttempt>(sortBy: [SortDescriptor(\.recordedAt)]))
        let first = attempts.first!.recordedAt, span = attempts.last!.recordedAt.timeIntervalSince(first)
        let hardest = (0..<3).map { third in
            attempts.filter { $0.sent && Int($0.recordedAt.timeIntervalSince(first) / span * 2.999) == third }
                .compactMap { $0.climb.map { Int($0.grade.dropFirst())! } }.max() ?? -1
        }
        XCTAssertEqual(hardest, hardest.sorted(), "Max grade never drops: \(hardest)")
        XCTAssertGreaterThan(hardest[2], hardest[0])
        let climbs = try context.fetch(FetchDescriptor<ClimbEntry>())
        XCTAssertEqual(Set(climbs.map(\.grade)), Set((0...8).map { "V\($0)" }))
        let sent = climbs.filter { $0.projectRaw == "active" && $0.isSent }
        XCTAssertFalse(sent.isEmpty, "A project was sent")
        XCTAssertTrue(sent.contains { $0.attempts.contains { $0.sent && Date.now.timeIntervalSince($0.recordedAt) < 3 * 86_400 } })
        XCTAssertTrue(sent.allSatisfy { $0.attempts.count > 3 }, "Projects take work")
        XCTAssertFalse(climbs.filter { $0.projectStatus == "active" }.isEmpty, "Some projects are still open")
        XCTAssertGreaterThan(climbs.filter(\.isFlash).count, 0)
    }

    func testNotesPhotosAndProfileArePresent() throws {
        let context = try seeded()
        XCTAssertGreaterThanOrEqual(try context.fetch(FetchDescriptor<ClimbingSession>()).filter { !$0.notes.isEmpty }.count, 3)
        let climbs = try context.fetch(FetchDescriptor<ClimbEntry>())
        XCTAssertGreaterThanOrEqual(climbs.filter { !$0.notes.isEmpty }.count, 3)
        XCTAssertGreaterThanOrEqual(try context.fetchCount(FetchDescriptor<ClimbNote>()), 2)
        let photos = try context.fetch(FetchDescriptor<RouteMedia>())
        XCTAssertGreaterThanOrEqual(photos.count, 4)
        for photo in photos {
            XCTAssertNoThrow(try photo.draft.validate())
            XCTAssertEqual(try RouteAnnotations.document(photo.annotationJSON).highlight?.selections, [ScreenshotDemo.startHold])
        }
        let profile = try XCTUnwrap(ProfileStore(key: "guest", directory: profiles).profile)
        XCTAssertEqual(profile.name, ScreenshotDemo.climberName)
        XCTAssertNotNil(profile.photo)
    }

    func testSeedRunsOnlyIntoAnEmptyJournal() throws {
        let context = try seeded()
        let count = try context.fetchCount(FetchDescriptor<ClimbingSession>())
        try ScreenshotDemo.seed(context, enabled: true, media: media, profileDirectory: profiles)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ClimbingSession>()), count)
    }

    func testFriendsSampleHasPeoplePostsPhotosReactionsAndComments() {
        let friends = SocialAuditSample.friendships.filter { $0.status == "accepted" }
        XCTAssertTrue((3...5).contains(friends.count))
        let others = SocialAuditSample.posts.filter { $0.owner_id != SocialAuditSample.me.id }
        XCTAssertGreaterThanOrEqual(Set(others.map(\.owner_id)).count, 3)
        XCTAssertGreaterThanOrEqual(others.filter { ($0.route_photo_count ?? 0) > 0 }.count, 2)
        XCTAssertGreaterThanOrEqual(SocialAuditSample.reactions().count, 3)
        XCTAssertGreaterThanOrEqual(SocialAuditSample.comments().values.joined().count, 5)
    }
}
