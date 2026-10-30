import SwiftUI
import SwiftData

struct SessionEditorView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(ClimbingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedGym.name) private var gyms: [SavedGym]
    @State private var selectedGymID: UUID?
    @State private var initialized = false
    var session: ClimbingSession?
    var isRecap = false
    @State private var startTime = Date.now
    @State private var endTime = Date.now
    @State private var durationKnown = false
    @State private var minutes = ""
    @State private var created: ClimbingSession?
    @State private var date = Date.now
    @State private var location = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Session").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    GymSelectionRow(selectedID: $selectedGymID)
                    if selectedGymID == nil {
                        TextField("Other location (optional)", text: $location, axis: .vertical).lineLimit(1...3).textInputAutocapitalization(.words)
                            .accessibilityIdentifier("sessionLocation").frame(minHeight: 44)
                    }
                    if session == nil { DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date) }
                }
                Section(header: Text("Time (optional for a recap)").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    if session != nil {
                        DatePicker("Started", selection: $startTime, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                        if session?.isComplete == true { DatePicker("Ended", selection: $endTime, in: ...Date.now, displayedComponents: [.date, .hourAndMinute]) }
                    }
                    Toggle("Duration is known", isOn: $durationKnown)
                    if isRecap { TextField("Minutes", text: $minutes).keyboardType(.numberPad) }
                }
                Section(header: Text("Notes").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    TextField("How are you feeling?", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                if session == nil {
                    Section { Text("Everything saves on your device. You can resume this session anytime.").foregroundStyle(ClimbTheme.secondaryText) }
                }
            }
            .id(textSize)
            .navigationTitle(session == nil ? (isRecap ? "Past session recap" : "New session") : "Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() }.accessibleToolbarAction() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(session == nil ? (isRecap ? "Create recap" : "Start") : "Save", systemImage: session == nil ? "play.fill" : "checkmark", action: submit).fontWeight(.semibold)
                        .accessibleToolbarAction().accessibilityIdentifier("saveSession")
                }
            }
            .onAppear {
                guard !initialized else { return }; initialized = true
                if let session {
                    selectedGymID = session.gymID
                    date = SessionDay.date(for: session.day) ?? .now
                    location = session.location
                    notes = session.notes
                    startTime = session.startedAt; endTime = session.endedAt ?? .now; durationKnown = session.durationKnown
                } else { selectedGymID = gyms.first(where: \.isDefault)?.id ?? gyms.first?.id }
            }
        }
        .environment(\.timeZone, session.flatMap { TimeZone(identifier: $0.timeZoneID) } ?? .current)
        .sheet(item: $created, onDismiss: { dismiss() }) { AggregateEditorView(session: $0) }
        .safeAreaInset(edge: .top) { SaveErrorBanner() }
    }

    private func submit() {
        let gym = gyms.first { $0.id == selectedGymID }
        if let session {
            if store.save({
                let oldDay = session.day
                session.day = SessionDay.key(for: startTime, in: TimeZone(identifier: session.timeZoneID) ?? .current)
                session.location = gym?.name ?? location.trimmingCharacters(in: .whitespacesAndNewlines)
                session.gymID = gym?.id
                guard session.isComplete == false || endTime >= startTime else { throw BackupError.invalid("End time must follow start time.") }
                session.startedAt = startTime; if session.isComplete { session.endedAt = endTime }
                session.durationKnown = durationKnown; session.updatedAt = .now
                for attempt in session.recordedAttempts where attempt.daySnapshot == oldDay || attempt.daySnapshot.isEmpty { attempt.daySnapshot = session.day; attempt.timePrecision = "day" }
                session.notes = notes
            }) { dismiss() }
        } else if isRecap {
            if durationKnown && (Int(minutes) == nil || (Int(minutes) ?? -1) < 0) { store.errorMessage = "Enter a duration in whole minutes or mark it unknown."; return }
            created = store.createRecap(date: date, gym: gym, location: location, notes: notes, minutes: durationKnown ? Int(minutes) : nil)
        } else if store.start(date: date, location: location, notes: notes, gym: gym) != nil {
            dismiss()
        }
    }
}
