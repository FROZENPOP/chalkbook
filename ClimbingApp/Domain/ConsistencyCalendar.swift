import Foundation

/// A year of climbing days laid out in calendar weeks for the Progress consistency calendar.
/// Streaks count weeks, not days: rest days are part of training and should never break a streak.
struct ConsistencyCalendar {
    struct Day: Identifiable {
        let key: String
        let date: Date
        let sessions: Int
        let attempts: Int
        let isFuture: Bool
        var id: String { key }
        /// 0 is no climbing; 1–4 shade by attempts so a light session still shows.
        var level: Int { sessions == 0 ? 0 : attempts >= 30 ? 4 : attempts >= 15 ? 3 : attempts >= 5 ? 2 : 1 }
    }
    struct Week: Identifiable {
        let days: [Day]
        var id: String { days[0].key }
        var sessions: Int { days.reduce(0) { $0 + $1.sessions } }
        var attempts: Int { days.reduce(0) { $0 + $1.attempts } }
    }

    let weeks: [Week]
    let activeDays: Int
    let currentWeekStreak: Int
    let longestWeekStreak: Int

    init(sessions: [(day: String, attempts: Int)], weekCount: Int = 53, today: Date = .now, calendar: Calendar = .current) {
        var byDay: [String: (sessions: Int, attempts: Int)] = [:]
        for session in sessions { byDay[session.day, default: (0, 0)].sessions += 1; byDay[session.day, default: (0, 0)].attempts += session.attempts }
        let todayKey = SessionDay.key(for: today, in: calendar.timeZone)
        func weekStart(_ date: Date) -> Date { calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date) }
        let thisWeek = weekStart(today)
        weeks = (0..<weekCount).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek) else { return nil }
            return Week(days: (0..<7).compactMap { index in
                guard let date = calendar.date(byAdding: .day, value: index, to: start) else { return nil }
                let key = SessionDay.key(for: date, in: calendar.timeZone)
                let activity = byDay[key] ?? (0, 0)
                return Day(key: key, date: date, sessions: activity.sessions, attempts: activity.attempts, isFuture: key > todayKey)
            })
        }
        activeDays = weeks.flatMap(\.days).filter { $0.sessions > 0 && !$0.isFuture }.count

        // Streaks use the whole history, not just the visible year.
        let activeWeeks = Set(byDay.keys.filter { $0 <= todayKey }.compactMap { SessionDay.date(for: $0, in: calendar.timeZone).map(weekStart) })
        func previous(_ week: Date) -> Date? { calendar.date(byAdding: .weekOfYear, value: -1, to: week) }
        // The current week only breaks the streak once it is over.
        var cursor: Date? = activeWeeks.contains(thisWeek) ? thisWeek : previous(thisWeek)
        var current = 0
        while let week = cursor, activeWeeks.contains(week) { current += 1; cursor = previous(week) }
        currentWeekStreak = current
        var longest = 0
        for week in activeWeeks where !(previous(week).map(activeWeeks.contains) ?? false) {
            var length = 1, next = calendar.date(byAdding: .weekOfYear, value: 1, to: week)
            while let candidate = next, activeWeeks.contains(candidate) { length += 1; next = calendar.date(byAdding: .weekOfYear, value: 1, to: candidate) }
            longest = max(longest, length)
        }
        longestWeekStreak = longest
    }
}
