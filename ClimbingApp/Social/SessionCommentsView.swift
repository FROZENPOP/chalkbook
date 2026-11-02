import SwiftUI

struct SessionCommentsView: View {
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    let entry: SharedSession
    @Binding var comments: [SessionComment]?
    @State private var text = ""
    @State private var sending = false
    @State private var error: String?
    @State private var deleting: SessionComment?
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Surface { SharedSessionPreview(entry: entry) }
                if let comments, comments.isEmpty { Text("No comments yet.").foregroundStyle(ClimbTheme.secondaryText) }
                ForEach(comments ?? []) { row($0) }
                if comments == nil && error == nil { SwiftUI.ProgressView("Loading comments…").frame(maxWidth: .infinity) }
                if let error {
                    Text(error).font(.subheadline).foregroundStyle(ClimbTheme.error).accessibilityIdentifier("commentError")
                    if comments == nil { Button("Try again") { Task { await load() } }.frame(minHeight: 44) }
                }
            }.padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ClimbTheme.background)
        .navigationTitle("Comments").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { if social.me != nil { composer } }
        .task { await load() }
        .confirmationDialog("Delete this comment?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { comment in
            Button("Delete comment", role: .destructive) { Task { await delete(comment) } }
        }
    }

    private func row(_ comment: SessionComment) -> some View {
        let name = comment.author?.display_name ?? "Climber"
        return Surface {
            HStack(alignment: .top, spacing: 12) {
                SocialAvatar(id: comment.user_id, name: name)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline)
                    Text(comment.created_at, format: .relative(presentation: .named)).font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                    Text(comment.body).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
                Menu {
                    if comment.user_id == social.userID || entry.owner_id == social.userID { Button("Delete comment", role: .destructive) { deleting = comment } }
                    if comment.user_id != social.userID {
                        Button("Block climber", role: .destructive) { Task { await block(comment.user_id) } }
                        NavigationLink("Report climber") { ReportClimberView(target: comment.user_id) }
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("Options for comment by \(name)").accessibilityIdentifier("commentOptions")
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Add a comment", text: $text, axis: .vertical).lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                .accessibilityIdentifier("commentField")
            if text.count > 450 { Text("\(text.count)/500").font(.caption).foregroundStyle(text.count > 500 ? ClimbTheme.error : ClimbTheme.secondaryText).frame(minHeight: 44) }
            Button { Task { await send() } } label: {
                if sending { SwiftUI.ProgressView().frame(width: 44, height: 44) }
                else { Image(systemName: "arrow.up.circle.fill").font(.title).frame(width: 44, height: 44) }
            }
            .disabled(trimmed.isEmpty || text.count > 500 || sending)
            .accessibilityLabel("Post comment").accessibilityIdentifier("postComment")
        }.padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
    }

    private func load() async {
        do { comments = try await social.comments(auth, entry: entry.id); error = nil }
        catch { if comments == nil { self.error = error.localizedDescription } }
    }
    private func send() async {
        sending = true; defer { sending = false }
        // The draft stays in the field until the server confirms the save.
        do { comments = (comments ?? []) + [try await social.addComment(auth, entry: entry.id, body: trimmed)]; text = ""; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func delete(_ comment: SessionComment) async {
        do { try await social.deleteComment(auth, id: comment.id); comments?.removeAll { $0.id == comment.id }; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func block(_ climber: UUID) async {
        if await social.safetyAction(auth, target: climber, block: true) { comments?.removeAll { $0.user_id == climber } }
        else { error = social.errorMessage }
    }
}
