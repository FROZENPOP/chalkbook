import SwiftUI
import SwiftData

struct GymsView: View {
    @Environment(ClimbingStore.self) private var store
    @Query(sort: \SavedGym.name) private var gyms: [SavedGym]
    @State private var sheet: GymSheet?

    var body: some View {
        List {
            Section {
                ForEach(gyms) { gym in
                    Button { sheet = .edit(gym) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(gym.name).foregroundStyle(.primary).font(.headline)
                                if !gym.address.isEmpty { Text(gym.address).font(.caption).foregroundStyle(ClimbTheme.secondaryText) }
                                Text(gym.scaleLabel).foregroundStyle(ClimbTheme.secondaryText).font(.subheadline)
                            }
                            Spacer()
                            if gym.isDefault { Label("Default", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(ClimbTheme.forest) }
                        }.padding(.vertical, 5)
                    }
                    .swipeActions(edge: .leading) {
                        Button("Make default") { store.makeDefault(gym) }.tint(ClimbTheme.forest)
                    }
                }
                Button { sheet = .new } label: { HStack { Image(systemName: "plus").accessibilityHidden(true); Text("Add gym").fixedSize(horizontal: false, vertical: true) } }
                    .frame(minHeight: 44).accessibilityIdentifier("addSavedGym")
            } footer: { Text("Your default gym is preselected for new sessions. Each climb starts with its session’s gym and grading scale.").font(.caption).foregroundStyle(ClimbTheme.secondaryText).fixedSize(horizontal: false, vertical: true) }
        }
        .navigationTitle("My gyms")
        .sheet(item: $sheet) { destination in GymEditorView(gym: destination.gym) }
    }
}

enum GymSheet: Identifiable {
    case new, edit(SavedGym)
    var id: String { switch self { case .new: "new"; case let .edit(gym): gym.id.uuidString } }
    var gym: SavedGym? { if case let .edit(gym) = self { gym } else { nil } }
}

struct GymSelectionRow: View {
    @Query(sort: \SavedGym.name) private var gyms: [SavedGym]
    @Binding var selectedID: UUID?
    @State private var sheet: GymSheet?
    var selectedName: String { gyms.first { $0.id == selectedID }?.menuLabel ?? "No gym selected" }

    var body: some View {
        Menu {
            ForEach(gyms) { gym in
                Button {
                    selectedID = gym.id
                } label: {
                    if selectedID == gym.id { Label(gym.menuLabel, systemImage: "checkmark") } else { Text(gym.menuLabel) }
                }
            }
            if !gyms.isEmpty { Divider() }
            Button("Add a new gym…", systemImage: "plus") { sheet = .new }
            Button("No gym / other location") { selectedID = nil }
        } label: {
            HStack {
                Label("Gym", systemImage: "building.2")
                Spacer()
                Text(selectedName).foregroundStyle(ClimbTheme.secondaryText).multilineTextAlignment(.trailing)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
            }
            .foregroundStyle(.primary).frame(minHeight: 44)
        }
        .accessibilityIdentifier("gymPicker")
        .sheet(item: $sheet) { _ in GymEditorView { selectedID = $0.id } }
    }
}

struct GymEditorView: View {
    @Environment(ClimbingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var gym: SavedGym?
    var onSaved: ((SavedGym) -> Void)?
    @State private var name = ""
    @State private var address = ""
    @State private var scale = GradeScale.vScale
    @State private var customName = ""
    @State private var gradesText = ""
    @State private var colorGuide = ""
    @State private var isDefault = true
    @State private var confirmDelete = false
    @State private var initialized = false

    init(gym: SavedGym? = nil, onSaved: ((SavedGym) -> Void)? = nil) {
        self.gym = gym
        self.onSaved = onSaved
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (scale != .custom || !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Gym").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    GymPlaceNameField(name: $name, address: $address)
                    TextField("Address or city (optional)", text: $address).textContentType(.fullStreetAddress).accessibilityIdentifier("gymAddress")
                    Toggle("Use as my default gym", isOn: $isDefault)
                }
                Section {
                    Picker("Grading scale", selection: $scale) {
                        ForEach(GradeScale.allCases) { Text($0.rawValue).tag($0) }
                    }.accessibilityIdentifier("gymScale")
                    if scale == .custom {
                        TextField("Scale name, e.g. Color circuits", text: $customName).accessibilityIdentifier("customScaleName")
                        TextField("Green, Blue, Red, Black", text: $gradesText, axis: .vertical)
                            .lineLimit(2...5).accessibilityIdentifier("customGradeOrder")
                    }
                } header: { Text("How does this gym grade climbs?").font(.subheadline).foregroundStyle(ClimbTheme.secondaryText).fixedSize(horizontal: false, vertical: true) } footer: {
                    Text(scale == .custom ? "Optionally list grades from easiest to hardest, separated by commas. You can also type any grade when logging a climb." : "We’ll preselect this scale whenever you log a climb at this gym.")
                }
                Section(header: Text("Local color guide (optional)").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    TextField("e.g. Blue: V2–V4, Red: V4–V6", text: $colorGuide, axis: .vertical).lineLimit(2...5)
                    Text("Your descriptions are notes, not grade conversions. They are copied into new climbs so later changes do not rewrite history.").font(.caption)
                }
                if gym != nil {
                    Section { Button("Remove saved gym", role: .destructive) { confirmDelete = true } }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(gym == nil ? "Add gym" : "Edit gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let saved = store.saveGym(existing: gym, name: name, scale: scale, customName: customName,
                                                     grades: GymGrades.orderedLabels(from: gradesText), isDefault: isDefault, colorGuide: colorGuide, address: address) {
                            onSaved?(saved)
                            dismiss()
                        }
                    }.disabled(!canSave).fontWeight(.semibold).accessibilityIdentifier("saveGym")
                }
            }
            .onAppear {
                guard !initialized else { return }
                initialized = true
                if let gym {
                    address = gym.address
                    colorGuide = gym.colorGuide
                    name = gym.name; scale = gym.scale; customName = gym.customScaleName
                    gradesText = gym.customGrades.joined(separator: ", "); isDefault = gym.isDefault
                } else { isDefault = (try? store.defaultGym()) == nil }
            }
            .confirmationDialog("Remove this saved gym?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove gym", role: .destructive) {
                    if let gym, store.deleteGym(gym) { dismiss() }
                }
            } message: { Text("Your existing sessions and climbs keep their gym names and grades.") }
        }
        .safeAreaInset(edge: .top) { SaveErrorBanner() }
    }
}
