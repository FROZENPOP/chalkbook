import SwiftUI

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
