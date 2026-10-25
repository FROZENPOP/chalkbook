import XCTest
import SwiftData
@testable import ClimbingApp

final class ProgressSummaryTests: XCTestCase {
    func testRepeatedSendsDoNotInflateCompletedClimbs() {
        let summary = ProgressSummary(climbs: [
            ClimbSnapshot(scale: .vScale, grade: "V3", attempts: 4, sends: 2),
            ClimbSnapshot(scale: .vScale, grade: "V3", attempts: 2, sends: 0),
            ClimbSnapshot(scale: .vScale, grade: "V4", attempts: 0, sends: 0)
        ])
        XCTAssertEqual(summary.attempts, 6)
        XCTAssertEqual(summary.sends, 2)
        XCTAssertEqual(summary.completed, 1)
        XCTAssertEqual(summary.attempted, 2)
        XCTAssertEqual(summary.completionRate, 0.5)
        XCTAssertEqual(summary.grades(in: .vScale).first?.rate, 0.5)
    }

    func testHighestSendUsesGradeOrderAndKeepsScalesSeparate() {
        let summary = ProgressSummary(climbs: [
            ClimbSnapshot(scale: .vScale, grade: "V9", attempts: 1, sends: 1),
            ClimbSnapshot(scale: .vScale, grade: "V10", attempts: 1, sends: 1),
            ClimbSnapshot(scale: .vScale, grade: "V12", attempts: 1, sends: 0),
            ClimbSnapshot(scale: .font, grade: "7A+", attempts: 1, sends: 1),
            ClimbSnapshot(scale: .vScale, grade: "Ungraded", attempts: 1, sends: 1)
        ])
        XCTAssertEqual(summary.highestSend(in: .vScale), "V10")
        XCTAssertEqual(summary.highestSend(in: .font), "7A+")
        XCTAssertEqual(summary.sends, 4)
        XCTAssertEqual(summary.grades(in: .vScale).count, 3)
    }

    func testEmptyMetricsDoNotDivideByZero() {
        let summary = ProgressSummary(climbs: [])
        XCTAssertNil(summary.completionRate)
        XCTAssertNil(summary.highestSend(in: .vScale))
        XCTAssertTrue(summary.grades(in: .vScale).isEmpty)
    }

    func testLocalDateIsStableAcrossTimeZonesAndRejectsInvalidDays() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-24T02:00:00Z"))
        XCTAssertEqual(SessionDay.key(for: date, in: try XCTUnwrap(TimeZone(identifier: "America/New_York"))), "2026-10-23")
        XCTAssertEqual(SessionDay.key(for: date, in: try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))), "2026-10-24")
        XCTAssertNotNil(SessionDay.date(for: "2024-02-29"))
        XCTAssertNil(SessionDay.date(for: "2026-02-29"))
        XCTAssertNil(SessionDay.date(for: "2026-13-01"))
    }
}

@MainActor
final class ClimbingStoreTests: XCTestCase {
    private func makeStore() throws -> ClimbingStore {
        let container = try Persistence.container(inMemory: true)
        return ClimbingStore(context: container.mainContext)
    }

    private func addClimb(to session: ClimbingSession, store: ClimbingStore, prior: PriorExperience = .unknown) -> ClimbEntry {
        let climb = ClimbEntry(grade: "V3", prior: prior)
        XCTAssertTrue(store.save {
            store.context.insert(climb)
            session.climbs.append(climb)
        })
        return climb
    }

