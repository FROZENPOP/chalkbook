import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(AccountSession.self) private var auth
    @Environment(SocialStore.self) private var social
    @AppStorage("healthEnabled") private var healthEnabled = false
    @State private var showLogin = false
    @State private var editProfile = false
    @State private var confirmSignOut = false
    @State private var confirmDeleteAccount = false
    @State private var deleteError: String?
    @Environment(ClimbingStore.self) private var store
    @Query(sort: \SavedGym.name) private var gyms: [SavedGym]
    @Query private var allClimbs: [ClimbEntry]
    @Query private var sessions: [ClimbingSession]
    @AppStorage("defaultGradeScale") private var defaultScale = GradeScale.vScale.rawValue
    // Device-wide, so it lives outside the per-account defaults.
    @AppStorage("appearance", store: .standard) private var appearance = "dark"
    @State private var exportDocument = BackupDocument()
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingBackup: ClimbingBackup?
    @State private var confirmRestore = false
    @State private var message: String?

    private func deleteAccount() async {
        deleteError = await social.deleteAccount(auth) ? nil : social.errorMessage ?? auth.errorMessage
    }

    var body: some View {
        Form {
            AccountSection(openPortal: { showLogin = true }, editProfile: { editProfile = true })
            Section(header: Text("My gyms").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                NavigationLink { GymsView() } label: {
                    Label("Saved gyms (\(gyms.count))", systemImage: "building.2")
                }.accessibilityIdentifier("savedGyms")
                if let gym = gyms.first(where: \.isDefault) {
                    LabeledContent("Default gym", value: gym.name)
                }
            }
            Section(header: Text("Apple Health").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                Toggle("Health workout linking", isOn: Binding(get: { healthEnabled }, set: { value in
                    if value { healthEnabled = true }
                    else if store.save({
                        for link in try store.context.fetch(FetchDescriptor<HealthWorkoutLink>()) { store.context.delete(link) }
                    }) { healthEnabled = false }
                }))
                Text("Read access is requested only from a session’s Link Apple Health workout action. Turning this off removes local links. Measurements are never included in journal backups, and no workouts are exported.").font(.caption)
            }
            Section(header: Text("Appearance").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                Picker("Theme", selection: $appearance) {
                    Text("Dark").tag("dark"); Text("Light").tag("light"); Text("Match iPhone").tag("system")
                }.accessibilityIdentifier("appearancePicker")
            }
            Section(header: Text("Climbing").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                Picker("Default grade scale", selection: $defaultScale) {
                    ForEach(GradeScale.allCases.filter { $0 != .custom }) { Text($0.rawValue).tag($0.rawValue) }
                }
                Label("Bouldering", systemImage: "figure.climbing")
            }
            Section {
                Button("Export backup", systemImage: "square.and.arrow.up", action: export)
                Button("Restore backup", systemImage: "square.and.arrow.down") { importing = true }
            } header: { Text("Your data").font(.subheadline).foregroundStyle(ClimbTheme.secondaryText).fixedSize(horizontal: false, vertical: true) } footer: {
                Text("Your log stays on this device and works offline. Export backups to Files regularly; deleting the app can delete its local data.").font(.caption).foregroundStyle(ClimbTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            if let pendingBackup {
                Section(header: Text("Backup ready to restore").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    Text("\(pendingBackup.sessions.count) sessions · \(pendingBackup.climbCount) climbs")
                    Text("Exported \(pendingBackup.exportedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                    Button("Back up current log first", action: export)
                    Button("Replace current log", role: .destructive) { confirmRestore = true }
                    Button("Cancel restore") { self.pendingBackup = nil }
                }
            }
            Section {
                LabeledContent("Sessions", value: "\(sessions.count)")
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                Text("Made for your next move.").foregroundStyle(ClimbTheme.secondaryText)
            }
            if auth.account != nil {
                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                        .frame(minHeight: 44).accessibilityIdentifier("signOut")
                    Button("Delete account", role: .destructive) { confirmDeleteAccount = true }
                        .frame(minHeight: 44).disabled(social.busy).accessibilityIdentifier("deleteAccount")
                    if social.needsAppleSignIn && deleteError != nil {
                        Text("Apple needs to confirm it’s you before your account can be deleted.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                        AppleConfirmButton { await deleteAccount() }
                    } else if let deleteError { Text(deleteError).font(.caption).foregroundStyle(ClimbTheme.error) }
                }
            }
        }
        .id(textSize)
        .navigationTitle("Settings")
        .sheet(isPresented: $editProfile) { ProfileEditorView() }
        .sheet(isPresented: $showLogin) { LoginPortalView() }
        .confirmationDialog("Sign out of your account?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { auth.signOut() }
        } message: { Text("Your account’s log stays on this iPhone. You’ll return to the separate guest log.") }
        .confirmationDialog("Delete your account?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: { Text("This permanently deletes your Climb Log account, Friends profile, connections, shared entries and reactions from our servers, then signs you out. Your private journal stays on this iPhone until you delete the app. This can’t be undone.") }
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
        .alert("Backup", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func export() {
        do {
            let backup = ClimbingBackup(sessions: sessions, defaultScale: GradeScale(rawValue: defaultScale) ?? .vScale, gyms: gyms, climbs: allClimbs)
            exportDocument = BackupDocument(data: try backup.encoded())
            exporting = true
        } catch { message = error.localizedDescription }
    }
}
