import SwiftUI

struct FriendsView: View {
    @Environment(AccountSession.self) private var auth
    @Environment(SocialStore.self) private var social
    @State private var login = false
    @State private var profile = false
    @State private var search = ""

    var body: some View {
        List {
            if social.configuration == nil {
                Section {
                    ContentUnavailableView("Friends is coming next", systemImage: "person.2", description: Text("Supabase setup is pending. Your journal stays private and works offline. Friend requests and shared entries will appear here when connected."))
                }
            } else if auth.account == nil {
                Section {
                    Text("Connect with friends and choose which completed sessions to share.")
                    Button("Sign in") { login = true }
                }
            } else {
                if social.me == nil {
                    Section {
                        Text("Create a social profile to receive friend requests. Only the name and username you choose will be visible in discovery.")
                        Button("Set up Friends") { profile = true }.disabled(social.userID == nil)
                        Button("Connect / Retry") { Task { await social.refresh(auth) } }
                    }
                } else {
                    Section {
                        Button("Edit social profile and privacy") { profile = true }
                        Text("Friend requests always need approval, for public and private accounts.").font(.caption)
                    }
                    Section("Friend requests") {
                        let requests = social.friendships.filter { $0.status == "pending" && $0.recipient == social.userID }
                        if requests.isEmpty { Text("No incoming requests").foregroundStyle(.secondary) }
                        ForEach(requests) { link in friendRow(id: link.requester, link: link) }
                    }
                    Section("Your friends") {
                        let friends = social.friendships.filter { $0.status == "accepted" }
                        if friends.isEmpty { Text("Find someone below and send a friend request.").foregroundStyle(.secondary) }
                        ForEach(friends) { link in friendRow(id: link.other(than: social.userID!), link: link) }
                    }
                    Section("Find climbers") {
                        TextField("Filter by username or name", text: $search).autocorrectionDisabled()
                        Text("Showing up to 200 profiles. Only basic names are discoverable; private entries remain private.").font(.caption).foregroundStyle(.secondary)
                        ForEach(social.people.filter { $0.id != social.userID && (search.isEmpty || $0.username.localizedCaseInsensitiveContains(search) || $0.display_name.localizedCaseInsensitiveContains(search)) }) { person in
                            friendRow(id: person.id, link: social.friendships.first { $0.other(than: social.userID!) == person.id })
                        }
                    }
                    Section("Shared progress") {
                        Text("Only reviewed sessions shared with you appear here. These totals do not represent a person’s complete journal.").font(.caption)
                        if social.entries.filter({ $0.owner_id != social.userID }).isEmpty { Text("No shared sessions yet").foregroundStyle(.secondary) }
                        ForEach(social.entries.filter { $0.owner_id != social.userID }) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(name(entry.owner_id)).font(.headline)
                                SharedSessionPreview(entry: entry)
                            }.padding(.vertical, 6)
                        }
                    }
                    if !social.blocks.isEmpty {
                        Section("Blocked climbers") {
                            ForEach(social.blocks) { block in
                                Button("Unblock climber \(block.target_id.uuidString.prefix(8))") { Task { await social.unblock(auth, target: block.target_id) } }.disabled(social.busy)
                            }
                        }
                    }
                }
                if let message = social.errorMessage {
                    Section { Text(message).foregroundStyle(.red); Button("Retry") { Task { await social.refresh(auth) } } }
                }
                if social.busy { SwiftUI.ProgressView("Connecting…") }
            }
        }
        .navigationTitle("Friends")
        .refreshable { if social.configuration != nil && auth.account != nil { await social.refresh(auth) } }
        .task { if social.configuration != nil && auth.account != nil { await social.refresh(auth) } }
        .sheet(isPresented: $login) { LoginPortalView() }
        .sheet(isPresented: $profile) { SocialProfileEditor() }
    }

    private func name(_ id: UUID) -> String { social.people.first { $0.id == id }?.display_name ?? "Climber" }

    @ViewBuilder private func friendRow(id: UUID, link: Friendship?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let person = social.people.first { $0.id == id }
            Text(person.map { "\($0.display_name) · @\($0.username)" } ?? "Climber").font(.headline)
            if link?.status == "accepted" {
                NavigationLink("View shared progress") { FriendProgressView(climberID: id, name: name(id)) }
            }
            HStack {
                if let link {
                    if link.status == "accepted" { action("Remove friend", id, "remove") }
                    else if link.recipient == social.userID { action("Accept", id, "accept"); action("Decline", id, "decline") }
                    else { Text("Request sent").font(.caption); action("Cancel", id, "cancel") }
                } else { action("Add friend", id, "request") }
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Block climber", role: .destructive) { Task { await social.safetyAction(auth, target: id, block: true) } }
                    NavigationLink("Report climber") { ReportClimberView(target: id) }
                }
            }.buttonStyle(.bordered).disabled(social.busy)
        }.padding(.vertical, 4)
    }
    private func action(_ title: String, _ target: UUID, _ action: String) -> some View {
        Button(title) { Task { await social.action(auth, target: target, action: action) } }.frame(minHeight: 44)
    }
}

