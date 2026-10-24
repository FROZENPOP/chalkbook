import SwiftUI

struct SessionDetailView: View {
    @Environment(ClimbingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let session: ClimbingSession
    @State private var sheet: SessionSheet?
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(SessionDay.label(for: session.day)).font(.subheadline).foregroundStyle(.secondary)
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(session.isComplete ? "Session complete" : "In progress", systemImage: session.isComplete ? "checkmark.circle.fill" : "circle.dotted")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(ClimbTheme.forest)
                        HStack {
                            Metric(value: "\(session.attemptCount)", label: "attempts")
                            Metric(value: "\(session.sendCount)", label: "sends")
                            Metric(value: "\(session.completedClimbs)", label: "climbs sent")
                        }
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
                if session.climbs.isEmpty {
                    EmptyState(title: "Find your first boulder", symbol: "figure.climbing", message: "Add a climb and record each try along the way.")
                }
                ForEach(session.orderedClimbs) { climb in
                    ClimbCard(climb: climb, canLog: !session.isComplete)
                }
                if !session.isComplete {
                    Button { store.finish(session) } label: {
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
        .confirmationDialog("Delete this session and all its attempts?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete session", role: .destructive) {
                if store.delete(session) { dismiss() }
            }
        }
    }
}

struct ClimbCard: View {
    @Environment(ClimbingStore.self) private var store
    let climb: ClimbEntry
    let canLog: Bool
    @State private var editing: ClimbEntry?
    @State private var cooldown = false
    @State private var mediaPreview: RouteMediaDraft?

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Text(climb.grade).font(.system(.title2, design: .rounded, weight: .bold))
                        .padding(12).background(ClimbTheme.forest.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(climb.title).font(.headline)
                        Text(climb.resultLabel).font(.subheadline)
                            .foregroundStyle(climb.isSent ? ClimbTheme.forest : .secondary)
                        Text("\(climb.attempts.count) attempts · \(climb.sendCount) sends").font(.caption).foregroundStyle(.secondary)
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
                if !climb.styles.isEmpty {
                    Text(climb.styles.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                if !climb.notes.isEmpty { Text(climb.notes).font(.subheadline).foregroundStyle(.secondary) }
                if canLog {
                    HStack(spacing: 12) {
                        Button { record(sent: false) } label: { Label("Attempt", systemImage: "arrow.clockwise").frame(maxWidth: .infinity).padding(.vertical, 5) }
                            .buttonStyle(.bordered).accessibilityIdentifier("logAttempt")
                        Button { record(sent: true) } label: { Label("Send", systemImage: "checkmark").frame(maxWidth: .infinity).padding(.vertical, 5) }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("logSend")
                    }.disabled(cooldown)
                }
                if !climb.attempts.isEmpty {
                    Button { store.undo(on: climb) } label: { Label("Undo last attempt", systemImage: "arrow.uturn.backward") }
                        .font(.caption).frame(minHeight: 32).accessibilityIdentifier("undoAttempt")
                }
            }
        }
        .sheet(item: $mediaPreview) { RouteMediaPreview(item: $0) }
        .sheet(item: $editing) { entry in
            if let session = entry.session { ClimbEditorView(session: session, climb: entry) }
        }
    }

    private func record(sent: Bool) {
        store.record(sent: sent, on: climb)
        cooldown = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            cooldown = false
        }
    }
}