    func testOnlyOneActiveSessionCanBeCreated() throws {
        let store = try makeStore()
        let first = try XCTUnwrap(store.start(date: .now, location: "Gym", notes: ""))
        let second = try XCTUnwrap(store.start(date: .now, location: "Other gym", notes: ""))
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<ClimbingSession>()), 1)
    }

    func testAttemptsUndoFlashAndRepeatRules() throws {
        let store = try makeStore()
        let session = try XCTUnwrap(store.start(date: .now, location: "Gym", notes: ""))
        let climb = addClimb(to: session, store: store, prior: .newClimb)
        store.record(sent: false, on: climb)
        store.record(sent: true, on: climb)
        XCTAssertFalse(climb.isFlash)
        XCTAssertEqual(climb.resultLabel, "Sent")
        store.undo(on: climb)
        XCTAssertEqual(climb.attempts.count, 1)
        XCTAssertEqual(climb.sendCount, 0)
        store.undo(on: climb)
        store.record(sent: true, on: climb)
        XCTAssertTrue(climb.isFlash)
        XCTAssertEqual(climb.orderedAttempts.first?.sequence, 1)
        let repeatClimb = addClimb(to: session, store: store, prior: .sent)
        store.record(sent: true, on: repeatClimb)
        XCTAssertEqual(repeatClimb.resultLabel, "Repeat")
        XCTAssertFalse(repeatClimb.isFlash)
        let unknown = addClimb(to: session, store: store)
        store.record(sent: true, on: unknown)
        XCTAssertEqual(unknown.resultLabel, "First try this session")
    }

    func testFinishedSessionDoesNotAcceptLiveAttempts() throws {
        let store = try makeStore()
        let session = try XCTUnwrap(store.start(date: .now, location: "", notes: ""))
        let climb = addClimb(to: session, store: store)
        store.finish(session)
        store.record(sent: true, on: climb)
        XCTAssertTrue(climb.attempts.isEmpty)
        XCTAssertNotNil(session.endedAt)
        XCTAssertNotEqual(store.start(date: .now, location: "", notes: "")?.id, session.id)
    }

    func testDeletingSessionPreservesIndependentClimbAndDeletesAttempts() throws {
        let store = try makeStore()
        let session = try XCTUnwrap(store.start(date: .now, location: "", notes: ""))
        let climb = addClimb(to: session, store: store)
        store.record(sent: true, on: climb)
        XCTAssertTrue(store.delete(session))
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<ClimbEntry>()), 1)
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<ClimbAttempt>()), 0)
    }

    func testFailedMutationRollsBackSavedData() throws {
        enum Failure: Error { case simulated }
        let store = try makeStore()
        let session = try XCTUnwrap(store.start(date: .now, location: "Original", notes: ""))
        XCTAssertFalse(store.save {
            session.location = "Unsaved"
            throw Failure.simulated
        })
        XCTAssertEqual(session.location, "Original")
        XCTAssertNotNil(store.errorMessage)
    }

    func testBackupRoundTripAndReplacingAnExistingIdenticalLog() throws {
        let store = try makeStore()
        let session = try XCTUnwrap(store.start(date: .now, location: "Test gym", notes: "Session notes"))
        let climb = addClimb(to: session, store: store, prior: .newClimb)
        store.record(sent: true, on: climb)
        let id = session.id
        let backup = ClimbingBackup(sessions: [session], defaultScale: .font)
        let decoded = try ClimbingBackup.decode(backup.encoded())
        XCTAssertTrue(store.restore(decoded), store.errorMessage ?? "Restore failed")
        let restored = try XCTUnwrap(store.context.fetch(FetchDescriptor<ClimbingSession>()).first)
        XCTAssertEqual(restored.id, id)
        XCTAssertEqual(restored.location, "Test gym")
        XCTAssertEqual(restored.climbs.first?.attempts.count, 1)
        XCTAssertEqual(restored.sendCount, 1)
        XCTAssertEqual(decoded.defaultScale, .font)
        XCTAssertTrue(store.restore(decoded), store.errorMessage ?? "Repeated restore failed")
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<ClimbAttempt>()), 1)
    }

    func testMalformedBackupsLeaveExistingLogIntact() throws {
        let store = try makeStore()
        let session = try XCTUnwrap(store.start(date: .now, location: "Keep me", notes: ""))
        _ = addClimb(to: session, store: store)
        var backup = ClimbingBackup(sessions: [session], defaultScale: .vScale)
        backup.sessions[0].climbs[0].grade = "V999"
        XCTAssertThrowsError(try ClimbingBackup.decode(backup.encoded()))
        XCTAssertFalse(store.restore(backup))
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<ClimbingSession>()), 1)
        XCTAssertEqual(session.location, "Keep me")
    }

    func testRejectsUnsupportedVersionDuplicateIDsAndMultipleActiveSessions() throws {
        let store = try makeStore()
        let session = try XCTUnwrap(store.start(date: .now, location: "", notes: ""))
        var backup = ClimbingBackup(sessions: [session], defaultScale: .vScale)
        backup.version = 99
        XCTAssertThrowsError(try backup.validated())
        backup.version = 1
        backup.sessions.append(backup.sessions[0])
        XCTAssertThrowsError(try backup.validated())
        backup.sessions[1].id = UUID()
        XCTAssertThrowsError(try backup.validated())
    }

    func testRejectsInvalidAttemptSequences() throws {
        let store = try makeStore()
        let session = try XCTUnwrap(store.start(date: .now, location: "", notes: ""))
        let climb = addClimb(to: session, store: store)
        store.record(sent: true, on: climb)
        var backup = ClimbingBackup(sessions: [session], defaultScale: .vScale)
        backup.sessions[0].climbs[0].attempts[0].sequence = 0
        XCTAssertThrowsError(try backup.validated())
    }

    func testSessionSurvivesOpeningAnotherContainer() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: ClimbingSchemaV5.self)
        let config = ModelConfiguration(schema: schema, url: directory.appending(path: "test.store"), cloudKitDatabase: .none)
        let first = try ModelContainer(for: schema, migrationPlan: ClimbingMigrationPlan.self, configurations: [config])
        let store = ClimbingStore(context: first.mainContext)
        let session = try XCTUnwrap(store.start(date: .now, location: "Persisted gym", notes: ""))
        let climb = addClimb(to: session, store: store)
        store.record(sent: true, on: climb)
        let reopened = try ModelContainer(for: schema, migrationPlan: ClimbingMigrationPlan.self, configurations: [config])
        let saved = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<ClimbingSession>()).first)
        XCTAssertEqual(saved.title, "Persisted gym")
        XCTAssertEqual(saved.sendCount, 1)
        XCTAssertFalse(saved.isComplete)
    }
}
