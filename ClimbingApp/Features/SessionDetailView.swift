import SwiftUI

struct SessionDetailView: View {
    @Environment(ClimbingStore.self) private var store
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let session: ClimbingSession
    @State private var sheet: SessionSheet?
    @State private var confirmDelete = false
    @State private var chooseExisting = false
    @State private var addingRecap = false
    @State private var editingAggregate: AggregateEntry?
    @State private var editingAttempt: ClimbAttempt?
    @State private var reviewing = false
    @State private var health = false
    @State private var manualAttempt = false
    @State private var sharing = false
    private var selected: ClimbEntry? { session.allClimbs.first { $0.id == session.selectedClimbID } ?? session.orderedClimbs.last }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(SessionDay.label(for: session.day)).font(.subheadline).foregroundStyle(.secondary)
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(session.isComplete ? "Session complete" : "In progress", systemImage: session.isComplete ? "checkmark.circle.fill" : "circle.dotted")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(ClimbTheme.forest)
                        JournalMetrics(first: session.totals.attempts.map(String.init) ?? "Unknown", firstLabel: "attempts", second: session.totals.sends.map(String.init) ?? "Unknown", secondLabel: "sends", third: "\(session.completedClimbs)", thirdLabel: "identified climbs sent")
                        Text(session.totals.label).font(.caption).foregroundStyle(.secondary)
                        if let minutes = session.durationMinutes { Text("Recorded duration: \(minutes) minutes").font(.caption) }
                        else { Text("Session duration not recorded").font(.caption).foregroundStyle(.secondary) }
                        if !session.notes.isEmpty { Text(session.notes).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
                HStack {
                    Text("Your climbs").font(.title2.bold())
                    Spacer()
                    if !session.isComplete {
                        Button { sheet = .addClimb } label: { Label("Add climb", systemImage: "plus") }
                            .buttonStyle(.bordered).accessibilityIdentifier("addClimb")
                    }
                }
                if !session.isComplete {
                    Button("Choose existing climb or project", systemImage: "square.stack") { chooseExisting = true }.frame(minHeight: 44).accessibilityIdentifier("chooseExistingClimb")
                }
                if session.allClimbs.isEmpty {
                    EmptyState(title: "Find your first boulder", symbol: "figure.climbing", message: "Add a climb and record each try along the way.")
                }
                if let selected { ClimbCard(climb: selected, canLog: !session.isComplete, loggingSession: session) }
                if !session.isComplete, !session.recordedAttempts.isEmpty {
                    Button { store.undoLatest(in: session) } label: { Label("Undo latest logged attempt", systemImage: "arrow.uturn.backward").frame(minHeight: 44) }.accessibilityIdentifier("undoLatestAttempt")
                }
                ForEach(session.orderedClimbs.filter { $0.id != selected?.id }) { climb in
                    Button { _ = store.select(climb, in: session) } label: {
                        Surface { VStack(alignment: .leading) { Text(climb.title).font(.headline); Text(climb.descriptor.label).font(.subheadline); Text("Select to log").font(.caption).foregroundStyle(.secondary) } }
                    }.buttonStyle(.plain)
                }
                Text("Recalled activity").font(.title2.bold())
                Text("Additional batches cover distinct unlogged activity. Whole-session totals replace detailed totals. Reduce or remove a batch explicitly before replacing it with individual entries.").font(.caption).foregroundStyle(.secondary)
                ForEach(session.aggregates) { entry in
                    Button { editingAggregate = entry } label: {
                        Surface { VStack(alignment: .leading) {
                            Text(entry.batch.coverage.title).font(.headline)
                            Text("\(entry.attempts.map(String.init) ?? "Unknown") attempts · \(entry.sends.map(String.init) ?? "Unknown") sends")
                            if !entry.label.isEmpty { Text(entry.label).font(.caption) }
                        } }
                    }.buttonStyle(.plain)
                }
                Button("Add remembered totals", systemImage: "plus.rectangle.on.folder") { addingRecap = true }.frame(minHeight: 44).accessibilityIdentifier("addRecap")
                Button("Link Apple Health workout", systemImage: "heart.text.square") { health = true }.frame(minHeight: 44)
                Button("Add an individual attempt from memory") { manualAttempt = true }.frame(minHeight: 44)
                DisclosureGroup("Recorded attempts — tap to correct") {
                    ForEach(session.recordedAttempts.sorted { $0.recordedAt < $1.recordedAt }) { attempt in
                        Button { editingAttempt = attempt } label: {
                            Label("\(attempt.climb?.title ?? "Boulder") · \(attempt.sent ? "Sent" : "Failed") · \(attempt.sessionDay)", systemImage: attempt.sent ? "checkmark.circle" : "xmark.circle").frame(minHeight: 44)
                        }
                    }
                }
                if !session.isComplete {
                    Button { reviewing = true } label: {
                        Label("Finish session", systemImage: "checkmark").frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("finishSession")
                }
            }.padding(20)
        }
        .background(ClimbTheme.background)
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Edit session", systemImage: "pencil") { sheet = .edit }
                if session.isComplete { Button("Share / privacy", systemImage: "square.and.arrow.up") { sharing = true } }
                Button("Delete session", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: { Label("Session options", systemImage: "ellipsis.circle") }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .edit: SessionEditorView(session: session)
            case .addClimb: ClimbEditorView(session: session)
            case .new: SessionEditorView()
            }
        }
        .sheet(isPresented: $chooseExisting) { ExistingClimbPicker(session: session) }
        .sheet(isPresented: $addingRecap) { AggregateEditorView(session: session) }
        .sheet(item: $editingAggregate) { AggregateEditorView(session: session, existing: $0) }
        .sheet(item: $editingAttempt) { AttemptEditorView(attempt: $0) }
        .sheet(isPresented: $manualAttempt) { ManualAttemptView(session: session) }
        .sheet(isPresented: $health) { HealthLinkView(session: session) }
        .sheet(isPresented: $reviewing) { FinishReviewView(session: session) }
        .sheet(isPresented: $sharing) { ShareSessionView(session: session) }
        .confirmationDialog("Delete this session and its recorded activity?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete session", role: .destructive) {
                Task {
                    // Remove any published snapshot first. On network failure retain the local session for retry.
                    if social.configuration != nil && auth.account != nil {
                        guard await social.removeShare(auth, sessionID: session.id) else {
                            store.errorMessage = social.errorMessage; return
                        }
                    }
                    if store.delete(session) { dismiss() }
                }
            }
        } message: { Text("Its attempts, recalled entries, and any shared recap will be removed. Removing a shared recap needs a connection. Climbs, projects, notebooks, media, and other sessions stay in your journal.") }
    }
}

