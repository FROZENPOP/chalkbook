import SwiftUI
import SwiftData

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
    @State private var manualAttempt = false
    @State private var shareProblem: String?
    @State private var shareNotice: String?
    @State private var postedContent: [String]?
    private var selected: ClimbEntry? { session.allClimbs.first { $0.id == session.selectedClimbID } ?? session.orderedClimbs.last }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(SessionDay.label(for: session.day)).font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(session.isComplete ? "Session complete" : session.isPaused ? "Paused" : "In progress", systemImage: session.isComplete ? "checkmark.circle.fill" : session.isPaused ? "pause.circle" : "circle.dotted")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(ClimbTheme.accent)
                        JournalMetrics(first: session.totals.attempts.map(String.init) ?? "Unknown", firstLabel: "attempts", second: session.totals.sends.map(String.init) ?? "Unknown", secondLabel: "sends", third: "\(session.completedClimbs)", thirdLabel: "climbs sent")
                        if !session.isComplete {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Session time").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                                Text(timerInterval: session.stopwatchStart...Date.distantFuture, pauseTime: session.pausedAt, countsDown: false)
                                    .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                            }
                            .accessibilityElement(children: .combine).accessibilityIdentifier("sessionStopwatch")
                            Button {
                                if session.isPaused { store.resume(session) } else { store.pause(session) }
                            } label: {
                                Label(session.isPaused ? "Resume" : "Pause", systemImage: session.isPaused ? "play.fill" : "pause.fill").frame(minHeight: 32)
                            }
                            .buttonStyle(.bordered).accessibilityIdentifier("pauseSession")
                        } else if let minutes = session.durationMinutes { Text("Recorded duration: \(minutes.counted("minute"))").font(.caption) }
                        else { Text("Session duration not recorded").font(.caption).foregroundStyle(ClimbTheme.secondaryText) }
                        if !session.notes.isEmpty { Text(session.notes).font(.subheadline).foregroundStyle(ClimbTheme.secondaryText) }
                    }
                }
                if let message = shareProblem ?? shareNotice {
                    Surface {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(shareProblem == nil ? message : "Friends wasn’t updated. \(message)").font(.subheadline)
                                .foregroundStyle(shareProblem == nil ? Color.primary : ClimbTheme.error).fixedSize(horizontal: false, vertical: true)
                            Button(shareProblem == nil ? "OK" : "Retry") { if shareProblem == nil { shareNotice = nil } else { syncShare() } }
                                .buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("sessionShareStatus")
                        }
                    }
                }
                HStack {
                    Text("Your climbs").font(.title2.bold()).id("sessionClimbs")
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
                if let selected { ClimbCard(climb: selected, canLog: !session.isComplete, loggingSession: session, onEditorClose: {
                    // Only a change to what the post carries needs a sync.
                    if SharedSession.content(of: session) != postedContent { syncShare() }
                }) }
                if !session.isComplete, !session.recordedAttempts.isEmpty {
                    Button { store.undoLatest(in: session) } label: { Label("Undo latest logged attempt", systemImage: "arrow.uturn.backward").frame(minHeight: 44) }.accessibilityIdentifier("undoLatestAttempt")
                }
                ForEach(session.orderedClimbs.filter { $0.id != selected?.id }) { climb in
                    Button { _ = store.select(climb, in: session) } label: {
                        Surface { VStack(alignment: .leading) { Text(climb.title).font(.headline); Text(climb.descriptor.label).font(.subheadline) } }
                    }.buttonStyle(.plain)
                }
                ForEach(session.aggregates) { entry in
                    Button { editingAggregate = entry } label: {
                        Surface { VStack(alignment: .leading) {
                            Text(entry.batch.coverage.title).font(.headline)
                            Text("\(entry.attempts.map(String.init) ?? "Unknown") attempts · \(entry.sends.map(String.init) ?? "Unknown") sends")
                            if !entry.label.isEmpty { Text(entry.label).font(.caption) }
                        } }
                    }.buttonStyle(.plain)
                }
                Menu {
                    Button("Remembered totals", systemImage: "plus.rectangle.on.folder") { addingRecap = true }.accessibilityIdentifier("addRecap")
                    Button("Single attempt", systemImage: "plus.circle") { manualAttempt = true }.accessibilityIdentifier("addManualAttempt")
                } label: { Label("Add from memory", systemImage: "clock.arrow.circlepath").frame(minHeight: 44) }.accessibilityIdentifier("addFromMemory")
                if !session.recordedAttempts.isEmpty {
                    DisclosureGroup("Recorded attempts") {
                        ForEach(session.recordedAttempts.sorted { $0.recordedAt < $1.recordedAt }) { attempt in
                            Button { editingAttempt = attempt } label: {
                                Label("\(attempt.climb?.title ?? "Boulder") · \(attempt.sent ? "Sent" : "Failed") · \(attempt.sessionDay)", systemImage: attempt.sent ? "checkmark.circle" : "xmark.circle").frame(minHeight: 44)
                            }
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
        .sheet(isPresented: $reviewing, onDismiss: syncShare) { FinishReviewView(session: session) }
        .onAppear { if postedContent == nil { postedContent = SharedSession.content(of: session) } }
        .confirmationDialog("Delete this session and its recorded activity?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete session", role: .destructive) {
                if social.deleteSession(session, store: store, auth: auth) { dismiss() }
            }
        } message: { Text("Its attempts and any shared recap are removed. Climbs and projects stay.") }
    }

    /// Posts a finished session, or media added to it, to Friends. Problems show above the climbs.
    private func syncShare() {
        guard session.isComplete else { return }
        postedContent = SharedSession.content(of: session)
        Task {
            shareProblem = await SessionEditorView.syncShare(social, auth, session)
            shareNotice = social.photoNotice; social.photoNotice = nil
        }
    }
}

struct ClimbCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(ClimbingStore.self) private var store
    let climb: ClimbEntry
    let canLog: Bool
    var loggingSession: ClimbingSession? = nil
    var onEditorClose: () -> Void = {}
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
                        .padding(12).background(ClimbTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(climb.title).font(.headline)
                        Text(climb.resultLabel).font(.subheadline)
                            .foregroundStyle(climb.isSent ? ClimbTheme.accent : ClimbTheme.secondaryText)
                        Text("\(displayedAttempts.count.counted("attempt")) · \(displayedAttempts.filter(\.sent).count.counted("send")) this session").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Button { editing = climb } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
                        .accessibilityLabel("Edit \(climb.title)")
                }
                if !climb.gymName.isEmpty {
                    Text(climb.gymName + (climb.scale == .custom ? " · " + climb.customScaleName : ""))
                        .font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                }
                ForEach(climb.media) { media in
                    Button { mediaPreview = media.draft } label: { MediaLabel(kind: media.kind, filename: media.filename) }
                }
                NavigationLink("Notebook") { ProjectDetailView(climb: climb) }.frame(minHeight: 44)
                if !climb.styles.isEmpty {
                    Text(climb.styles.joined(separator: " · ")).font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                }
                if !climb.notes.isEmpty { Text(climb.notes).font(.subheadline).foregroundStyle(ClimbTheme.secondaryText) }
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
        .sheet(item: $mediaPreview) { item in
            RouteMediaPreview(item: item) { json in
                guard let media = climb.media.first(where: { $0.id == item.id }) else { return false }
                return store.save { media.annotationJSON = json; media.updatedAt = .now }
            }
        }
        .sheet(item: $editing, onDismiss: onEditorClose) { entry in
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
