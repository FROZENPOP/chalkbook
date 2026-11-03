import SwiftUI

/// A year of climbing days, one column per week, shaded by attempts.
/// Tapping the year zooms into a week; tapping a day in that week shows what was climbed.
struct ConsistencyCalendarView: View {
    let calendar: ConsistencyCalendar
    var openDay: (String) -> Void = { _ in }
    @AppStorage("consistencyCalendarExpanded") private var expanded = true
    @State private var focusedWeek: ConsistencyCalendar.Week?
    @State private var selected: ConsistencyCalendar.Day?
    @State private var cursor: Int?
    @State private var width: CGFloat = 0
    private let gap: CGFloat = 3
    // Shows the weeks that fit instead of scrolling: text in a horizontal scroll view fails the Dynamic Type audit.
    private var weekCount: Int { min(calendar.weeks.count, max(1, Int((width + gap) / 16))) }
    // Cells stretch from 13 pt so the grid fills the card edge to edge.
    private var cell: CGFloat { width > 0 ? (width + gap) / CGFloat(weekCount) - gap : 13 }
    private var weeks: [ConsistencyCalendar.Week] { Array(calendar.weeks.suffix(weekCount)) }
    private var cursorWeek: ConsistencyCalendar.Week? { weeks.indices.contains(cursor ?? -1) ? weeks[cursor!] : weeks.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                HStack {
                    Text("Consistency").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down").font(.subheadline.weight(.semibold)).foregroundStyle(ClimbTheme.secondaryText)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Hides the calendar." : "Shows the calendar.")
            .accessibilityIdentifier("consistencyToggle")
            JournalMetrics(first: "\(calendar.activeDays)", firstLabel: "climbing days this year",
                           second: "\(calendar.currentWeekStreak)", secondLabel: "week streak",
                           third: "\(calendar.longestWeekStreak)", thirdLabel: "best week streak")
            if expanded {
                if let week = focusedWeek { weekView(week) } else { yearView }
                if let text = selected.map(detail) {
                    Text(text).font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("consistencyDetail")
                }
            }
        }
    }

    private var yearView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: gap) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                        if let month = monthLabel(week) {
                            // A month starting in the last columns is right-aligned so it doesn't wrap at the edge.
                            let nearEnd = index >= weeks.count - 2
                            Text(month).font(.caption).foregroundStyle(ClimbTheme.secondaryText).lineLimit(1)
                                .padding(.leading, nearEnd ? 0 : CGFloat(index) * (cell + gap))
                                .frame(maxWidth: .infinity, alignment: nearEnd ? .trailing : .leading)
                        }
                    }
                }
                HStack(alignment: .top, spacing: gap) {
                    ForEach(weeks) { week in
                        VStack(spacing: gap) {
                            ForEach(week.days) { day in RoundedRectangle(cornerRadius: cell / 4).fill(fill(day)).frame(width: cell, height: cell) }
                        }
                    }
                }
                // One tap target for the whole grid; single cells are far below the 44 pt minimum.
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { open(column: Int($0.location.x / (cell + gap))) })
                // VoiceOver steps week by week, as with charts, instead of visiting 371 squares.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Climbing calendar")
                .accessibilityValue(cursorWeek.map(summary) ?? "")
                .accessibilityHint("Swipe up or down to move between weeks. Double-tap to see the week's days.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAdjustableAction { direction in
                    cursor = min(max((cursor ?? weeks.count - 1) + (direction == .increment ? 1 : -1), 0), weeks.count - 1)
                }
                .accessibilityAction { open(column: cursor ?? weeks.count - 1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
    }

    private func weekView(_ week: ConsistencyCalendar.Week) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.snappy) { focusedWeek = nil; selected = nil } } label: {
                Label("Year", systemImage: "chevron.left").font(.subheadline.weight(.semibold)).frame(minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityHint("Shows the whole year.")
            .accessibilityIdentifier("consistencyYear")
            .frame(maxWidth: .infinity, alignment: .leading)
            // Buttons for the same move as the swipe below, so it never depends on a gesture.
            .overlay(alignment: .trailing) {
                HStack(spacing: 0) {
                    weekStep(-1, "chevron.left", "Previous week", "consistencyPreviousWeek")
                    weekStep(1, "chevron.right", "Next week", "consistencyNextWeek")
                }
            }
            HStack(spacing: 6) {
                ForEach(week.days) { day in
                    Button { if day.sessions > 0 { openDay(day.key) } else { selected = day } } label: {
                        // A light tint plus a shaded bar: text on the full shade fails contrast at the middle levels.
                        VStack(spacing: 4) {
                            Text(day.date.formatted(.dateTime.weekday(.narrow))).font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                            Text(day.date.formatted(.dateTime.day())).font(.subheadline.weight(.semibold)).foregroundStyle(day.isFuture ? ClimbTheme.secondaryText : .primary)
                            Capsule().fill(day.sessions > 0 ? shade(day.level) : .clear).frame(height: 6).padding(.horizontal, 10)
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(day.sessions > 0 ? ClimbTheme.accent.opacity(0.16) : day.isFuture ? .clear : Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                        // Future days are outlined rather than dimmed: dimmed text fails contrast.
                        .overlay { if day.isFuture { RoundedRectangle(cornerRadius: 10).stroke(Color(uiColor: .separator)) } }
                        .overlay { if day.id == selected?.id { RoundedRectangle(cornerRadius: 10).stroke(.primary, lineWidth: 2) } }
                    }
                    .buttonStyle(.plain)
                    // Not .disabled: SwiftUI dims disabled buttons below the contrast minimum.
                    .allowsHitTesting(!day.isFuture)
                    .accessibilityRemoveTraits(day.isFuture ? .isButton : [])
                    .accessibilityLabel(detail(day))
                    .accessibilityAddTraits(day.id == selected?.id ? .isSelected : [])
                    .accessibilityIdentifier("consistencyDay-\(day.key)")
                }
            }
            .highPriorityGesture(DragGesture(minimumDistance: 20).onEnded {
                guard abs($0.translation.width) > abs($0.translation.height) else { return }
                open(column: (cursor ?? weeks.count - 1) + ($0.translation.width < 0 ? 1 : -1))
            })
        }
    }

    private func weekStep(_ delta: Int, _ symbol: String, _ label: String, _ id: String) -> some View {
        let column = (cursor ?? weeks.count - 1) + delta
        return Button { open(column: column) } label: {
            Image(systemName: symbol).font(.subheadline.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .disabled(!weeks.indices.contains(column))
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func open(column: Int) {
        guard weeks.indices.contains(column) else { return }
        withAnimation(.snappy) { focusedWeek = weeks[column]; selected = nil; cursor = column }
    }
    private func fill(_ day: ConsistencyCalendar.Day) -> Color { day.isFuture ? Color(uiColor: .quaternarySystemFill) : shade(day.level) }
    private func shade(_ level: Int) -> Color { level == 0 ? Color(uiColor: .systemFill) : ClimbTheme.accent.opacity([0, 0.45, 0.65, 0.85, 1][level]) }
    private func monthLabel(_ week: ConsistencyCalendar.Week) -> String? {
        guard let first = week.days.first(where: { Calendar.current.component(.day, from: $0.date) == 1 }) else { return nil }
        return first.date.formatted(.dateTime.month(.abbreviated))
    }
    private func plural(_ count: Int, _ noun: String) -> String { "\(count) \(noun)\(count == 1 ? "" : "s")" }
    private func detail(_ day: ConsistencyCalendar.Day) -> String {
        let label = day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return day.sessions == 0 ? "\(label): rest day" : "\(label): \(plural(day.sessions, "session")) · \(plural(day.attempts, "attempt"))"
    }
    private func summary(_ week: ConsistencyCalendar.Week) -> String {
        let active = week.days.filter { $0.sessions > 0 }
        guard !active.isEmpty else { return "Week of \(week.days[0].date.formatted(.dateTime.month(.wide).day())): no climbing" }
        let days = active.map { $0.date.formatted(.dateTime.weekday(.wide)) }.formatted(.list(type: .and))
        return "Week of \(week.days[0].date.formatted(.dateTime.month(.wide).day())): climbed \(days). \(plural(week.sessions, "session")), \(plural(week.attempts, "attempt"))"
    }
}
