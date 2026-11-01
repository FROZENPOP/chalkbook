import Foundation
import SwiftData
import XCTest
@testable import ClimbingApp

/// Three years of near-daily climbing: the calendar, backups and deletion must stay fast and lossless.
@MainActor
final class LargeJournalStressTests: XCTestCase {
    func testThreeYearJournalStaysFastAndRoundTrips() throws {
        let container = try Persistence.container(inMemory: true)
        let store = ClimbingStore(context: container.mainContext)
        let clock = ContinuousClock()
        let sessionCount = 1100, climbsPerSession = 2, attemptsPerClimb = 5
        XCTAssertTrue(store.save {
            for index in 0..<sessionCount {
                let date = Date.now.addingTimeInterval(-Double(index) * 86_400)
                let session = ClimbingSession(date: date, location: "Gym \(index % 4)")
                session.isComplete = true; session.endedAt = date.addingTimeInterval(5400)
                store.context.insert(session)
                for climbIndex in 0..<climbsPerSession {
                    let climb = ClimbEntry(scale: .vScale, grade: "V\(climbIndex + index % 6)")
                    store.context.insert(climb); session.climbs.append(climb)
                    for sequence in 1...attemptsPerClimb {
                        let attempt = ClimbAttempt(sequence: sequence, sent: sequence == attemptsPerClimb, recordedAt: date)
                        store.context.insert(attempt); climb.attempts.append(attempt)
                    }
                }
            }
        })
        let sessions = try store.context.fetch(FetchDescriptor<ClimbingSession>())
        XCTAssertEqual(sessions.count, sessionCount)

        var rows: [(day: String, attempts: Int)] = []
        // Mirrors Progress: only the visible year needs attempt counts.
        let since = SessionDay.key(for: .now.addingTimeInterval(-380 * 86_400))
        let countTime = clock.measure { rows = sessions.map { ($0.day, $0.day >= since ? $0.attemptCount : 0) } }
        XCTAssertLessThan(countTime, .seconds(1), "Counting attempts took \(countTime)")
        let calendarTime = clock.measure {
            let calendar = ConsistencyCalendar(sessions: rows)
            XCTAssertEqual(calendar.weeks.count, 53)
            XCTAssertGreaterThanOrEqual(calendar.longestWeekStreak, 150)
        }
        XCTAssertLessThan(calendarTime, .seconds(3), "Consistency calendar took \(calendarTime)")

        var data = Data()
        let exportTime = try clock.measure { data = try ClimbingBackup(sessions: sessions, defaultScale: .vScale).encoded() }
        XCTAssertLessThan(exportTime, .seconds(15), "Backup export took \(exportTime)")
        let backup = try ClimbingBackup.decode(data)
        XCTAssertEqual(backup.sessions.count, sessionCount)

        let restoreTime = clock.measure { XCTAssertTrue(store.restore(backup), store.errorMessage ?? "Restore failed") }
        XCTAssertLessThan(restoreTime, .seconds(30), "Restore took \(restoreTime)")
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<ClimbingSession>()), sessionCount)
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<ClimbAttempt>()), sessionCount * climbsPerSession * attemptsPerClimb)

        let deleteTime = clock.measure { XCTAssertTrue(store.deleteAll()) }
        XCTAssertLessThan(deleteTime, .seconds(15), "Delete all took \(deleteTime)")
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<ClimbAttempt>()), 0)
        print("STRESS counts=\(countTime) calendar=\(calendarTime) export=\(exportTime) (\(data.count / 1024) KB) restore=\(restoreTime) delete=\(deleteTime)")
    }
}