struct ClimbCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(ClimbingStore.self) private var store
    let climb: ClimbEntry
    let canLog: Bool
    var loggingSession: ClimbingSession? = nil
    private var displayedAttempts: [ClimbAttempt] { guard let loggingSession else { return climb.attempts }; return climb.attempts.filter { $0.effectiveSessionID == loggingSession.id } }
    @State private var editing: ClimbEntry?
    @State private var cooldown = false
    @State private var pendingOutcome: Bool?
    @State private var mediaPreview: RouteMediaDraft?

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                let header = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                header {
                    Text(climb.descriptor.label).font(.system(.title2, design: .rounded, weight: .bold))
                        .padding(12).background(ClimbTheme.forest.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(climb.title).font(.headline)
                        Text(climb.resultLabel).font(.subheadline)
                            .foregroundStyle(climb.isSent ? ClimbTheme.forest : .secondary)
                        Text("\(displayedAttempts.count) attempts · \(displayedAttempts.filter(\.sent).count) sends this session").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button { editing = climb } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
                        .accessibilityLabel("Edit \(climb.title)")
                }
                if !climb.gymName.isEmpty {
                    Text(climb.gymName + (climb.scale == .custom ? " · " + climb.customScaleName : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(climb.media) { media in
                    Button { mediaPreview = media.draft } label: { MediaLabel(kind: media.kind, filename: media.filename) }
                }
                NavigationLink("Notebook and complete history") { ProjectDetailView(climb: climb) }.frame(minHeight: 44)
                if !climb.styles.isEmpty {
                    Text(climb.styles.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                if !climb.notes.isEmpty { Text(climb.notes).font(.subheadline).foregroundStyle(.secondary) }
                if canLog {
                    ProjectNotebookSummary(climb:climb)
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                    layout {
                        Button { record(sent: false) } label: { Label("Failed", systemImage: "arrow.clockwise").frame(maxWidth: .infinity).frame(minHeight: 52) }
                            .buttonStyle(.bordered).accessibilityIdentifier("logAttempt")
                        Button { record(sent: true) } label: { Label("Sent", systemImage: "checkmark").frame(maxWidth: .infinity).frame(minHeight: 52) }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("logSend")
                    }.disabled(cooldown)
                }
                if loggingSession == nil && !climb.attempts.isEmpty {
                    Button { store.undo(on: climb) } label: { Label("Undo last attempt", systemImage: "arrow.uturn.backward") }
                        .font(.caption).frame(minHeight: 44).accessibilityIdentifier("undoAttempt")
                }
            }
        }
        .confirmationDialog("Does this attempt overlap recalled activity?", isPresented: Binding(get: { pendingOutcome != nil }, set: { if !$0 { pendingOutcome = nil } }), titleVisibility: .visible) {
            Button("New activity beyond recalled batches") { if let sent = pendingOutcome { performRecord(sent: sent) }; pendingOutcome = nil }
            Button("Review recalled activity first") { store.errorMessage = "Reduce or replace the recalled batch before logging its individual details."; pendingOutcome = nil }
        }
        .sheet(item: $mediaPreview) { RouteMediaPreview(item: $0) }
        .sheet(item: $editing) { entry in
            ClimbEditorView(session: loggingSession ?? entry.session, climb: entry)
        }
    }

    private func record(sent: Bool) {
        if loggingSession?.aggregates.contains(where: { $0.batch.coverage == .additional }) == true { pendingOutcome = sent }
        else { performRecord(sent: sent) }
    }

    private func performRecord(sent: Bool) {
        store.record(sent: sent, on: climb, in: loggingSession)
        cooldown = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            cooldown = false
        }
    }
}
