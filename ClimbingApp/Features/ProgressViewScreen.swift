import SwiftUI
import SwiftData
import Charts

enum ProgressRange: String, CaseIterable, Identifiable {
    case month = "30 days", quarter = "90 days", all = "All time"
    var id: String { rawValue }
    var days: Int? { switch self { case .month: 30; case .quarter: 90; case .all: nil } }
}

struct ProgressViewScreen: View {
    @Query(sort: [SortDescriptor(\ClimbingSession.day, order: .reverse), SortDescriptor(\ClimbingSession.startedAt, order: .reverse)]) private var sessions: [ClimbingSession]
    @State private var opened: ClimbingSession?
    @State private var dayChoices: [ClimbingSession] = []
    @State private var shownLogs = 30

    var body: some View {
        ScrollView {
            // Paged instead of lazy: a LazyVStack left rows it built while scrolling out of the accessibility tree, so VoiceOver couldn't reach them.
            VStack(alignment: .leading, spacing: 16) {
                if sessions.isEmpty {
                    EmptyState(title: "Progress takes practice", symbol: "chart.bar.xaxis", message: "Your sessions will show up here.")
                } else {
                    // Attempts only shade the visible year; streaks need just the days, so older sessions skip the costly count.
                    let since = SessionDay.key(for: .now.addingTimeInterval(-380 * 86_400))
                    Surface { ConsistencyCalendarView(calendar: ConsistencyCalendar(sessions: sessions.map { ($0.day, $0.day >= since ? $0.attemptCount : 0) }), openDay: open) }
                    Text("Logs").font(.title3.bold()).id("progressLogs")
                    ForEach(sessions.prefix(shownLogs)) { session in
                        NavigationLink { log(session) } label: { Surface { SessionRow(session: session) } }.buttonStyle(.plain)
                    }
                    if sessions.count > shownLogs {
                        Button("Show older sessions") { shownLogs += 30 }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("showOlderLogs")
                    }
                }
            }.padding(20)
        }
        .background(ClimbTheme.background)
        .navigationTitle("Progress")
        .toolbar {
            if !sessions.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { NavigationLink { ProgressStatsView() } label: { Label("Stats", systemImage: "chart.line.uptrend.xyaxis") }.accessibleToolbarAction().accessibilityIdentifier("openStats") }
            }
        }
        .navigationDestination(item: $opened) { log($0) }
        .confirmationDialog("Which session?", isPresented: Binding(get: { !dayChoices.isEmpty }, set: { if !$0 { dayChoices = [] } }), titleVisibility: .visible) {
            ForEach(dayChoices) { session in
                Button("\(session.title) · \(session.startedAt.formatted(date: .omitted, time: .shortened))") { opened = session }
            }
        }
    }

    @ViewBuilder private func log(_ session: ClimbingSession) -> some View {
        if session.isComplete { SessionLogView(session: session) } else { SessionDetailView(session: session) }
    }

    private func open(day: String) {
        let matches = sessions.filter { $0.day == day }
        if matches.count == 1 { opened = matches[0] } else { dayChoices = matches }
    }
}

struct ProgressStatsView: View {
    @Query(sort: [SortDescriptor(\ClimbingSession.day, order: .reverse), SortDescriptor(\ClimbingSession.startedAt, order: .reverse)]) private var sessions: [ClimbingSession]
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
        return grouped.keys.sorted().map { WeekActivity(day: $0, sessions: grouped[$0]!.count) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Time range", selection: $range) { ForEach(ProgressRange.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                if filtered.isEmpty {
                    Text("No sessions in this range.").foregroundStyle(ClimbTheme.secondaryText)
                } else {
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            JournalMetrics(first: "\(filtered.count)", firstLabel: "sessions", second: statistics.knownAttempts.map(String.init) ?? "Unknown", secondLabel: "attempts", third: statistics.knownSends.map(String.init) ?? "Unknown", thirdLabel: "sends")
                            JournalMetrics(first: "\(statistics.distinctClimbsSent)", firstLabel: "climbs sent", second: "\(statistics.confirmedFlashes)", secondLabel: "flashes", third: "\(statistics.recordedMinutes)", thirdLabel: "minutes")
                        }
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Sessions per week").font(.headline)
                            Chart(weeks) { week in
                                BarMark(x: .value("Week", SessionDay.date(for: week.day) ?? .now, unit: .weekOfYear), y: .value("Sessions", week.sessions))
                                    .foregroundStyle(ClimbTheme.accent).cornerRadius(5)
                            }.frame(height: 140)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Weekly activity")
                            .accessibilityValue(weeks.map { "\(SessionDay.label(for: $0.day)): \($0.sessions.counted("session"))" }.joined(separator: "; "))
                        }
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Grade scale", selection: $scale) { ForEach(GradeScale.allCases) { Text($0.rawValue).tag($0) } }
                                .pickerStyle(.menu)
                            let distribution = statistics.distributions(in: scale)
                            if distribution.isEmpty { Text("No attempts in this scale.").foregroundStyle(ClimbTheme.secondaryText) }
                            ForEach(distribution) { item in
                                LabeledContent(item.label, value: "\(item.attempts.counted("attempt")) · \(item.sends.counted("send"))")
                            }
                        }
                    }
                }
            }.padding(20)
        }
        .background(ClimbTheme.background)
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WeekActivity: Identifiable {
    let day: String
    let sessions: Int
    var id: String { day }
}