struct SocialProfileEditor: View {
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var name = ""
    @State private var isPrivate = true
    @State private var confirmDelete = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Discoverable profile") {
                    TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Display name", text: $name)
                    Text("Your username and display name are visible to signed-in climbers. Local profile photos, email and bio are not uploaded.").font(.caption)
                }
                Section("Account privacy") {
                    Toggle("Private account", isOn: $isPrivate)
                    Text("A private account limits Public entries to approved friends. Private entries are always yours alone. Friendship always requires acceptance.").font(.caption)
                }
                if let message = social.errorMessage { Text(message).foregroundStyle(.red) }
                Button("Save social profile") {
                    Task { if await social.saveProfile(auth, username: username, name: name, isPrivate: isPrivate) { dismiss() } }
                }.disabled(social.busy)
                if social.me != nil {
                    Section {
                        Button("Delete social profile", role: .destructive) { confirmDelete = true }.disabled(social.busy)
                        Text("Removes your friend connections, requests and shared entries. Your private local journal and Google account are preserved.").font(.caption)
                    }
                }
            }.navigationTitle(social.me == nil ? "Join Friends" : "Social profile")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onAppear { username = social.me?.username ?? ""; name = social.me?.display_name ?? profiles.profile?.name ?? ""; isPrivate = social.me?.is_private ?? true }
                .confirmationDialog("Delete your social profile and all shared entries?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete social profile", role: .destructive) { Task { if await social.deleteProfile(auth) { dismiss() } } }
                }
        }
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
                if let message = social.errorMessage { Text(message).foregroundStyle(.red) }
            }
        }.navigationTitle("Report climber")
    }
}

struct SharedSessionPreview: View {
    let entry: SharedSession
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.session_day).font(.subheadline)
            if !entry.caption.isEmpty { Text(entry.caption) }
            Text("\(entry.attempts.map(String.init) ?? "Unknown") attempts · \(entry.sends.map(String.init) ?? "Unknown") sends")
            Text(entry.duration_minutes.map { "\($0) minutes recorded" } ?? "Duration not recorded").font(.caption)
            Text(entry.completeness).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
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
            Section("Shared progress") {
                Text("\(entries.count) shared sessions in the current feed (up to 200 entries). This is not their complete climbing history.")
                Text("\(entries.compactMap(\.attempts).reduce(0,+)) attempts across \(entries.filter { $0.attempts != nil }.count) entries with attempt totals")
                Text("\(entries.compactMap(\.sends).reduce(0,+)) sends across \(entries.filter { $0.sends != nil }.count) entries with send totals")
                Text("Missing values are excluded. No grades or flash rates are inferred.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(entries) { SharedSessionPreview(entry: $0) }
            if let message = social.errorMessage { Text(message).foregroundStyle(.red) }
        }.navigationTitle(name).refreshable { await social.refresh(auth) }
    }
}
