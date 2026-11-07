import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(AccountSession.self) private var auth
    @Environment(SocialStore.self) private var social
    @Environment(ProfileStore.self) private var profiles
    @AppStorage("healthEnabled") private var healthEnabled = false
    @State private var showLogin = false
    @State private var editProfile = false
    @State private var confirmSignOut = false
    @State private var confirmDeleteAccount = false
    @State private var deleteError: String?
    @State private var confirmWithApple = false
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
        let deleted = await social.deleteAccount(auth)
        deleteError = deleted ? nil : social.errorMessage ?? auth.errorMessage
        if deleted { confirmWithApple = false }
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
                Text("Read-only. Never shared or backed up. Turning this off removes your links.").font(.caption)
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
            }
            Section {
                Button("Export backup", systemImage: "square.and.arrow.up", action: export)
                Button("Restore backup", systemImage: "square.and.arrow.down") { importing = true }
            } header: { Text("Your data").font(.subheadline).foregroundStyle(ClimbTheme.secondaryText).fixedSize(horizontal: false, vertical: true) } footer: {
                Text("Your log stays on this device. Deleting the app can delete it, so export backups.").font(.caption).foregroundStyle(ClimbTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            if let pendingBackup {
                Section(header: Text("Backup ready to restore").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    Text("\(pendingBackup.sessions.count.counted("session")) · \(pendingBackup.climbCount.counted("climb"))")
                    Text("Exported \(pendingBackup.exportedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                    Button("Back up current log first", action: export)
                    Button("Replace current log", role: .destructive) { confirmRestore = true }
                    Button("Cancel restore") { self.pendingBackup = nil }
                }
            }
            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                NavigationLink("Privacy Policy") { PrivacyPolicyView() }.accessibilityIdentifier("privacyPolicy")
                Link("Contact support", destination: URL(string: "mailto:chalkbook.support@gmail.com")!)
                    .frame(minHeight: 44).accessibilityValue("chalkbook.support@gmail.com").accessibilityIdentifier("contactSupport")
            }
            if auth.account != nil {
                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                        .frame(minHeight: 44).accessibilityIdentifier("signOut")
                    Button("Delete account", role: .destructive) { confirmDeleteAccount = true }
                        .frame(minHeight: 44).disabled(social.busy).accessibilityIdentifier("deleteAccount")
                    if confirmWithApple || (social.needsAppleSignIn && deleteError != nil) {
                        if let deleteError, !social.needsAppleSignIn { Text(deleteError).font(.caption).foregroundStyle(ClimbTheme.error) }
                        Text("Apple needs to confirm it’s you before your account can be deleted.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                        AppleConfirmButton { await deleteAccount() }
                    } else if let deleteError { Text(deleteError).font(.caption).foregroundStyle(ClimbTheme.error) }
                }
            }
        }
        .id(textSize)
        .navigationTitle("Settings")
        .sheet(isPresented: $editProfile) { ProfileEditorView(setup: profiles.profile?.setupComplete != true) }
        .sheet(isPresented: $showLogin) { LoginPortalView() }
        .confirmationDialog("Sign out of your account?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { auth.signOut() }
        } message: { Text("Your log stays on this iPhone.") }
        .confirmationDialog("Delete your account?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                // Apple's revoke API needs a fresh code, which only this confirmation can give.
                if auth.account?.provider == .apple && social.configuration != nil { confirmWithApple = true }
                else { Task { await deleteAccount() } }
            }
        } message: { Text("Permanently deletes your account, Friends profile and shared entries. Your journal stays on this iPhone. This can’t be undone.") }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
                      defaultFilename: "Chalkbook-\(SessionDay.key(for: .now))") { result in
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
        } message: { Text("Current sessions will be replaced.") }
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
