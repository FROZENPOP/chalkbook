import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \ClimbingSession.day, order: .reverse) private var sessions: [ClimbingSession]
    @State private var sheet: SessionSheet?
    private var active: ClimbingSession? { sessions.first { !$0.isComplete } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label("CLIMB LOG", systemImage: "figure.climbing")
                        .font(.caption.weight(.bold)).tracking(2).foregroundStyle(ClimbTheme.forest)
                    Spacer()
                    Text(Date.now, format: .dateTime.month(.abbreviated).day()).font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(active == nil ? "Your next move." : "Keep climbing.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Small attempts. Real progress.").font(.subheadline).foregroundStyle(.secondary)
                }
                Surface {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "mountain.2.fill").font(.system(size: 44)).foregroundStyle(ClimbTheme.forest)
                        Text(active == nil ? "A good session starts here." : "You have a session in progress.")
                            .font(.title2.weight(.semibold))
                        Text(active?.title ?? "Log your climbs, celebrate your sends, and keep track of what’s next.")
                            .foregroundStyle(.secondary)
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
                    HStack(alignment: .top) {
                        Metric(value: "\(sessions.count)", label: "sessions")
                        Metric(value: "\(sessions.reduce(0) { $0 + $1.completedClimbs })", label: "climbs sent")
                        Metric(value: "\(sessions.reduce(0) { $0 + $1.attemptCount })", label: "attempts")
                    }
                }
                if !sessions.isEmpty {
                    Text("Recent sessions").font(.title3.bold())
                    ForEach(Array(sessions.prefix(3))) { session in
                        NavigationLink { SessionDetailView(session: session) } label: {
                            Surface { SessionRow(session: session) }
                        }.buttonStyle(.plain)
                    }
                } else {
                    Label("Your log grows one session at a time.", systemImage: "leaf")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .background(ClimbTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { _ in SessionEditorView() }
    }
}

enum SessionSheet: String, Identifiable {
    case new, edit, addClimb
    var id: String { rawValue }
}
