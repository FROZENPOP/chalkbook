import SwiftUI
import SwiftData
import ImageIO

struct ProjectsView: View {
    @Query(sort: \ClimbEntry.createdAt, order: .reverse) private var climbs: [ClimbEntry]
    @State private var filter = "active"
    @State private var adding = false
    private var listState: ProjectListState { ProjectListState(climbs: climbs, filter: filter) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Project status", selection: $filter) { Text("Active").tag("active"); Text("Sent").tag("sent"); Text("Archived").tag("archived"); Text("All").tag("all") }.pickerStyle(.menu).accessibilityIdentifier("projectStatusFilter")
                if let action = listState.emptyAction {
                    ContentUnavailableView {
                        Label(action == .addProject ? "Save your first project" : "No projects in this filter", systemImage: "figure.climbing")
                    } description: {
                        Text(action == .addProject
                             ? "A project is a climb you want to keep working on. Add one to keep its photos, notes, and attempts together across sessions."
                             : "Your saved projects are still here. View all projects or choose another status above.")
                    } actions: {
                        Button {
                            if action == .addProject { adding = true }
                            else { filter = "all" }
                        } label: {
                            Label(action == .addProject ? "Add your first project" : "View all projects", systemImage: action == .addProject ? "plus" : "line.3.horizontal.decrease")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("projectsEmptyAction")
                    }.padding(.vertical, 24)
                }
                ForEach(listState.projects) { climb in
                    NavigationLink { ProjectDetailView(climb: climb) } label: {
                        Surface {
                            VStack(alignment: .leading, spacing: 12) {
                                if let photo = climb.media.first(where: { $0.kind == .photo }) { RouteThumbnail(data: photo.data,annotationJSON:photo.annotationJSON) }
                                Text(climb.title).font(.title3.bold())
                                Text("\(climb.descriptor.label) · \(climb.gymName)").font(.subheadline)
                                Text("\(climb.attempts.count) recorded attempts · \(climb.projectStatus.capitalized)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(20)
        }
        .background(ClimbTheme.background).navigationTitle("Projects")
        .toolbar { Button("Add project", systemImage: "plus") { adding = true } }
        .sheet(isPresented: $adding) { ClimbEditorView(initialProject: true) }
    }
}

struct RouteThumbnail: View {
    let data: Data
    var annotationJSON: String = ""
    @State private var image: UIImage?
    var body: some View {
        Group {
            if (try? RouteAnnotations.document(annotationJSON).highlight) != nil {
                HighlightedRoutePhoto(data: data, annotationJSON: annotationJSON)
            } else if let image {
                if let strokes = try? RouteAnnotations.decode(annotationJSON), !strokes.isEmpty { RouteMarkupImage(image:image,strokes:strokes).clipShape(RoundedRectangle(cornerRadius:12)) }
                else { Image(uiImage: image).resizable().scaledToFill().frame(height: 160).clipped().clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Route photo") }
            }
            else { Image(systemName: "photo").frame(height: 80).accessibilityLabel("Route photo preview unavailable") }
        }.task(id: data.count) {
            image = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 640, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return UIImage?.none }
                return UIImage(cgImage: cg)
            }.value
        }
    }
}

struct ProjectDetailView: View {
    @Environment(ClimbingStore.self) private var store
    @Query private var sessions: [ClimbingSession]
    let climb: ClimbEntry
    @State private var editing = false
    @State private var notebookEditor: NotebookDestination?
    @State private var attempt: ClimbAttempt?
    @State private var preview: RouteMediaDraft?
    @State private var trying: ClimbingSession?
    @State private var annotating: RouteMedia?
    private var historySessions: Int { Set(climb.attempts.compactMap(\.effectiveSessionID)).count }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let photo = climb.media.first(where: { $0.kind == .photo }) { RouteThumbnail(data: photo.data,annotationJSON:photo.annotationJSON) }
                Text(climb.descriptor.label).font(.title.bold())
                Text(climb.gymName).foregroundStyle(.secondary)
                Text(climb.isSent ? "Completion observed in recorded attempts" : (climb.prior == .sent ? "Historical completion declared before the journal" : "No recorded completion"))
                if !climb.notes.isEmpty { Surface { Text(climb.notes) } }
                ForEach(climb.media) { media in
                    Button { preview = media.draft } label: { MediaLabel(kind: media.kind, filename: media.filename) }
                    if media.kind == .photo { Button("Annotate \(media.filename)",systemImage:"pencil.tip.crop.circle") { annotating=media }.frame(minHeight:44).accessibilityIdentifier("annotateRoutePhoto") }
                }
                ProjectNotebookSummary(climb:climb)
                Button("Try this session", systemImage: "figure.climbing") {
                    let session = sessions.first { !$0.isComplete } ?? store.start(date: .now, location: climb.gymName, notes: "")
                    if let session, store.select(climb, in: session) { trying = session }
                }.buttonStyle(.borderedProminent).frame(minHeight: 44).accessibilityIdentifier("tryProject")
                Menu("Project status") {
                    Button("Active") { _ = store.setProject(climb, status: "active") }
                    Button("Archive") { _ = store.setProject(climb, status: "archived") }
                    Button("Remove project status") { _ = store.setProject(climb, status: "") }
                }
                Text("Removing status keeps the climb, notebook, and history. A recorded or declared completion appears in Sent; repeating it keeps this same climb.").font(.caption).foregroundStyle(.secondary)
                HStack { Text("Private notebook").font(.title2.bold()); Spacer(); Button("Add note") { notebookEditor=NotebookDestination(note:nil) }.frame(minHeight: 44) }
                ForEach(climb.notebook.sorted { $0.createdAt > $1.createdAt }) { note in
                    Button { notebookEditor=NotebookDestination(note:note) } label: {
                        Surface { VStack(alignment: .leading) { if climb.pinnedNoteID == note.id { Label("Pinned next move",systemImage:"pin.fill").font(.caption.bold()) };Text(note.text); Text(note.updatedAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary) } }
                    }.buttonStyle(.plain).accessibilityIdentifier("editNotebookNote")
                }
                if let firstSend = climb.orderedAttempts.firstIndex(where: \.sent) {
                    let before = Array(climb.orderedAttempts.prefix(firstSend + 1))
                    Text("Before first recorded send: \(before.count) recorded attempts across \(Set(before.compactMap(\.effectiveSessionID)).count) sessions. Earlier unrecorded activity is unknown.").font(.subheadline)
                }
                Text("Complete recorded history").font(.title2.bold())
                Text("\(climb.attempts.count) attempts across \(historySessions) sessions").font(.subheadline)
                Text("Flash: \(climb.flash.state == .confirmed ? "confirmed" : climb.flash.state == .notFlash ? "not flash" : "unknown"). \(climb.flash.reason)").font(.caption)
                ForEach(climb.orderedAttempts) { item in
                    Button { attempt = item } label: {
                        Label("\(SessionDay.label(for: item.sessionDay)) · Try \(item.sequence) · \(item.sent ? "Sent" : "Failed")", systemImage: item.sent ? "checkmark.circle" : "xmark.circle").frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }
            }.padding(20)
        }.background(ClimbTheme.background).navigationTitle(climb.title)
        .toolbar { Button("Edit climb", systemImage: "pencil") { editing = true } }
        .sheet(isPresented: $editing) { ClimbEditorView(climb: climb) }
        .sheet(item:$notebookEditor) { NotebookEditor(climb:climb,note:$0.note) }
        .sheet(item: $attempt) { AttemptEditorView(attempt: $0) }
        .sheet(item: $preview) { item in
            RouteMediaPreview(item: item) { json in
                guard let media = climb.media.first(where: { $0.id == item.id }) else { return false }
                return store.save { media.annotationJSON = json; media.updatedAt = .now }
            }
        }
        .sheet(item:$annotating) { RouteAnnotationView(media:$0) }
        .sheet(item: $trying) { session in NavigationStack { SessionDetailView(session: session).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { trying = nil } } } } }
    }
}

