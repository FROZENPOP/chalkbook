import SwiftUI

/// One finished session as a log: the climbing first, then its Health numbers.
struct SessionLogView: View {
    let session: ClimbingSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Deleting from the journal entry pops back here, and a deleted session can't be read.
        if session.isDeleted || session.modelContext == nil {
            Color.clear.onAppear { dismiss() }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title).font(.system(.title, design: .rounded, weight: .bold))
                        Text(SessionDay.label(for: session.day)).font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
                    }
                    Surface {
                        JournalMetrics(first: session.totals.sends.map(String.init) ?? "Unknown", firstLabel: "sends", second: session.totals.attempts.map(String.init) ?? "Unknown", secondLabel: "attempts", third: session.durationMinutes.map(duration) ?? "Unknown", thirdLabel: "duration")
                    }
                    climbs
                    SessionHealthStatistics(session: session)
                }.padding(20)
            }
            .background(ClimbTheme.background)
            .navigationTitle("Session log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { NavigationLink { SessionDetailView(session: session) } label: { Label("Edit", systemImage: "pencil") }.accessibleToolbarAction().accessibilityIdentifier("openJournalEntry") }
        }
    }

    private func duration(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    @ViewBuilder private var climbs: some View {
        let rows = session.orderedClimbs.map { climb in (climb: climb, attempts: climb.attempts.filter { $0.effectiveSessionID == session.id }) }
        let most = max(1, rows.map(\.attempts.count).max() ?? 1)
        if !rows.isEmpty || !session.aggregates.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Climbs").font(.title3.bold()).accessibilityIdentifier("sessionLogClimbs")
                Surface {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(rows, id: \.climb.id) { row in
                            SessionLogClimbRow(title: row.climb.title, grade: row.climb.descriptor.label, tries: row.attempts.count, sent: row.attempts.contains(where: \.sent), fraction: Double(row.attempts.count) / Double(most))
                        }
                        ForEach(session.aggregates) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.batch.coverage.title).font(.headline)
                                Text("\(entry.attempts.map(String.init) ?? "Unknown") attempts · \(entry.sends.map(String.init) ?? "Unknown") sends").font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
                            }.accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }
}

private struct SessionLogClimbRow: View {
    let title: String
    let grade: String
    let tries: Int
    let sent: Bool
    let fraction: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text("\(grade) · \(tries) \(tries == 1 ? "try" : "tries") · \(sent ? "Sent" : "Not sent")")
                .font(.subheadline).foregroundStyle(sent ? ClimbTheme.accent : ClimbTheme.secondaryText)
            Capsule().fill(.primary.opacity(0.08)).frame(height: 8)
                .overlay(alignment: .leading) {
                    GeometryReader { space in
                        Capsule().fill(sent ? ClimbTheme.accent : ClimbTheme.secondaryText).frame(width: space.size.width * fraction)
                    }
                }
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
