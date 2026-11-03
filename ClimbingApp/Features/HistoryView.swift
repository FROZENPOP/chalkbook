import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(ClimbingStore.self) private var store
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    @Query(sort: [SortDescriptor(\ClimbingSession.day, order: .reverse), SortDescriptor(\ClimbingSession.startedAt, order: .reverse)]) private var sessions: [ClimbingSession]
    @State private var deleting: ClimbingSession?
    @State private var search = ""
    @State private var completedOnly = false

    private var filtered: [ClimbingSession] {
        sessions.filter {
            (!completedOnly || $0.isComplete) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.day.contains(search))
        }
    }

    var body: some View {
        List {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(ClimbTheme.secondaryText).accessibilityHidden(true)
                TextField("Gym or date", text: $search, axis: .vertical).lineLimit(1...3)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("Search history by gym or date").accessibilityIdentifier("historySearch")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                        .accessibilityLabel("Clear history search").accessibilityIdentifier("clearHistorySearch")
                }
            }.frame(minHeight: 44)
            if !sessions.isEmpty {
                Section { Toggle("Completed sessions only", isOn: $completedOnly) }
            }
            if filtered.isEmpty {
                EmptyState(title: sessions.isEmpty ? "Your story starts here" : "No matching sessions", symbol: "clock.arrow.circlepath",
                           message: sessions.isEmpty ? "Start your first session from Today." : "Try another gym, date, or filter.")
                    .listRowBackground(Color.clear)
            }
            ForEach(filtered) { session in
                NavigationLink { SessionDetailView(session: session) } label: { SessionRow(session: session) }
                    .swipeActions { Button("Delete", systemImage: "trash") { deleting = session }.tint(.red) }
            }
        }
        .navigationTitle("History")
        .confirmationDialog("Delete this session and its recorded activity?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { session in
            Button("Delete session", role: .destructive) { _ = social.deleteSession(session, store: store, auth: auth) }
        } message: { _ in Text("Its attempts and any shared recap are removed. Climbs and projects stay.") }
    }
}
