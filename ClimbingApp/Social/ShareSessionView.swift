import SwiftUI

struct ShareSessionView: View {
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let session: ClimbingSession
    @State private var draft: SharedSession?
    @State private var includeAttempts = true
    @State private var includeSends = true
    @State private var includeDuration = true

    var body: some View {
        NavigationStack {
            Form {
                if let draft {
                    Section("Audience") {
                        Picker("Visibility", selection: Binding(get: { draft.visibility }, set: { self.draft?.visibility = $0 })) {
                            ForEach(EntryVisibility.allCases) { Text($0.title).tag($0) }
                        }
                        Text(social.me?.is_private == true ? "Your account is private: Public entries can only be seen by friends. Private entries remain yours alone." : "Public entries are visible to signed-in climbers. Friends entries require mutual acceptance. Private entries are yours alone.").font(.caption)
                    }
                    Section("Choose what to share") {
                        TextField("Separate public caption", text: Binding(get: { draft.caption }, set: { self.draft?.caption = $0 }), axis: .vertical)
                        Toggle("Attempts", isOn: $includeAttempts)
                        Toggle("Sends", isOn: $includeSends)
                        Toggle("Recorded duration", isOn: $includeDuration)
                        Button("Refresh summary from journal") {
                            var value = SharedSession(session: session, owner: draft.owner_id)
                            value.caption = draft.caption; value.visibility = draft.visibility
                            self.draft = value
                        }
                    }
                    Section("Exact preview") {
                        if let preview { SharedSessionPreview(entry: preview) }
                        Text("Only this date, caption and selected summary values are sent. Your notes, gym, photos, videos and Health data stay private.").font(.caption)
                    }
                    Section {
                        Button("Save reviewed entry") { Task { if let preview, await social.publish(auth, entry: preview) { dismiss() } } }
                            .disabled(social.busy || draft.caption.count > 1000)
                        Button("Remove shared entry", role: .destructive) { Task { if await social.removeShare(auth, sessionID: session.id) { dismiss() } } }.disabled(social.busy)
                        Text("Saving replaces this entry’s shared snapshot. Later journal edits do not silently change published content. Visibility changes require a connection and a confirmed save.").font(.caption)
                    }
                } else {
                    Text(social.configuration == nil ? "Friends is waiting for Supabase setup. This session is private on this device." : "Connect and set up your social profile in Friends before sharing.")
                }
                if social.busy { SwiftUI.ProgressView("Loading…") }
                if let message = social.errorMessage { Text(message).foregroundStyle(.red); Button("Retry loading") { Task { await load() } } }
            }
            .navigationTitle("Share session")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await load() }
        }
    }

    private var preview: SharedSession? {
        guard var value = draft else { return nil }
        if !includeAttempts { value.attempts = nil }
        if !includeSends { value.sends = nil }
        if !includeDuration { value.duration_minutes = nil }
        return value
    }

    private func load() async {
        guard social.configuration != nil, auth.account != nil else { return }
        await social.refresh(auth)
        guard social.errorMessage == nil, social.me != nil, social.userID != nil else { return }
        if draft == nil { draft = await social.sharedEntry(auth, session: session) }
    }
}
