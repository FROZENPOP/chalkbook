import SwiftUI
import SwiftData

struct SessionEditorView: View {
    @Environment(ClimbingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedGym.name) private var gyms: [SavedGym]
    @State private var selectedGymID: UUID?
    @State private var initialized = false
    var session: ClimbingSession?
    @State private var date = Date.now
    @State private var location = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    GymSelectionRow(selectedID: $selectedGymID)
                    if selectedGymID == nil {
                        TextField("Other location (optional)", text: $location).textInputAutocapitalization(.words)
                            .accessibilityIdentifier("sessionLocation")
                    }
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
                Section("Notes") {
                    TextField("How are you feeling?", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                if session == nil {
                    Section { Text("Everything saves on your device. You can resume this session anytime.").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(session == nil ? "New session" : "Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(session == nil ? "Start" : "Save", action: submit).fontWeight(.semibold)
                        .accessibilityIdentifier("saveSession")
                }
            }
            .onAppear {
                guard !initialized else { return }; initialized = true
                if let session {
                    selectedGymID = session.gymID
                    date = SessionDay.date(for: session.day) ?? .now
                    location = session.location
                    notes = session.notes
                } else { selectedGymID = gyms.first(where: \.isDefault)?.id ?? gyms.first?.id }
            }
        }
        .safeAreaInset(edge: .top) { SaveErrorBanner() }
    }

    private func submit() {
        let gym = gyms.first { $0.id == selectedGymID }
        if let session {
            if store.save({
                session.day = SessionDay.key(for: date)
                session.location = gym?.name ?? location.trimmingCharacters(in: .whitespacesAndNewlines)
                session.gymID = gym?.id
                session.notes = notes
            }) { dismiss() }
        } else if store.start(date: date, location: location, notes: notes, gym: gym) != nil {
            dismiss()
        }
    }
}
