import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(ProfileStore.self) private var profiles
    @Query(sort: [SortDescriptor(\ClimbingSession.day, order: .reverse), SortDescriptor(\ClimbingSession.startedAt, order: .reverse)]) private var sessions: [ClimbingSession]
    @State private var pastRecap = false
    @State private var sheet: SessionSheet?
    @State private var started: ClimbingSession?
    private var active: ClimbingSession? { sessions.first { !$0.isComplete } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let header = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
                header {
                    Label { Text("SENDR") } icon: { AscentMark().frame(width: 14) }
                        .font(.caption.weight(.bold)).tracking(2).foregroundStyle(ClimbTheme.accent)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("journalBrand")
                    if !textSize.isAccessibilitySize { Spacer() }
                    Text(Date.now, format: .dateTime.month(.abbreviated).day()).font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                        .accessibilityIdentifier("journalDate")
                }
                VStack(spacing: 12) {
                    if let active {
                        Surface {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(active.title).font(.headline)
                                Text(active.isPaused ? "Paused" : "In progress").font(.subheadline.weight(.semibold)).foregroundStyle(ClimbTheme.accent)
                                NavigationLink { SessionDetailView(session: active) } label: {
                                    Label(active.isPaused ? "Open session" : "Resume session", systemImage: "arrow.right").frame(maxWidth: .infinity).padding(.vertical, 6).foregroundStyle(Color(uiColor: .systemBackground))
                                }
                                .buttonStyle(.borderedProminent).accessibilityIdentifier("resumeSession")
                            }
                        }
                    } else {
                        Button { sheet = .new } label: {
                            Label("Start session", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 6).foregroundStyle(Color(uiColor: .systemBackground))
                        }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("startSession")
                    }
                    Button("Log a past session", systemImage: "calendar.badge.plus") { pastRecap = true }.frame(minHeight: 44).accessibilityIdentifier("pastSession")
                }
                .id("journalSessionActions")
                if !sessions.isEmpty {
                    (textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))) {
                        Text("Recent sessions").font(.title3.bold())
                        if !textSize.isAccessibilitySize { Spacer(minLength: 8) }
                        NavigationLink("See all") { HistoryView() }.frame(minHeight: 44).accessibilityIdentifier("browseHistory")
                    }
                    ForEach(Array(sessions.lazy.filter { $0.id != active?.id }.prefix(3))) { session in
                        NavigationLink { SessionDetailView(session: session) } label: {
                            Surface { SessionRow(session: session) }
                        }.buttonStyle(.plain)
                    }
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
        .sheet(item: $sheet) { _ in SessionEditorView(onStart: { started = $0 }) }
        .navigationDestination(item: $started) { SessionDetailView(session: $0) }
    }
}

enum SessionSheet: String, Identifiable {
    case new, edit, addClimb
    var id: String { rawValue }
}
