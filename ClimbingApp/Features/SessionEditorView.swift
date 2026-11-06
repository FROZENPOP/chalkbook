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
    var onStart: (ClimbingSession) -> Void = { _ in }
    @State private var startTime = Date.now
    @State private var endTime = Date.now
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
                    if isRecap { DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date) }
                }
                if session != nil {
                    Section(header: Text("Time").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        DatePicker("Started", selection: $startTime, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                        if session?.isComplete == true {
                            DatePicker("Ended", selection: $endTime, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                            LabeledContent("Duration", value: durationLabel)
                            if let session, session.pausedSeconds >= 60 { LabeledContent("Paused", value: Int(session.pausedSeconds / 60).counted("minute")) }
                        }
                    }
                } else if isRecap {
                    Section(header: Text("Duration").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        TextField("Minutes (optional)", text: $minutes).keyboardType(.numberPad)
                    }
                }
                Section(header: Text("Notes").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    TextField("How are you feeling?", text: $notes, axis: .vertical).lineLimit(3...6)
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
                    startTime = session.startedAt; endTime = session.endedAt ?? .now
                } else { selectedGymID = gyms.first(where: \.isDefault)?.id ?? gyms.first?.id }
            }
        }
        .environment(\.timeZone, session.flatMap { TimeZone(identifier: $0.timeZoneID) } ?? .current)
        .sheet(item: $created, onDismiss: { dismiss() }) { AggregateEditorView(session: $0) }
        .safeAreaInset(edge: .top) { SaveErrorBanner() }
    }

    private func timesChanged(_ session: ClimbingSession) -> Bool {
        startTime != session.startedAt || (session.isComplete && endTime != session.endedAt)
    }

    private var durationLabel: String {
        guard let session, session.durationKnown || timesChanged(session) else { return "Not recorded" }
        return max(0, Int((endTime.timeIntervalSince(startTime) - session.pausedSeconds) / 60)).counted("minute")
    }

    private func submit() {
        let gym = gyms.first { $0.id == selectedGymID }
        if let session {
            if store.save({
                let oldDay = session.day
                if timesChanged(session) { session.durationKnown = true }
                session.day = SessionDay.key(for: startTime, in: TimeZone(identifier: session.timeZoneID) ?? .current)
                session.location = gym?.name ?? location.trimmingCharacters(in: .whitespacesAndNewlines)
                session.gymID = gym?.id
                guard session.isComplete == false || endTime >= startTime else { throw BackupError.invalid("End time must follow start time.") }
                session.startedAt = startTime; if session.isComplete { session.endedAt = endTime }
                session.updatedAt = .now
                for attempt in session.recordedAttempts where attempt.daySnapshot == oldDay || attempt.daySnapshot.isEmpty { attempt.daySnapshot = session.day; attempt.timePrecision = "day" }
                session.notes = notes
            }) { dismiss() }
        } else if isRecap {
            let entered = minutes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !entered.isEmpty && !(0...10_080).contains(Int(entered) ?? -1) { store.errorMessage = "Enter a duration of up to 10,080 minutes (one week), or leave it blank."; return }
            created = store.createRecap(date: date, gym: gym, location: location, notes: notes, minutes: Int(entered))
        } else if let started = store.start(date: .now, location: location, notes: notes, gym: gym) {
            onStart(started)
            dismiss()
        }
    }
}
