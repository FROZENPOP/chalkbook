import SwiftUI
import SwiftData

struct ClimbEditorView: View {
    @Environment(\.dynamicTypeSize) private var textSize
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
    var session: ClimbingSession? = nil
    var climb: ClimbEntry?
    var initialProject = false
    @State private var gradeKind = GradeKind.unknown
    @State private var gradeUpper = "V1"
    @State private var isProject = false
    @State private var confirmHistory = false
    @State private var correctPastGrades = false
    @State private var label = ""
    @State private var color = ""
    @State private var scale = GradeScale.vScale
    @State private var appliedScale = GradeScale.vScale
    @State private var otherGymName = ""
    @State private var colorGuide = ""
    @State private var grade = "V0"
    @State private var styles = Set<String>()
    @State private var prior = PriorExperience.unknown
    @State private var notes = ""
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Where are you climbing?").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) { GymSelectionRow(selectedID: $selectedGymID) }
                Section(header: Text("Climb").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    TextField("Name or wall (optional)", text: $label, axis: .vertical).lineLimit(1...3).accessibilityIdentifier("climbName").frame(minHeight: 44)
                    TextField("Hold color (optional)", text: $color, axis: .vertical).lineLimit(1...3).frame(minHeight: 44)
                    if !colorGuide.isEmpty { Text(colorGuide).font(.caption).foregroundStyle(ClimbTheme.secondaryText) }
                    Toggle("Save as a project", isOn: $isProject)
                    Picker("Describe difficulty", selection: $gradeKind) { ForEach(GradeKind.allCases) { Text($0.title).tag($0) } }
                    if gradeKind != .unknown && gradeKind != .color {
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
                                            Button { grade = choice } label: { Text(choice).frame(minHeight: 44) }.buttonStyle(.bordered)
                                                .tint(grade == choice ? ClimbTheme.accent : .secondary)
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
                }
                if gradeKind == .range || gradeKind == .colorRange {
                    Section(header: Text("Upper end of range").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        if scale == .custom { TextField("Upper grade", text: $gradeUpper) }
                        else { Picker("Upper grade", selection: $gradeUpper) { ForEach(scale.grades, id: \.self) { Text($0).tag($0) } } }
                    }
                }
                Section {
                    RouteMediaEditor(attachments: $attachments, isLoading: $mediaLoading)
                } header: { Text("Route photos & videos (optional)").font(.subheadline).foregroundStyle(ClimbTheme.secondaryText).fixedSize(horizontal: false, vertical: true) } footer: {
                    Text("Add up to 3 photos or short clips, 25 MB each. Media is saved with this climb on your iPhone.").font(.caption).foregroundStyle(ClimbTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    Picker("Before the first journal attempt", selection: $prior) {
                        ForEach(PriorExperience.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if climb?.historyIncomplete == true {
                        Toggle("I reviewed the missing history; this journal is complete", isOn: $confirmHistory)
                        Text("Removed records leave history unknown until you explicitly confirm completeness.").font(.caption)
                    }
                } footer: { Text("A first-try send counts as a flash only if you’ve never tried this climb before.").font(.caption).foregroundStyle(ClimbTheme.secondaryText).fixedSize(horizontal: false, vertical: true) }
                Section {
                    DisclosureGroup("Style (optional)") {
                    ForEach(ClimbStyle.allCases) { style in
                        Toggle(style.rawValue, isOn: Binding(get: { styles.contains(style.rawValue) }, set: { enabled in
                            if enabled { styles.insert(style.rawValue) } else { styles.remove(style.rawValue) }
                        }))
                    }
                }
                }
                Section(header: Text("Notes").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    TextField("Beta, a tricky move, or a small win…", text: $notes, axis: .vertical).lineLimit(2...5)
                }
                if let climb, !climb.attempts.isEmpty {
                    Section {
                        Toggle("Correct difficulty on existing attempts too", isOn: $correctPastGrades)
                        Text("Leave off to retain the difficulty recorded at the time. Turning this on explicitly corrects all this climb’s saved attempt descriptors.").font(.caption)
                    }
                }
                if climb != nil {
                    Section { Button("Delete climb", role: .destructive) { confirmDelete = true } }
                }
            }
            .id(textSize)
            .navigationTitle(climb == nil ? "Add climb" : "Edit climb")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() }.accessibleToolbarAction() }
                ToolbarItem(placement: .confirmationAction) { Button("Save", systemImage: "checkmark", action: submit).disabled(mediaLoading || !validDescriptor).fontWeight(.semibold).accessibleToolbarAction().accessibilityIdentifier("saveClimb") }
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
                    gradeKind = GradeKind(rawValue: climb.gradeKindRaw) ?? .exact; gradeUpper = climb.gradeUpper
                    isProject = !climb.projectRaw.isEmpty
                    label = climb.label; color = climb.color; appliedScale = climb.scale; scale = climb.scale; grade = climb.grade
                    colorGuide = climb.colorGuide
                    otherGymName = climb.gymID == nil ? climb.gymName : ""
                    styles = Set(climb.styles); prior = climb.prior; notes = climb.notes
                } else {
                    isProject = initialProject
                    scale = GradeScale(rawValue: defaultScale) ?? .vScale
                    grade = scale == .vScale ? "V0" : (scale == .font ? "5" : "")
                    let id = session?.gymID ?? gyms.first(where: \.isDefault)?.id
                    otherGymName = id == nil ? session?.location ?? "" : ""
                    selectedGymID = id
                    if id != nil { applyGym(id) }
                }
                initialized = true
            }
            .confirmationDialog("Delete this climb everywhere?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete climb", role: .destructive) {
                    if let climb, store.delete(climb) { dismiss() }
                }
            } message: {
                Text("This removes \(climb?.attempts.count ?? 0) attempts and \(climb?.media.count ?? 0) attachments across every session, plus its notebook. Original Photos and Files items stay intact.")
            }
        }
        .safeAreaInset(edge: .top) { SaveErrorBanner() }
    }

    private var validDescriptor: Bool {
        if gradeKind == .unknown { return true }
        if gradeKind == .color { return !color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard GymGrades.valid(grade: grade, scale: scale, customName: customScaleName) else { return false }
        if gradeKind == .range || gradeKind == .colorRange {
            guard !gradeUpper.isEmpty else { return false }
            if scale != .custom {
                guard let lower = scale.rank(of: grade), let upper = scale.rank(of: gradeUpper), upper >= lower else { return false }
            }
            if gradeKind == .colorRange && color.isEmpty { return false }
        }
        return true
    }

    private func applyGym(_ id: UUID?) {
        lastAppliedGymID = id
        guard let gym = gyms.first(where: { $0.id == id }) else { otherGymName = ""; return }
        gradeKind = .exact
        appliedScale = gym.scale
        scale = gym.scale
        customScaleName = gym.customScaleName
        customOrder = gym.customGrades
        colorGuide = gym.colorGuide
        grade = scale == .custom ? (gym.customGrades.first ?? "") : (scale == .vScale ? "V0" : "5")
    }

    private func submit() {
        guard !mediaLoading, validDescriptor else { return }
        if store.save({
            let entry = climb ?? ClimbEntry()
            if climb == nil {
                store.context.insert(entry)
                session?.climbs.append(entry)
                session?.selectedClimbID = entry.id
            }
            entry.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.color = color.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.gymID = selectedGymID
            entry.gymName = gyms.first { $0.id == selectedGymID }?.name ?? otherGymName
            entry.colorGuide = colorGuide
            entry.customScaleName = scale == .custom ? customScaleName.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            entry.customGradeOrder = scale == .custom ? customOrder : []
            entry.scaleRaw = scale.rawValue; entry.grade = grade.trimmingCharacters(in: .whitespacesAndNewlines)
            let existing = Dictionary(uniqueKeysWithValues: entry.media.map { ($0.id, $0) })
            let retained = Set(attachments.map(\.id))
            for item in entry.media where !retained.contains(item.id) { store.context.delete(item) }
            entry.media = try attachments.map { draft in
                try draft.validate()
                if let item = existing[draft.id] {
                    item.annotationJSON = draft.annotationJSON
                    item.updatedAt = .now
                    return item
                }
                let item = RouteMedia(id: draft.id, kind: draft.kind, filename: draft.filename, contentType: draft.contentType, data: draft.data)
                item.annotationJSON = draft.annotationJSON
                store.context.insert(item)
                return item
            }
            entry.gradeKindRaw = gradeKind.rawValue; entry.gradeUpper = gradeUpper
            entry.projectRaw = isProject ? (entry.projectRaw.isEmpty ? "active" : entry.projectRaw) : ""
            entry.updatedAt = .now
            if confirmHistory { entry.historyIncomplete = false }
            entry.styles = styles.sorted(); entry.priorRaw = prior.rawValue; entry.notes = notes
            if correctPastGrades { for attempt in entry.attempts { attempt.gradeSnapshot = entry.descriptor.encoded; attempt.updatedAt = .now } }
            defaultScale = scale.rawValue
        }) { dismiss() }
    }
}
