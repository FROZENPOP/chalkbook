import SwiftUI

/// A year of climbing days, one column per week, shaded by attempts.
struct ConsistencyCalendarView: View {
    let calendar: ConsistencyCalendar
    @State private var selected: ConsistencyCalendar.Day?
    @ScaledMetric(relativeTo: .caption) private var cell: CGFloat = 13
    private let gap: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Consistency").font(.headline)
            JournalMetrics(first: "\(calendar.activeDays)", firstLabel: "climbing days this year",
                           second: "\(calendar.currentWeekStreak)", secondLabel: "week streak",
                           third: "\(calendar.longestWeekStreak)", thirdLabel: "best week streak")
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(calendar.weeks) { week in
                            VStack(spacing: gap) {
                                Text(monthLabel(week)).font(.caption2).foregroundStyle(ClimbTheme.secondaryText)
                                    .fixedSize().frame(width: cell, height: cell * 1.2, alignment: .leading)
                                ForEach(week.days) { day in
                                    RoundedRectangle(cornerRadius: cell / 4)
                                        .fill(fill(day))
                                        .overlay { if day.id == selected?.id { RoundedRectangle(cornerRadius: cell / 4).stroke(.primary, lineWidth: 1.5) } }
                                        .frame(width: cell, height: cell)
                                        .contentShape(Rectangle())
                                        .onTapGesture { if !day.isFuture { selected = day } }
                                }
                            }
                            .id(week.id)
                            // One VoiceOver stop per week; 371 single-day stops would be unusable.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Week of \(week.days[0].date.formatted(.dateTime.month(.wide).day()))")
                            .accessibilityValue(summary(week))
                        }
                    }
                    .padding(.trailing, 4)
                }
                .onAppear { proxy.scrollTo(calendar.weeks.last?.id, anchor: .trailing) }
            }
            HStack(spacing: gap) {
                Text("Less").padding(.trailing, 4)
                ForEach(0..<5) { level in RoundedRectangle(cornerRadius: cell / 4).fill(shade(level)).frame(width: cell, height: cell) }
                Text("More").padding(.leading, 4)
                Spacer()
            }
            .font(.caption).foregroundStyle(ClimbTheme.secondaryText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Darker squares mean more attempts that day")
            Text(selected.map(detail) ?? "Tap a day to see what you climbed. Streaks count weeks with at least one session, so rest days never break them.")
                .font(.subheadline).foregroundStyle(selected == nil ? ClimbTheme.secondaryText : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fill(_ day: ConsistencyCalendar.Day) -> Color { day.isFuture ? .clear : shade(day.level) }
    private func shade(_ level: Int) -> Color { level == 0 ? Color(uiColor: .systemFill) : ClimbTheme.forest.opacity([0, 0.35, 0.55, 0.78, 1][level]) }
    private func monthLabel(_ week: ConsistencyCalendar.Week) -> String {
        guard let first = week.days.first(where: { Calendar.current.component(.day, from: $0.date) == 1 }) else { return "" }
        return first.date.formatted(.dateTime.month(.abbreviated))
    }
    private func plural(_ count: Int, _ noun: String) -> String { "\(count) \(noun)\(count == 1 ? "" : "s")" }
    private func detail(_ day: ConsistencyCalendar.Day) -> String {
        let label = day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return day.sessions == 0 ? "\(label): rest day" : "\(label): \(plural(day.sessions, "session")) · \(plural(day.attempts, "attempt"))"
    }
    private func summary(_ week: ConsistencyCalendar.Week) -> String {
        let active = week.days.filter { $0.sessions > 0 }
        guard !active.isEmpty else { return "No climbing" }
        let days = active.map { $0.date.formatted(.dateTime.weekday(.wide)) }.formatted(.list(type: .and))
        return "Climbed \(days). \(plural(week.sessions, "session")), \(plural(week.attempts, "attempt"))"
    }
}
