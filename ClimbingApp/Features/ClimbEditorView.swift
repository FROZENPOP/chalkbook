import SwiftUI
import SwiftData

struct ClimbEditorView: View {
    @Environment(ClimbingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultGradeScale") private var defaultScale = GradeScale.vScale.rawValue
    @Query(sort: \SavedGym.name) private var gyms: [SavedGym]
    @State private var selectedGymID: UUID?
    @State private var lastAppliedGymID: UUID?
    @State private var customScaleName = ""
    @State private var customOrder: [String] = []
    @State private var attachments: [RouteMediaDraft] = []
    @State private var mediaLoading = false
    @State private var initialized = false
    let session: ClimbingSession
    var climb: ClimbEntry?
    @State private var label = ""
    @State private var color = ""
    @State private var scale = GradeScale.vScale
    @State private var appliedScale = GradeScale.vScale
    @State private var otherGymName = ""
    @State private var grade = "V0"
    @State private var styles = Set<String>()
    @State private var prior = PriorExperience.unknown
    @State private var notes = ""
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Where are you climbing?") { GymSelectionRow(selectedID: $selectedGymID) }
                Section("Climb") {
                    TextField("Name or wall (optional)", text: $label).accessibilityIdentifier("climbName")
                    TextField("Hold color (optional)", text: $color)
                    Picker("Grade scale", selection: $scale) {
                        ForEach(GradeScale.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if scale == .custom {
                        TextField("Scale name, e.g. Color circuits", text: $customScaleName).accessibilityIdentifier("climbCustomScale")
                        TextField("Grade, e.g. Blue or Circuit 3", text: $grade).accessibilityIdentifier("customGrade")
                        if !customOrder.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(customOrder, id: \.self) { choice in
                                        Button(choice) { grade = choice }.buttonStyle(.bordered)
                                            .tint(grade == choice ? ClimbTheme.forest : .secondary)
                                    }
                                }
                            }
                        }
                    } else {
                        Picker("Grade", selection: $grade) {
                            Text("Ungraded").tag("Ungraded")
                            ForEach(scale.grades, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
                Section {
                    RouteMediaEditor(attachments: $attachments, isLoading: $mediaLoading)
                } header: { Text("Route photos & videos (optional)") } footer: {
                    Text("Add up to 3 photos or short clips, 25 MB each. Media is saved with this climb on your iPhone.")
                }
                Section {
                    Picker("Before this session", selection: $prior) {
                        ForEach(PriorExperience.allCases) { Text($0.rawValue).tag($0) }
                    }
                } footer: { Text("A first-try send counts as a flash only if you’ve never tried this climb before.") }
                Section {
                    DisclosureGroup("Style (optional)") {
                    ForEach(ClimbStyle.allCases) { style in
                        Toggle(style.rawValue, isOn: Binding(get: { styles.contains(style.rawValue) }, set: { enabled in
                            if enabled { styles.insert(style.rawValue) } else { styles.remove(style.rawValue) }
                        }))
                    }
                }
                }
                Section("Notes") {
                    TextField("Beta, a tricky move, or a small win…", text: $notes, axis: .vertical).lineLimit(2...5)
                }
                if let climb, !climb.attempts.isEmpty {
                    Section("Attempts") {
                        ForEach(climb.orderedAttempts) { attempt in
                            Label("Try \(attempt.sequence) · \(attempt.sent ? "Sent" : "Unsuccessful")", systemImage: attempt.sent ? "checkmark.circle" : "circle")
                        }
                    }
                }
                if climb != nil {
                    Section { Button("Delete climb", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(climb == nil ? "Add climb" : "Edit climb")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: submit).disabled(mediaLoading || !GymGrades.valid(grade: grade, scale: scale, customName: customScaleName)).fontWeight(.semibold).accessibilityIdentifier("saveClimb") }
            }
            .onChange(of: scale) { _, newScale in
                guard newScale != appliedScale else { return }; appliedScale = newScale
                if newScale == .custom {
                    grade = ""
                    if customScaleName.isEmpty { customScaleName = "Gym scale" }
                } else if grade != "Ungraded" && !newScale.grades.contains(grade) { grade = newScale.grades.first ?? "Ungraded" }
            }
            .onChange(of: selectedGymID) { _, id in
                guard initialized, id != lastAppliedGymID else { return }
                applyGym(id)
            }
            .onAppear {
                guard !initialized else { return }
                if let climb {
                    selectedGymID = climb.gymID; lastAppliedGymID = climb.gymID
                    customScaleName = climb.customScaleName; customOrder = climb.customGradeOrder
                    attachments = climb.media.map(\.draft)
                    label = climb.label; color = climb.color; appliedScale = climb.scale; scale = climb.scale; grade = climb.grade
                    otherGymName = climb.gymID == nil ? climb.gymName : ""
                    styles = Set(climb.styles); prior = climb.prior; notes = climb.notes
                } else {
                    scale = GradeScale(rawValue: defaultScale) ?? .vScale
                    grade = scale == .vScale ? "V0" : (scale == .font ? "5" : "")
                    let id = session.gymID
                    otherGymName = id == nil ? session.location : ""
                    selectedGymID = id
                    if id != nil { applyGym(id) }
                }
                initialized = true
            }
            .confirmationDialog("Delete this climb and all its attempts?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete climb", role: .destructive) {
                    if let climb, store.delete(climb) { dismiss() }
                }
            }
        }
        .safeAreaInset(edge: .top) { SaveErrorBanner() }
    }

    private func applyGym(_ id: UUID?) {
        lastAppliedGymID = id
        guard let gym = gyms.first(where: { $0.id == id }) else { otherGymName = ""; return }
        appliedScale = gym.scale
        scale = gym.scale
        customScaleName = gym.customScaleName
        customOrder = gym.customGrades
        grade = scale == .custom ? (gym.customGrades.first ?? "") : (scale == .vScale ? "V0" : "5")
    }

    private func submit() {
        guard !mediaLoading, GymGrades.valid(grade: grade, scale: scale, customName: customScaleName) else { return }
        if store.save({
            let entry = climb ?? ClimbEntry()
            if climb == nil {
                store.context.insert(entry)
                session.climbs.append(entry)
            }
            entry.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.color = color.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.gymID = selectedGymID
            entry.gymName = gyms.first { $0.id == selectedGymID }?.name ?? otherGymName
            entry.customScaleName = scale == .custom ? customScaleName.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            entry.customGradeOrder = scale == .custom ? customOrder : []
            entry.scaleRaw = scale.rawValue; entry.grade = grade.trimmingCharacters(in: .whitespacesAndNewlines)
            let existing = Dictionary(uniqueKeysWithValues: entry.media.map { ($0.id, $0) })
            let retained = Set(attachments.map(\.id))
            for item in entry.media where !retained.contains(item.id) { store.context.delete(item) }
            entry.media = try attachments.map { draft in
                try draft.validate()
                if let item = existing[draft.id] { return item }
                let item = RouteMedia(id: draft.id, kind: draft.kind, filename: draft.filename, contentType: draft.contentType, data: draft.data)
                store.context.insert(item)
                return item
            }
            entry.styles = styles.sorted(); entry.priorRaw = prior.rawValue; entry.notes = notes
        }) { dismiss() }
    }
}
