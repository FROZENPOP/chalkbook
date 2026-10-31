import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(ProfileStore.self) private var profiles
    @Query(sort: \ClimbingSession.day, order: .reverse) private var sessions: [ClimbingSession]
    @State private var pastRecap = false
    @State private var sheet: SessionSheet?
    private var active: ClimbingSession? { sessions.first { !$0.isComplete } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label("CLIMB LOG", systemImage: "figure.climbing")
                        .font(.caption.weight(.bold)).tracking(2).foregroundStyle(ClimbTheme.forest)
                    Spacer()
                    Text(Date.now, format: .dateTime.month(.abbreviated).day()).font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(active == nil ? "Your next move." : "Keep climbing.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Small attempts. Real progress.").font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
                }
                Surface {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "mountain.2.fill").accessibilityHidden(true).font(.system(size: 44)).foregroundStyle(ClimbTheme.forest)
                        Text(active == nil ? "A good session starts here." : "You have a session in progress.")
                            .font(.title2.weight(.semibold))
                        Text(active?.title ?? "Log your climbs, celebrate your sends, and keep track of what’s next.")
                            .foregroundStyle(ClimbTheme.secondaryText)
                        if let active {
                            NavigationLink { SessionDetailView(session: active) } label: {
                                Label("Resume session", systemImage: "arrow.right").frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("resumeSession")
                        } else {
                            Button { sheet = .new } label: {
                                Label("Start session", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("startSession")
                        }
                    }
                }
                Surface {
                    JournalMetrics(first: "\(sessions.count)", firstLabel: "sessions", second: "\(JournalStatistics(sessions: sessions).distinctClimbsSent)", secondLabel: "climbs sent", third: JournalStatistics(sessions: sessions).knownAttempts.map(String.init) ?? "Unknown", thirdLabel: "attempts")
                }
                Button("Log a past session", systemImage: "calendar.badge.plus") { pastRecap = true }.frame(minHeight: 44).accessibilityIdentifier("pastSession")
                NavigationLink("Browse all history") { HistoryView() }.frame(minHeight: 44)
                if !sessions.isEmpty {
                    Text("Recent sessions").font(.title3.bold())
                    ForEach(Array(sessions.prefix(3))) { session in
                        NavigationLink { SessionDetailView(session: session) } label: {
                            Surface { SessionRow(session: session) }
                        }.buttonStyle(.plain)
                    }
                } else {
                    Label("Your log grows one session at a time.", systemImage: "leaf")
                        .font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
                }
            }
            .padding(20)
        }
        .background(ClimbTheme.background)
        .navigationTitle("Journal")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: {
                    ProfileAvatar(photo: profiles.profile?.photo, size: 32)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your profile")
                .accessibilityIdentifier("openSettings")
            }
        }
        .sheet(isPresented: $pastRecap) { SessionEditorView(isRecap: true) }
        .sheet(item: $sheet) { _ in SessionEditorView() }
    }
}

enum SessionSheet: String, Identifiable {
    case new, edit, addClimb
    var id: String { rawValue }
}
