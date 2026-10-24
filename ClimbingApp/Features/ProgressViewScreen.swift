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
    private var summary: ProgressSummary { ProgressSummary(climbs: filtered.flatMap(\.climbs).map(\.snapshot)) }
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
            VStack(alignment: .leading, spacing: 20) {
                Picker("Time range", selection: $range) { ForEach(ProgressRange.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                if filtered.isEmpty {
                    EmptyState(title: "Progress takes practice", symbol: "chart.bar.xaxis", message: "Your sessions and sends will show up here as you climb.")
                } else {
                    Text("Every attempt counts.").font(.title2.bold())
                    Surface {
                        HStack {
                            Metric(value: "\(filtered.count)", label: "sessions")
                            Metric(value: "\(summary.attempts)", label: "attempts")
                            Metric(value: "\(summary.sends)", label: "sends")
                        }
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Climbs completed").font(.headline)
                            Text(summary.completionRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "No attempts yet")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(ClimbTheme.forest)
                            Text("\(summary.completed) of \(summary.attempted) attempted climbs. Repeat sends count once here.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Sessions per week").font(.headline)
                            Chart(weeks) { week in
                                BarMark(x: .value("Week", SessionDay.date(for: week.day) ?? .now, unit: .weekOfYear), y: .value("Sessions", week.sessions))
                                    .foregroundStyle(ClimbTheme.forest).cornerRadius(5)
                            }.frame(height: 160)
                            .accessibilityLabel("Weekly activity")
                            .accessibilityValue("\(filtered.count) sessions across \(weeks.count) weeks with activity")
                            Text("Weeks begin on your calendar’s first weekday.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            Picker("Grade scale", selection: $scale) { ForEach(GradeScale.allCases) { Text($0.rawValue).tag($0) } }
                                .pickerStyle(.menu)
                            if scale != .custom {
                            HStack {
                                Text("Highest logged send").font(.headline)
                                Spacer()
                                Text(summary.highestSend(in: scale) ?? "—").font(.title2.bold()).foregroundStyle(ClimbTheme.forest)
                            }
                            }
                            if scale == .custom {
                                if summary.customScales.isEmpty { Text("No custom-scale attempts yet.").foregroundStyle(.secondary) }
                                ForEach(summary.customScales) { group in
                                    Text(group.title).font(.headline)
                                    ForEach(group.grades) { grade in
                                        HStack {
                                            Text(grade.grade).font(.subheadline.bold())
                                            Spacer()
                                            Text("\(grade.completed) / \(grade.attempted) climbs sent").font(.caption).foregroundStyle(.secondary)
                                        }.accessibilityElement(children: .combine)
                                    }
                                }
                            }
                            let grades = summary.grades(in: scale)
                            if grades.isEmpty && scale != .custom {
                                Text("No graded attempts in this scale yet.").foregroundStyle(.secondary)
                            } else {
                                ForEach(grades) { grade in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(grade.grade).font(.subheadline.bold())
                                            Spacer()
                                            Text("\(grade.completed) / \(grade.attempted) climbs sent").font(.caption).foregroundStyle(.secondary)
                                        }
                                        SwiftUI.ProgressView(value: grade.rate).tint(ClimbTheme.forest)
                                    }.accessibilityElement(children: .combine)
                                }
                            }
                            Text("Gym scales stay separate. Custom labels are shown in your gym’s saved order when available, and never converted into V grades.")
                                .font(.caption).foregroundStyle(.secondary)
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
    var id: String { day }
}