private struct NotebookDestination:Identifiable {
    let id:UUID
    let note:ClimbNote?
    init(note:ClimbNote?) { self.note=note;id=note?.id ?? UUID() }
}

struct NotebookEditor: View {
    @Environment(ClimbingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let climb: ClimbEntry
    var note: ClimbNote?
    @State private var text = ""
    @State private var pinned = false
    @State private var initialized=false
    var body: some View {
        NavigationStack {
            Form {
                Toggle("Pin as next move",isOn:$pinned).accessibilityIdentifier("pinNotebookNote")
                TextField("What will you try next?", text: $text, axis: .vertical).lineLimit(5...15).accessibilityIdentifier("notebookText")
                if let note { Button("Delete note", role: .destructive) {
                    if store.save({ if climb.pinnedNoteID == note.id { climb.pinnedNoteID=nil };climb.notebook.removeAll { $0.id == note.id }; store.context.delete(note) }) { dismiss() }
                } }
            }.navigationTitle(note == nil ? "New private note" : "Edit private note")
            .onAppear { if !initialized { text = note?.text ?? "";pinned = note != nil && climb.pinnedNoteID == note?.id;initialized=true } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if store.save({
                        let entry = note ?? ClimbNote(text: text)
                        if note == nil { store.context.insert(entry); climb.notebook.append(entry) }
                        entry.text = text; entry.updatedAt = .now
                        if pinned { climb.pinnedNoteID=entry.id } else if climb.pinnedNoteID == entry.id { climb.pinnedNoteID=nil }
                        climb.updatedAt = .now
                    }) { dismiss() }
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }.safeAreaInset(edge: .top) { SaveErrorBanner() }
    }
}

struct ExistingClimbPicker: View {
    @Environment(ClimbingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ClimbEntry.updatedAt, order: .reverse) private var climbs: [ClimbEntry]
    let session: ClimbingSession
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List(climbs.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.gymName.localizedCaseInsensitiveContains(search) }) { climb in
                Button { if store.select(climb, in: session) { dismiss() } } label: {
                    VStack(alignment: .leading) { Text(climb.title).font(.headline); Text("\(climb.descriptor.label) · \(climb.gymName)").font(.caption) }
                }.frame(minHeight: 44)
            }.searchable(text: $search).navigationTitle("Choose existing climb")
            .overlay { if climbs.isEmpty { ContentUnavailableView("No saved climbs", systemImage: "figure.climbing", description: Text("Create a climb first. Matching grades and colors never merge climbs.")) } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Distinguishes a new notebook from an empty filter so the suggested action never hides saved work.
struct ProjectListState {
    enum EmptyAction { case addProject, showAll }
    let projects: [ClimbEntry]
    private let hasSavedProjects: Bool

    init(climbs: [ClimbEntry], filter: String) {
        let saved = climbs.filter { !$0.projectRaw.isEmpty }
        hasSavedProjects = !saved.isEmpty
        projects = saved.filter { filter == "all" || $0.projectStatus == filter }
    }
    var emptyAction: EmptyAction? {
        guard projects.isEmpty else { return nil }
        return hasSavedProjects ? .showAll : .addProject
    }
}
