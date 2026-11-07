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
                Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(ClimbTheme.accent.opacity(0.75))
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .accessibilityLabel(photo == nil ? "Default profile picture" : "Profile picture")
    }
}

struct ProfileEditorView: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(AccountSession.self) private var auth
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    var setup = false
    @State private var username = ""
    @State private var isPrivate = true
    @State private var agreed = false
    @State private var friendsLoaded = false
    @State private var name = ""
    @State private var bio = ""
    @State private var photo: Data?
    @State private var selection: PhotosPickerItem?
    @State private var importing = false
    @State private var files = false
    @State private var initialized = false
    @State private var importError: String?

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.trimmingCharacters(in: .whitespacesAndNewlines).count <= 60 && bio.count <= 500 &&
            (!syncFriends || (!username.trimmingCharacters(in: .whitespaces).isEmpty && bio.unicodeScalars.count <= 240 && (social.me != nil || agreed)))
    }
    // One editor for the whole profile: signed-in climbers also set their Friends username, privacy and agreement here.
    private var signedIn: Bool { auth.account != nil && social.configuration != nil }
    private var joining: Bool { social.me == nil }
    // Setup requires a username; editing later can leave it blank to stay off Friends.
    private var usernameRequired: Bool { friendsLoaded && (!joining || setup) }
    private var syncFriends: Bool { friendsLoaded && (!joining || setup || !username.trimmingCharacters(in: .whitespaces).isEmpty) }
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
                }
                Section(header: Text("About you").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    TextField("Display name *", text: $name).textContentType(.name).textInputAutocapitalization(.words).accessibilityLabel("Display name, required").accessibilityIdentifier("profileName")
                    if friendsLoaded {
                        TextField(usernameRequired ? "Username *" : "Username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityLabel(usernameRequired ? "Username, required" : "Username").accessibilityIdentifier("setupUsername")
                    }
                    Text("* Required").font(.caption).foregroundStyle(ClimbTheme.secondaryText).accessibilityHidden(true)
                    TextField("A little about your climbing (optional)", text: $bio, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("profileBio")
                    if syncFriends { Text("\(bio.unicodeScalars.count)/240 characters").font(.caption).foregroundStyle(ClimbTheme.secondaryText) }
                }
                if signedIn {
                    Section(header: Text("Friends").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        if friendsLoaded {
                            Text(joining && !setup ? "Add a username to join Friends, or leave it blank to stay off Friends. Usernames are 3–24 lowercase letters, numbers or underscores." :
                                    "Your username is 3–24 lowercase letters, numbers or underscores, and is visible to signed-in climbers. Your email stays private.")
                                .font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                            Toggle("Private account", isOn: $isPrivate)
                            if let discovery = social.suggestions.discoveryEnabled {
                                Toggle("Let friends of friends find me", isOn: Binding(get: { discovery }, set: { value in
                                    Task { await social.suggestions.setDiscovery(value, service: SocialSuggestionService(store: social, auth: auth)) }
                                })).disabled(social.suggestions.savingSetting)
                            }
                            if joining {
                                // Required before any user-generated content is shared (App Store Guideline 1.2).
                                Text("No objectionable, hateful, sexual or harassing content, and no abuse of other climbers. Report or block anyone who breaks these rules. We review reports and remove content and accounts that break them.").font(.caption)
                                NavigationLink("Read the Privacy Policy") { PrivacyPolicyView() }
                                Toggle("I agree to the community rules and the Privacy Policy *", isOn: $agreed).accessibilityLabel("I agree to the community rules and the Privacy Policy, required").accessibilityIdentifier("setupAgree")
                            }
                        } else if !social.busy && !social.needsAppleSignIn {
                            Button("Retry loading your Friends profile") { Task { await loadFriends() } }
                        }
                        if social.busy { SwiftUI.ProgressView(friendsLoaded ? "Saving your Friends profile…" : "Loading your Friends profile…") }
                        if let message = social.errorMessage { Text(message).font(.subheadline).foregroundStyle(ClimbTheme.error) }
                        // After a relaunch Apple's sign-in token is gone, so Apple confirms again before Friends can load or save.
                        if social.needsAppleSignIn { AppleConfirmButton { if friendsLoaded { save(retry: profiles.errorMessage != nil) } else { await loadFriends() } } }
                    }
                }
                if let account = auth.account {
                    Section(header: Text("Sign-in account").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        LabeledContent("Provider", value: account.provider == .google ? "Google" : "Apple")
                        if let email = account.email { LabeledContent("Email", value: email) }
                    }
                }
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
                    Button("Save") { save(retry: profiles.errorMessage != nil) }.disabled(importing || social.busy || !valid).accessibilityIdentifier("saveProfile")
                }
            }
            .onAppear {
                guard !initialized else { return }; initialized = true
                name = profiles.profile?.name ?? auth.account?.name ?? ""
                bio = profiles.profile?.bio ?? ""; photo = profiles.profile?.photo
            }
            .task { if signedIn { await loadFriends() } }
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

    /// Loads the Friends profile so editing shows the current username, privacy and discovery setting.
    private func loadFriends() async {
        await social.refresh(auth)
        guard social.errorMessage == nil else { return }
        if let me = social.me {
            username = me.username; isPrivate = me.is_private
            if bio.isEmpty, let details = try? await social.profileDetails(auth, id: me.id) { bio = details.bio }
            await social.suggestions.loadDiscovery(SocialSuggestionService(store: social, auth: auth))
        }
        friendsLoaded = true
    }

    private func save(retry: Bool) {
        let success = retry ? profiles.retrySave(name: name, bio: bio, photo: photo) : profiles.save(name: name, bio: bio, photo: photo)
        guard success else { return }
        guard syncFriends else { dismiss(); return }
        let socialBio = String(String.UnicodeScalarView(bio.unicodeScalars.prefix(240)))
        let socialPhoto = photo.flatMap { try? SocialPhoto.prepare($0) }
        Task { if await social.saveProfile(auth, username: username, name: name, isPrivate: isPrivate, bio: socialBio, photo: socialPhoto) { dismiss() } }
    }
}
