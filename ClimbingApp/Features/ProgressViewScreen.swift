import SwiftUI
import SwiftData
import Charts

enum ProgressRange: String, CaseIterable, Identifiable {
    case month = "30 days", quarter = "90 days", all = "All time"
    var id: String { rawValue }
    var days: Int? { switch self { case .month: 30; case .quarter: 90; case .all: nil } }
}

struct ProgressViewScreen: View {
    @Query(sort: \ClimbingSession.day, order: .reverse) private var sessions: [ClimbingSession]
    @State private var range = ProgressRange.month
    @State private var scale = GradeScale.vScale

    private var filtered: [ClimbingSession] {
        guard let days = range.days,
              let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: .now) else { return sessions }
        let key = SessionDay.key(for: start)
        return sessions.filter { $0.day >= key }
    }
    private var statistics: JournalStatistics { JournalStatistics(sessions: filtered) }
    private var weeks: [WeekActivity] {
        let grouped = Dictionary(grouping: filtered) { session -> String in
            guard let date = SessionDay.date(for: session.day),
                  let start = Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start else { return session.day }
            return SessionDay.key(for: start)
        }
        return grouped.keys.sorted().map { WeekActivity(day: $0, sessions: grouped[$0]!.count, minutes: grouped[$0]!.compactMap(\.durationMinutes).reduce(0,+), durationCount: grouped[$0]!.filter { $0.durationMinutes != nil }.count) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // The calendar always shows the past year, so it sits above the range picker it ignores.
                if !sessions.isEmpty {
                    // Attempts only shade the visible year; streaks need just the days, so older sessions skip the costly count.
                    let since = SessionDay.key(for: .now.addingTimeInterval(-380 * 86_400))
                    Surface { ConsistencyCalendarView(calendar: ConsistencyCalendar(sessions: sessions.map { ($0.day, $0.day >= since ? $0.attemptCount : 0) })) }
                }
                Picker("Time range", selection: $range) { ForEach(ProgressRange.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                ProgressHealthSection(sessionIDs: Set(filtered.map(\.id)))
                if filtered.isEmpty {
                    EmptyState(title: "Progress takes practice", symbol: "chart.bar.xaxis", message: "Your sessions and sends will show up here as you climb.")
                } else {
                    Text("Every attempt counts.").font(.title2.bold())
                    Surface {
                        JournalMetrics(first: "\(filtered.count)", firstLabel: "sessions", second: statistics.knownAttempts.map(String.init) ?? "Unknown", secondLabel: "attempts", third: statistics.knownSends.map(String.init) ?? "Unknown", thirdLabel: "sends")
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Climbs completed").font(.headline)
                            Text("\(statistics.distinctClimbsSent)")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(ClimbTheme.accent)
                            Text("\(statistics.distinctClimbsSent) of \(statistics.distinctClimbsAttempted) identified climbs. Recalled sends cannot establish distinct climb identities.")
                                .font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
                        }
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Completeness and time").font(.headline)
                            Text("\(statistics.recalledSessions) sessions include recalled activity. Other values count recorded activity only; unlogged activity remains unknown.")
                            Text("\(statistics.recordedMinutes) recorded minutes across \(statistics.durationCount) sessions with known duration.")
                            Text("Confirmed flashes: \(statistics.confirmedFlashes) / \(statistics.knownFlashDenominator) sent climbs with known history; \(statistics.unknownFlashCount) unknown.")
                            Text("Flash classification uses the complete journal history even when this date filter covers fewer sessions.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                        }.accessibilityElement(children: .combine)
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Sessions per week").font(.headline).id("progressWeeklyActivity")
                            Chart(weeks) { week in
                                BarMark(x: .value("Week", SessionDay.date(for: week.day) ?? .now, unit: .weekOfYear), y: .value("Sessions", week.sessions))
                                    .foregroundStyle(ClimbTheme.accent).cornerRadius(5)
                            }.frame(height: 160)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Weekly activity")
                            .accessibilityValue("\(filtered.count) sessions across \(weeks.count) weeks with activity")
                            ForEach(weeks) { week in Text("\(SessionDay.label(for: week.day)): \(week.sessions) sessions").font(.caption) }
                            if weeks.contains(where: { $0.durationCount > 0 }) {
                                Text("Recorded duration per week").font(.headline)
                                Chart(weeks.filter { $0.durationCount > 0 }) { week in
                                    BarMark(x: .value("Week", SessionDay.date(for: week.day) ?? .now, unit: .weekOfYear), y: .value("Recorded minutes", week.minutes)).foregroundStyle(ClimbTheme.accent)
                                }.frame(height: 160).accessibilityElement(children: .ignore).accessibilityLabel("Weekly recorded duration")
                                .accessibilityValue(weeks.filter { $0.durationCount > 0 }.map { "\(SessionDay.label(for: $0.day)): \($0.minutes) recorded minutes in \($0.durationCount) sessions" }.joined(separator: "; "))
                                ForEach(weeks.filter { $0.durationCount > 0 }) { week in Text("\(SessionDay.label(for: week.day)): \(week.minutes) recorded minutes in \(week.durationCount) sessions").font(.caption) }
                            }
                            Text("Weeks begin on your calendar’s first weekday.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                        }
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            Picker("Grade scale", selection: $scale) { ForEach(GradeScale.allCases) { Text($0.rawValue).tag($0) } }
                                .pickerStyle(.menu)
                            let distribution = statistics.distributions(in: scale)
                            if distribution.isEmpty { Text("No individual attempts in this grading system yet. Recalled totals do not establish grade-level evidence.").foregroundStyle(ClimbTheme.secondaryText) }
                            ForEach(distribution) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.label).font(.headline)
                                    Text("\(item.attempts) recorded attempts · \(item.sends) sends").font(.subheadline)
                                }.accessibilityElement(children: .combine)
                            }
                            Text("Gym scales stay separate. Custom labels are shown in your gym’s saved order when available, and never converted into V grades.")
                                .font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                        }
                    }
                }
            }.padding(20)
        }
        .background(ClimbTheme.background)
        .navigationTitle("Progress")
    }
}

private struct WeekActivity: Identifiable {
    let day: String
    let sessions: Int
    let minutes: Int
    let durationCount: Int
    var id: String { day }
}
