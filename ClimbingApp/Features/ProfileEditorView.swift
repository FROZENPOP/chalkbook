import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ProfileAvatar: View {
    let photo: Data?
    var size: CGFloat = 64
    var body: some View {
        Group {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(ClimbTheme.forest.opacity(0.75))
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .accessibilityLabel(photo == nil ? "Default profile picture" : "Profile picture")
    }
}

struct ProfileEditorView: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(AccountSession.self) private var auth
    @Environment(\.dismiss) private var dismiss
    var setup = false
    @State private var name = ""
    @State private var bio = ""
    @State private var photo: Data?
    @State private var selection: PhotosPickerItem?
    @State private var importing = false
    @State private var files = false
    @State private var initialized = false
    @State private var importError: String?

    private var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.trimmingCharacters(in: .whitespacesAndNewlines).count <= 60 && bio.count <= 500 }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { Spacer(); ProfileAvatar(photo: photo, size: 104); Spacer() }.padding(.vertical, 12)
                    PhotosPicker(selection: $selection, matching: .images) {
                        Label(photo == nil ? "Add profile photo" : "Change profile photo", systemImage: "photo").frame(minHeight: 44)
                    }.disabled(importing).accessibilityIdentifier("chooseProfilePhoto")
                    Button("Choose photo from Files", systemImage: "folder") { files = true }.frame(minHeight: 44).disabled(importing).accessibilityIdentifier("profilePhotoFromFiles")
                    if photo != nil {
                        Button("Remove profile photo", role: .destructive) { photo = nil }.frame(minHeight: 44).accessibilityIdentifier("removeProfilePhoto")
                    }
                    if importing { SwiftUI.ProgressView("Preparing your photo…") }
                    if let importError { Text(importError).font(.subheadline).foregroundStyle(ClimbTheme.error) }
                } footer: { Text("A photo is optional. You can change or remove it later.").font(.caption).foregroundStyle(ClimbTheme.secondaryText).fixedSize(horizontal: false, vertical: true) }
                Section(header: Text("About you").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    TextField("Display name", text: $name).textContentType(.name).textInputAutocapitalization(.words).accessibilityIdentifier("profileName")
                    TextField("A little about your climbing (optional)", text: $bio, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("profileBio")
                    Text("Display name: 1–60 characters. Bio: up to 500 characters.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                }
                if let account = auth.account {
                    Section(header: Text("Sign-in account").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        LabeledContent("Provider", value: account.provider == .google ? "Google" : "Apple")
                        if let email = account.email { LabeledContent("Email", value: email) }
                        Text("To change your sign-in email, update it with your sign-in provider. Editing your display name here does not change that account.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                    }
                }
                Section { Text("Your profile is saved on this iPhone. It stays private and does not turn on sharing or cloud sync.").font(.footnote).foregroundStyle(ClimbTheme.secondaryText) }
                if let message = profiles.errorMessage {
                    Section(header: Text("Couldn’t save profile").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        Text(message).foregroundStyle(ClimbTheme.error)
                        Button("Retry") { save(retry: true) }.disabled(importing || !valid)
                    }
                }
            }
            .navigationTitle(setup ? "Set up your profile" : "Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(setup ? "Not now" : "Cancel") {
                        if setup {
                            let fallback = auth.account?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Climber"
                            let fallbackName = String((fallback.isEmpty ? "Climber" : fallback).prefix(60))
                            if profiles.save(name: fallbackName, bio: "", photo: nil, setupComplete: false) { dismiss() }
                        } else { dismiss() }
                    }.disabled(importing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(retry: profiles.errorMessage != nil) }.disabled(importing || !valid).accessibilityIdentifier("saveProfile")
                }
            }
            .onAppear {
                guard !initialized else { return }; initialized = true
                name = profiles.profile?.name ?? auth.account?.name ?? ""
                bio = profiles.profile?.bio ?? ""; photo = profiles.profile?.photo
            }
            .task(id: selection) {
                guard let selection else { return }
                importing = true; importError = nil
                defer { importing = false }
                do {
                    guard let file = try await selection.loadTransferable(type: ImportedRouteFile.self) else { throw BackupError.invalid("This photo couldn’t be opened. Try another one.") }
                    let data = file.draft.data
                    let prepared = try await Task.detached(priority: .userInitiated) { try ProfilePhoto.prepare(data) }.value
                    try Task.checkCancellation()
                    photo = prepared
                } catch is CancellationError {} catch { importError = error.localizedDescription }
                self.selection = nil
            }
            .fileImporter(isPresented: $files, allowedContentTypes: [.image]) { result in
                do {
                    let url = try result.get()
                    importing = true; importError = nil
                    Task {
                        defer { importing = false }
                        do {
                            let prepared = try await Task.detached(priority: .userInitiated) {
                                let accessing = url.startAccessingSecurityScopedResource()
                                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                                guard size > 0, size <= ProfilePhoto.maximumImportBytes else { throw BackupError.invalid("Choose a photo smaller than 10 MB.") }
                                return try ProfilePhoto.prepare(Data(contentsOf: url))
                            }.value
                            photo = prepared
                        } catch { importError = error.localizedDescription }
                    }
                } catch { if (error as NSError).code != NSUserCancelledError { importError = error.localizedDescription } }
            }
        }
    }

    private func save(retry: Bool) {
        let success = retry ? profiles.retrySave(name: name, bio: bio, photo: photo) : profiles.save(name: name, bio: bio, photo: photo)
        if success { dismiss() }
    }
}
