import SwiftUI
import PhotosUI

struct SocialProfileEditor: View {
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var name = ""
    @State private var isPrivate = true
    @State private var confirmDelete = false
    @State private var bio = ""
    @State private var photo:Data?
    @State private var selection:PhotosPickerItem?
    @State private var ready = false
    @State private var importing=false
    @State private var initialized=false
    @State private var loadError:String?
    @State private var agreed = false
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Discoverable profile").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Display name", text: $name)
                    Text("Your username and display name are visible to signed-in climbers. Your email stays private.").font(.caption)
                }
                Section(header: Text("Optional climbing profile").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    ProfileAvatar(photo:photo)
                    PhotosPicker("Choose profile photo",selection:$selection,matching:.images)
                    if importing { SwiftUI.ProgressView("Preparing photo…") }
                    if let local=profiles.profile?.photo { Button("Use my local profile photo") { do { photo=try SocialPhoto.prepare(local) } catch { loadError=error.localizedDescription } } }
                    if photo != nil { Button("Remove shared photo",role:.destructive) { photo=nil } }
                    TextField("A little about your climbing",text:$bio,axis:.vertical).lineLimit(3...5)
                    Text("\(bio.count)/240 characters").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                    if let local=profiles.profile?.bio,!local.isEmpty { Button("Copy my local bio into this draft") { bio=String(local.prefix(240)) } }
                    Text("Only the photo and bio shown here will be published when you save. On a private account, only friends can see them. Public accounts make them visible to signed-in climbers.").font(.caption)
                }.disabled(!ready || social.busy || importing)
                Section(header: Text("Account privacy").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    Toggle("Private account", isOn: $isPrivate)
                    Text("A private account limits Public entries to approved friends. Private entries are always yours alone. Friendship always requires acceptance.").font(.caption)
                }
                if social.me != nil {
                    Section(header: Text("Friend discovery").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        if social.suggestions.discoveryEnabled != nil {
                            Toggle("Let friends of friends find me",isOn:Binding(get:{ social.suggestions.discoveryEnabled ?? true },set:{ value in
                                Task { await social.suggestions.setDiscovery(value,service:SocialSuggestionService(store:social,auth:auth)) }
                            })).disabled(social.suggestions.savingSetting)
                        }
                        Text("Your profile may be suggested to climbers with mutual friends. Turn off to stop appearing in suggestions. Changes save immediately.").font(.caption)
                        if social.suggestions.savingSetting { SwiftUI.ProgressView("Saving discovery setting…") }
                        if let error=social.suggestions.settingError {
                            Text(error).foregroundStyle(ClimbTheme.error)
                            Button("Retry discovery setting") { Task { await social.suggestions.loadDiscovery(SocialSuggestionService(store:social,auth:auth)) } }
                        }
                    }
                }
                if social.me == nil {
                    // Required before any user-generated content is shared (App Store Guideline 1.2).
                    Section(header: Text("Community rules").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        Text("No objectionable, hateful, sexual or harassing content, and no abuse of other climbers. Report or block anyone who breaks these rules. We review reports and remove content and accounts that break them.").font(.caption)
                        Toggle("I agree to the community rules", isOn: $agreed).accessibilityIdentifier("agreeCommunityRules")
                    }
                }
                if let message = social.errorMessage { Text(message).foregroundStyle(ClimbTheme.error) }
                Button("Save social profile") {
                    Task { if await social.saveProfile(auth, username: username, name: name, isPrivate: isPrivate,bio:bio,photo:photo) { dismiss() } }
                }.disabled(social.busy || !ready || importing || bio.count>240 || (social.me == nil && !agreed))
                if let loadError { Text(loadError).foregroundStyle(ClimbTheme.error);if !ready { Button("Retry loading profile") { Task { await loadDetails() } } } }
                if social.me != nil {
                    Section {
                        Button("Delete social profile", role: .destructive) { confirmDelete = true }.disabled(social.busy)
                        Text("Removes your friend connections, requests and shared entries. If offline, removal waits to sync and friends may still see them until then. Your private local journal and Google account are preserved.").font(.caption)
                    }
                }
            }.navigationTitle(social.me == nil ? "Join Friends" : "Social profile")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onAppear { if !initialized { username = social.me?.username ?? ""; name = social.me?.display_name ?? profiles.profile?.name ?? ""; isPrivate = social.me?.is_private ?? true;initialized=true } }
                .task {
                    if !ready { await loadDetails() }
                    if social.me != nil { await social.suggestions.loadDiscovery(SocialSuggestionService(store:social,auth:auth)) }
                }
                .onChange(of:selection) { _,value in if value != nil { importing=true } }
                .task(id:selection) {
                    guard let selection else { return }
                    defer { importing=false }
                    do { if let data=try await selection.loadTransferable(type:Data.self) { photo=try SocialPhoto.prepare(data);loadError=nil } } catch { loadError=error.localizedDescription }
                    self.selection=nil
                }
                .confirmationDialog("Delete your social profile and all shared entries?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete social profile", role: .destructive) { Task { if await social.deleteProfile(auth) { dismiss() } } }
                }
        }
    }

    private func loadDetails() async {
        guard let id=social.me?.id else { ready=true;return }
        do {
            let details=try await social.profileDetails(auth,id:id)
            bio=details?.bio ?? "";photo=details?.photo;ready=true;loadError=nil
        } catch { loadError=error.localizedDescription;ready=false }
    }
}

