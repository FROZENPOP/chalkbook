import SwiftUI

struct AggregateEditorView: View {
    @Environment(ClimbingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let session: ClimbingSession
    var existing: AggregateEntry? = nil
    @State private var coverage = ActivityCoverage.additional
    @State private var attempts = ""
    @State private var sends = ""
    @State private var label = ""
    @State private var initialized = false

    private var batch: ActivityBatch { ActivityBatch(coverage: coverage, attempts: Int(attempts), sends: Int(sends)) }
    private var validation: [String] {
        var errors = JournalRules.totals(detailedAttempts: session.recordedAttempts.count, detailedSends: session.recordedAttempts.filter(\.sent).count,
            batches: session.aggregates.filter { $0.id != existing?.id }.map(\.batch) + [batch]).conflicts
        if (!attempts.isEmpty && Int(attempts) == nil) || (!sends.isEmpty && Int(sends) == nil) { errors.append("Use whole numbers, or leave a total blank when unknown.") }
        return errors
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Coverage", selection: $coverage) { ForEach(ActivityCoverage.allCases) { Text($0.title).tag($0) } }.accessibilityIdentifier("recapCoverage")
                    Text(coverage == .additional ? "Only activity beyond your individual entries and other batches. Each batch must cover distinct activity." : "Describes the entire session. This replaces each supplied metric’s detailed total; it is never added to it.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("What do you remember?") {
                    TextField("Attempts — unknown if blank", text: $attempts).keyboardType(.numberPad).accessibilityIdentifier("recapAttempts")
                    TextField("Sends — unknown if blank", text: $sends).keyboardType(.numberPad).accessibilityIdentifier("recapSends")
                    TextField("Batch description (optional)", text: $label)
                    Text("Sends do not imply attempts, unique climbs, or flashes. Recalled totals never create individual attempts.").font(.caption)
                }
                Section("Recorded evidence") { Text("\(session.recordedAttempts.count) individual attempts · \(session.recordedAttempts.filter(\.sent).count) sends") }
                if !validation.isEmpty { Section("Resolve before saving") { ForEach(validation, id: \.self) { Text($0).foregroundStyle(.red) } } }
                if let existing {
                    Section { Button("Delete recalled entry", role: .destructive) {
                        if store.save({ session.aggregates.removeAll { $0.id == existing.id }; store.context.delete(existing) }) { dismiss() }
                    } }
                }
            }
            .navigationTitle("Recalled activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if store.saveAggregate(existing, session: session, coverage: coverage, attempts: Int(attempts), sends: Int(sends), label: label) { dismiss() }
                }.disabled(!validation.isEmpty).accessibilityIdentifier("saveRecap") }
            }
            .onAppear {
                guard !initialized else { return }; initialized = true
                if let existing { coverage = existing.batch.coverage; attempts = existing.attempts.map(String.init) ?? ""; sends = existing.sends.map(String.init) ?? ""; label = existing.label }
            }
        }.safeAreaInset(edge: .top) { SaveErrorBanner() }
    }
}

struct AttemptEditorView: View {
    @Environment(ClimbingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let attempt: ClimbAttempt
    @State private var sent = false
    @State private var date = Date.now
    @State private var order = 1
    @State private var precision = "day"
    @State private var delete = false
    var body: some View {
        NavigationStack {
            Form {
                Toggle("Sent", isOn: $sent)
                DatePicker("Occurrence day", selection: $date, in: ...Date.now, displayedComponents: .date)
                Stepper("Order on this climb: \(order)", value: $order, in: 1...100000)
                Picker("Time precision", selection: $precision) { Text("Day only").tag("day"); Text("Unknown").tag("unknown"); Text("Recorded timestamp").tag("exact") }
                Text("Changing day or order recalculates flash history. The linked session stays the same. Exact time is only known when recorded live.").font(.caption)
                if let data = attempt.gradeSnapshot.data(using: .utf8), let descriptor = try? JSONDecoder().decode(GradeDescriptor.self, from: data) {
                    Text("Difficulty when logged: \(descriptor.label)").font(.subheadline)
                }
                Button("Delete attempt", role: .destructive) { delete = true }
            }
            .navigationTitle("Correct attempt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if store.updateAttempt(attempt, sent: sent, day: SessionDay.key(for: date), sequence: order, precision: precision) { dismiss() }
                } }
            }
            .onAppear { sent = attempt.sent; date = SessionDay.date(for: attempt.sessionDay) ?? .now; order = attempt.sequence; precision = attempt.timePrecision }
            .confirmationDialog("Delete this attempt?", isPresented: $delete, titleVisibility: .visible) {
                Button("Delete attempt", role: .destructive) { if store.removeAttempt(attempt) { dismiss() } }
            } message: { Text("History will be marked incomplete. A remaining first send will not become a confirmed flash just because an earlier record was deleted.") }
        }.safeAreaInset(edge: .top) { SaveErrorBanner() }
    }
}

