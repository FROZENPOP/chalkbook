import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AccountSession.self) private var auth
    @State private var showLogin = false
    @State private var confirmSignOut = false
    @Environment(ClimbingStore.self) private var store
    @Query(sort: \SavedGym.name) private var gyms: [SavedGym]
    @Query private var sessions: [ClimbingSession]
    @AppStorage("defaultGradeScale") private var defaultScale = GradeScale.vScale.rawValue
    @State private var exportDocument = BackupDocument()
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingBackup: ClimbingBackup?
    @State private var confirmRestore = false
    @State private var confirmDelete = false
    @State private var message: String?

    var body: some View {
        Form {
            AccountSection(openPortal: { showLogin = true }, requestSignOut: { confirmSignOut = true })
            Section("My gyms") {
                NavigationLink { GymsView() } label: {
                    Label("Saved gyms (\(gyms.count))", systemImage: "building.2")
                }.accessibilityIdentifier("savedGyms")
                if let gym = gyms.first(where: \.isDefault) {
                    LabeledContent("Default gym", value: gym.name)
                }
            }
            Section("Climbing") {
                Picker("Default grade scale", selection: $defaultScale) {
                    ForEach(GradeScale.allCases.filter { $0 != .custom }) { Text($0.rawValue).tag($0.rawValue) }
                }
                Label("Bouldering", systemImage: "figure.climbing")
            }
            Section {
                Button("Export backup", systemImage: "square.and.arrow.up", action: export)
                Button("Restore backup", systemImage: "square.and.arrow.down") { importing = true }
            } header: { Text("Your data") } footer: {
                Text("Your log stays on this device and works offline. Export backups to Files regularly; deleting the app can delete its local data.")
            }
            if let pendingBackup {
                Section("Backup ready to restore") {
                    Text("\(pendingBackup.sessions.count) sessions · \(pendingBackup.climbCount) climbs")
                    Text("Exported \(pendingBackup.exportedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Back up current log first", action: export)
                    Button("Replace current log", role: .destructive) { confirmRestore = true }
                    Button("Cancel restore") { self.pendingBackup = nil }
                }
            }
            Section {
                LabeledContent("Sessions", value: "\(sessions.count)")
                LabeledContent("Version", value: "0.1.0")
                Text("Made for your next move.").foregroundStyle(.secondary)
            }
            Section { Button("Delete all climbing data", role: .destructive) { confirmDelete = true } }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showLogin) { LoginPortalView() }
        .confirmationDialog("Sign out of your account?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { auth.signOut() }
        } message: { Text("Your account’s log stays on this iPhone. You’ll return to the separate guest log.") }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
                      defaultFilename: "ClimbingLog-\(SessionDay.key(for: .now))") { result in
            if case let .failure(error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                // Check before reading the entire file into memory.
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= ClimbingBackup.maximumBytes else { throw BackupError.invalid("Choose a backup smaller than 150 MB.") }
                pendingBackup = try ClimbingBackup.decode(Data(contentsOf: url))
            } catch { message = "Couldn’t open this backup. \(error.localizedDescription)" }
        }
        .confirmationDialog("Replace your current log with this backup?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Replace current log", role: .destructive) {
                if let backup = pendingBackup, store.restore(backup) {
                    defaultScale = backup.defaultScale.rawValue
                    pendingBackup = nil
                }
            }
        } message: { Text("Current sessions will be replaced. Export a backup first if you want to keep them.") }
        .confirmationDialog("Delete all sessions, gyms, climbs, and route media?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete all climbing data", role: .destructive) {
                if store.deleteAll() { pendingBackup = nil }
            }
        } message: { Text("This cannot be undone. Export a backup first if you want to keep your log.") }
        .alert("Backup", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func export() {
        do {
            let backup = ClimbingBackup(sessions: sessions, defaultScale: GradeScale(rawValue: defaultScale) ?? .vScale, gyms: gyms)
            exportDocument = BackupDocument(data: try backup.encoded())
            exporting = true
        } catch { message = error.localizedDescription }
    }
}
