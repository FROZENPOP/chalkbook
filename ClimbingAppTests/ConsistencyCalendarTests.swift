import XCTest
@testable import ClimbingApp

final class ConsistencyCalendarTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }()
    // Wednesday 2026-10-28.
    private let today = Date(timeIntervalSince1970: 1_793_188_800)

    private func make(_ sessions: [(String, Int)], weeks: Int = 53) -> ConsistencyCalendar {
        ConsistencyCalendar(sessions: sessions.map { (day: $0.0, attempts: $0.1) }, weekCount: weeks, today: today, calendar: calendar)
    }

    func testGridIsWholeWeeksEndingThisWeekWithFutureDaysMarked() {
        let grid = make([], weeks: 3)
        XCTAssertEqual(grid.weeks.map(\.days.count), [7, 7, 7])
        XCTAssertEqual(grid.weeks.first?.days.first?.key, "2026-10-12")
        XCTAssertEqual(grid.weeks.last?.days.first?.key, "2026-10-26")
        XCTAssertEqual(grid.weeks.last?.days.filter(\.isFuture).map(\.key), ["2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01"])
    }

    func testDaysCombineSessionsAndShadeByAttempts() {
        let grid = make([("2026-10-26", 3), ("2026-10-26", 4), ("2026-10-27", 40), ("2026-10-20", 0)], weeks: 2)
        let days = Dictionary(uniqueKeysWithValues: grid.weeks.flatMap(\.days).map { ($0.key, $0) })
        XCTAssertEqual(days["2026-10-26"]?.sessions, 2)
        XCTAssertEqual(days["2026-10-26"]?.attempts, 7)
        XCTAssertEqual(days["2026-10-26"]?.level, 2)
        XCTAssertEqual(days["2026-10-27"]?.level, 4)
        XCTAssertEqual(days["2026-10-20"]?.level, 1, "a recalled session with no attempts still counts as a climbing day")
        XCTAssertEqual(days["2026-10-21"]?.level, 0)
        XCTAssertEqual(grid.activeDays, 3)
    }

    func testStreaksCountWeeksAndAnUnfinishedWeekDoesNotBreakThem() {
        // Active weeks: Oct 5, Oct 12, Oct 19 (nothing yet this week), plus an older 4-week run in August.
        let grid = make([("2026-10-05", 1), ("2026-10-14", 1), ("2026-10-18", 1), ("2026-10-25", 1),
                         ("2026-08-03", 1), ("2026-08-10", 1), ("2026-08-17", 1), ("2026-08-24", 1)])
        XCTAssertEqual(grid.currentWeekStreak, 3, "Sundays close Monday-start weeks: Oct 18 counts for the week of Oct 12")
        XCTAssertEqual(grid.longestWeekStreak, 4)
        XCTAssertEqual(make([("2026-10-28", 1), ("2026-10-25", 1)]).currentWeekStreak, 2)
        XCTAssertEqual(make([("2026-10-12", 1)]).currentWeekStreak, 0, "a missed full week ends the streak")
    }

    func testStreaksIncludeHistoryOlderThanTheGridAndIgnoreFutureDays() {
        let grid = make([("2024-01-01", 1), ("2024-01-08", 1), ("2026-11-02", 5)], weeks: 1)
        XCTAssertEqual(grid.longestWeekStreak, 2)
        XCTAssertEqual(grid.currentWeekStreak, 0)
        XCTAssertEqual(grid.activeDays, 0)
    }
}