struct ReportClimberView: View {
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    let target: UUID
    @State private var reason = ""
    @State private var submitted = false
    var body: some View {
        Form {
            if submitted { Text("Report submitted for review.") }
            else {
                TextField("Describe the concern", text: $reason, axis: .vertical).lineLimit(4...8)
                Button("Submit report") { Task { submitted = await social.safetyAction(auth, target: target, block: false, reason: reason) } }
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.count > 1000 || social.busy)
                if let message = social.errorMessage { Text(message).foregroundStyle(ClimbTheme.error) }
            }
        }.navigationTitle("Report climber")
    }
}

struct SharedSessionPreview: View {
    let entry: SharedSession
    var routePhotos: [SharedRoutePhoto]? = nil
    @State private var viewingPhotos = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SessionDay.label(for: entry.session_day)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            if !entry.caption.isEmpty { Text(entry.caption).fixedSize(horizontal: false, vertical: true) }
            Text("\(entry.attempts?.counted("attempt") ?? "Unknown attempts") · \(entry.sends?.counted("send") ?? "Unknown sends")")
            Text(entry.duration_minutes.map { "\($0.counted("minute")) recorded" } ?? "Duration not recorded").font(.caption)
            Text(entry.completeness).fixedSize(horizontal: false, vertical: true).font(.caption).foregroundStyle(ClimbTheme.secondaryText)
            if (routePhotos?.count ?? entry.route_photo_count ?? 0) > 0 {
                Button("View climb photos", systemImage:"photo.on.rectangle") { viewingPhotos = true }
                    .frame(minHeight:44).accessibilityIdentifier("viewSharedRoutePhotos")
                Text("Photos are never public; friends can view them when this entry is shared with them.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
            }
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .contain)
            .sheet(isPresented:$viewingPhotos) {
                NavigationStack { SharedRoutePhotosView(entryID:entry.id,previewPhotos:routePhotos) }
            }
    }
}

struct FriendProgressView: View {
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    let climberID: UUID
    let name: String
    private var entries: [SharedSession] { social.entries.filter { $0.owner_id == climberID } }
    var body: some View {
        List {
            Section(header: Text("Shared progress").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                Text("\(entries.count) shared sessions in the currently loaded feed pages. This is not their complete climbing history.")
                Text("\(entries.compactMap(\.attempts).reduce(0,+)) attempts across \(entries.filter { $0.attempts != nil }.count) entries with attempt totals")
                Text("\(entries.compactMap(\.sends).reduce(0,+)) sends across \(entries.filter { $0.sends != nil }.count) entries with send totals")
                Text("Missing values are excluded. No grades or flash rates are inferred.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
            }
            ForEach(entries) { SharedSessionPreview(entry: $0) }
            if let message = social.errorMessage { Text(message).foregroundStyle(ClimbTheme.error) }
        }.navigationTitle(name).refreshable { await social.refresh(auth) }
    }
}
