import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \ClimbingSession.day, order: .reverse) private var sessions: [ClimbingSession]
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
            }
        }
        .navigationTitle("History")
    }
}
