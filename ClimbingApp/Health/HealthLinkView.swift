import SwiftUI
import SwiftData

struct HealthLinkView: View {
    @Environment(ClimbingStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Query private var links: [HealthWorkoutLink]
    @AppStorage("healthEnabled") private var enabled = false
    let session: ClimbingSession
    var reader: any HealthWorkoutReading = AppleHealthWorkouts()
    @State private var candidates: [HealthWorkout] = []
    @State private var linkedWorkout: HealthWorkout?
    @State private var selected: HealthWorkout?
    @State private var loaded = false
    @State private var loading = false
    @State private var message: String?
    private var link: HealthWorkoutLink? { links.first { $0.sessionID == session.id } }
    var body: some View {
        NavigationStack {
            List {
                if let link {
                    Section(header: Text("Linked workout").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        if let linkedWorkout { workoutRow(linkedWorkout) }
                        else { Text("Workout not available.") }
                        Text("Source: \(link.sourceName)").font(.caption)
                        Button("Unlink", role: .destructive) { if store.save({ store.context.delete(link) }) { linkedWorkout = nil } }
                    }
                }
                if !enabled {
                    Button("Allow Health access and find workouts") { enabled = true; Task { await load(request: true) } }.disabled(!reader.available)
                } else {
                    Button("Refresh nearby workouts") { Task { await load(request: true) } }.disabled(loading || !reader.available)
                }
                if loading { SwiftUI.ProgressView("Looking for workouts…") }
                if let message { Text(message).foregroundStyle(ClimbTheme.secondaryText) }
                if loaded && candidates.isEmpty { Text("No workouts found.") }
                Section(header: Text("Nearby workouts").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    ForEach(candidates) { workout in
                        Button { selected = workout } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                workoutRow(workout)
                                Text("Overlap with session: \(Int(HealthLinkRules.overlap(workout,start:session.startedAt,end:session.endedAt ?? .now)/60)) minutes").font(.caption)
                                if HealthLinkRules.hasSimilarCandidate(workout,among:candidates) { Label("Similar workout found.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(ClimbTheme.accent) }
                                if links.contains(where: { $0.workoutID == workout.id && $0.sessionID != session.id }) { Text("Already linked to another session").font(.caption) }
                            }
                        }.disabled(!HealthLinkRules.canLink(workoutID:workout.id,to:session.id,existing:links.map { ($0.sessionID,$0.workoutID) }))
                    }
                }
            }.navigationTitle("Apple Health workout")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: enabled) { _, value in if !value { linkedWorkout = nil; candidates = []; loaded = false } }
            .onChange(of: scenePhase) { _, value in if value == .active && enabled { Task { await load(request: false) } } }
            .task { if enabled { await load(request:false) } }
            .confirmationDialog("Link this specific workout?", isPresented: Binding(get:{ selected != nil },set:{ if !$0 { selected = nil } }), titleVisibility:.visible) {
                Button(link == nil ? "Link workout" : "Replace linked workout") { if let selected { attach(selected) }; selected = nil }
            } message: { Text("\(selected?.sourceName ?? "") · \(selected?.start.formatted() ?? ""). Only this workout will be linked.") }
        }.safeAreaInset(edge:.top) { SaveErrorBanner() }
    }
    private func workoutRow(_ workout: HealthWorkout) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(workout.sourceName).font(.headline)
            Text(workout.start,format:.dateTime.month().day().hour().minute())
            Text("Duration: \(Int(workout.duration/60)) min")
            Text(workout.energyKilocalories.map { "Active energy: \(Int($0)) kcal" } ?? "Active energy: unavailable")
            Text(workout.meanHeartRate.map { "Average heart rate: \(Int($0)) bpm" } ?? "Heart rate: unavailable")
        }.foregroundStyle(.primary).accessibilityElement(children:.combine)
    }
    private func load(request: Bool) async {
        guard !loading else { return }; loading = true; message = nil
        defer { loading = false; loaded = true }
        do {
            if request { try await reader.requestReadAccess() }
            candidates = HealthLinkRules.deduplicated(try await reader.nearby(start:session.startedAt,end:session.endedAt ?? .now))
            if let link { linkedWorkout = try await reader.workout(id:link.workoutID) }
        } catch { candidates = []; linkedWorkout = nil; message = "Couldn’t read Apple Health." }
    }
    private func attach(_ workout: HealthWorkout) {
        guard HealthLinkRules.canLink(workoutID:workout.id,to:session.id,existing:links.map { ($0.sessionID,$0.workoutID) }) else { return }
        if store.save({
            if let link { link.workoutID = workout.id; link.sourceName = workout.sourceName; link.sourceBundle = workout.sourceBundle; link.linkedAt = .now }
            else { store.context.insert(HealthWorkoutLink(sessionID:session.id,workoutID:workout.id,sourceName:workout.sourceName,sourceBundle:workout.sourceBundle)) }
        }) { linkedWorkout = workout; enabled = true }
    }
}