struct FinishReviewView: View {
    @Environment(ClimbingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let session: ClimbingSession
    @State private var recalling = false
    @State private var editing = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Review") {
                    Text("\(session.recordedAttempts.count) recorded attempts · \(session.completedClimbs) distinct climbs sent")
                    Text(session.totals.label)
                    Text("Attempts: \(session.totals.attempts.map(String.init) ?? "Unknown") · Sends: \(session.totals.sends.map(String.init) ?? "Unknown")")
                }
                Section {
                    Button("Add missing remembered activity") { recalling = true }
                    Button("Edit times and notes") { editing = true }
                    Text("You can correct individual entries from session details after finishing.").font(.caption)
                }
                Button("Finish and save") {
                    store.finish(session)
                    if store.errorMessage == nil { dismiss() }
                }.accessibilityIdentifier("confirmFinishSession")
            }.navigationTitle("Finish and review")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Keep climbing") { dismiss() } } }
            .sheet(isPresented: $recalling) { AggregateEditorView(session: session) }
            .sheet(isPresented: $editing) { SessionEditorView(session: session) }
        }.safeAreaInset(edge: .top) { SaveErrorBanner() }
    }
}

struct ManualAttemptView: View {
    @Environment(ClimbingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let session: ClimbingSession
    @State private var selectedID: UUID?
    @State private var outcome = ""
    @State private var disjoint = false
    @State private var creating = false
    @State private var choosing = false
    var body: some View {
        NavigationStack {
            Form {
                Picker("Climb", selection: $selectedID) {
                    Text("Choose a climb").tag(UUID?.none)
                    ForEach(session.allClimbs) { Text($0.title + " · " + $0.descriptor.label).tag(Optional($0.id)) }
                }
                Button("Choose another saved climb") { choosing = true }
                Button("Create a new climb") { creating = true }
                Picker("Outcome", selection: $outcome) { Text("Choose an outcome").tag(""); Text("Failed").tag("failed"); Text("Sent").tag("sent") }
                Text("This creates one individual attempt on the session day with unknown exact time. Use remembered totals instead when you do not know individual results.").font(.caption)
                if !session.aggregates.isEmpty {
                    Toggle("This is beyond recalled activity, or I reduced its batch first", isOn: $disjoint)
                    Text("Edit recalled entries before converting any of their activity into individual attempts. Whole-session totals must still cover all detailed evidence.").font(.caption)
                }
            }.navigationTitle("Add remembered attempt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    guard let climb = session.allClimbs.first(where: { $0.id == selectedID }) else { return }
                    let sent = outcome == "sent"
                    let total = JournalRules.totals(detailedAttempts: session.recordedAttempts.count + 1, detailedSends: session.recordedAttempts.filter(\.sent).count + (sent ? 1 : 0), batches: session.aggregates.map(\.batch))
                    if let error = total.conflicts.first { store.errorMessage = error; return }
                    if store.save({
                        let attempt = ClimbAttempt(sequence:(climb.attempts.map(\.sequence).max() ?? 0)+1,sent:sent)
                        attempt.sessionID = session.id; attempt.daySnapshot = session.day; attempt.timePrecision = "day"; attempt.gradeSnapshot = climb.descriptor.encoded
                        store.context.insert(attempt); climb.attempts.append(attempt)
                    }) { dismiss() }
                }.disabled(selectedID == nil || outcome.isEmpty || (!session.aggregates.isEmpty && !disjoint)) }
            }
            .sheet(isPresented: $creating) { ClimbEditorView(session:session) }
            .sheet(isPresented: $choosing) { ExistingClimbPicker(session:session) }
        }.safeAreaInset(edge:.top) { SaveErrorBanner() }
    }
}
