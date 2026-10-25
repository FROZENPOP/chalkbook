import SwiftUI

struct SocialClimberProfileView: View {
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    let climberID:UUID
    @State private var page:SocialProfilePage?
    @State private var error:String?
    @State private var editing=false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                if let page {
                    Surface {
                        VStack(alignment:.leading,spacing:14) {
                            ProfileAvatar(photo:page.details?.photo)
                            Text(page.profile.display_name).font(.title.bold())
                            Text("@\(page.profile.username)").foregroundStyle(.secondary)
                            if let bio=page.details?.bio,!bio.isEmpty { Text(bio) }
                            Label(page.profile.is_private ? "Private account" : "Public account",systemImage:page.profile.is_private ? "lock" : "globe").font(.caption)
                            if page.profile.is_private && page.details == nil { Text("Their bio and photo are visible to friends.").font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }
                    if page.profile.id == social.userID { Button("Edit your social profile") { editing=true } }
                    else if social.me == nil { Button("Set up Friends to send a request") { editing=true } }
                    else { FriendPersonRow(person:page.profile,personID:page.profile.id,showsProfileLink:false) }
                    Text("Shared sessions").font(.title2.bold())
                    Text("Only sessions this person has made visible to you appear here. Their private journal is never shown.").font(.caption).foregroundStyle(.secondary)
                    if page.entries.isEmpty { Text("No sessions shared with you yet.").foregroundStyle(.secondary) }
                    ForEach(page.entries) { entry in
                        Surface { VStack(alignment:.leading,spacing:16) { SharedSessionPreview(entry:entry);SessionReactionBar(entry:entry) } }
                    }
                } else if error == nil { SwiftUI.ProgressView("Opening profile…") }
                if let error { Text(error).foregroundStyle(.red);Button("Try again") { Task { await load() } } }
            }.padding(20)
        }.background(ClimbTheme.background).navigationTitle("Climber profile").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$editing,onDismiss:{ Task { await load() } }) { SocialProfileEditor() }
            .task { await load() }.refreshable { await load() }
            .onChange(of:social.friendships.map(\.id).joined()+social.friendships.map(\.status).joined()+social.blocks.map { $0.id.uuidString }.joined()) { _,_ in Task { await load() } }
    }
    private func load() async {
        do { if social.userID == nil { await social.refresh(auth) };page=try await social.profilePage(auth,id:climberID);error=nil }
        catch { page=nil;self.error=error.localizedDescription }
    }
}

struct SessionReactionBar: View {
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    let entry:SharedSession
    @State private var summaries:[ReactionSummary]=[]
    @State private var busy=false
    @State private var loaded=false
    @State private var error:String?
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            if loaded { reactionButtons }
            else if error == nil { SwiftUI.ProgressView("Loading reactions…") }
            if social.me == nil { Text("Set up Friends to react.").font(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).font(.caption).foregroundStyle(.red);Button("Retry reactions") { Task { await load() } }.frame(minHeight:44) }
        }.task(id:entry.id) { await load() }
    }
    private var reactionButtons: some View {
        let layout=textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:10)) : AnyLayout(HStackLayout(spacing:10))
        return layout {
            ForEach(SessionReaction.allCases) { reaction in
                let summary=summaries.first { $0.kind == reaction.rawValue }
                Button {
                    busy=true
                    Task {
                        do { try await social.react(auth,entry:entry.id,reaction:summary?.mine == true ? nil : reaction);await load() }
                        catch { self.error=error.localizedDescription }
                        busy=false
                    }
                } label: {
                    Text("\(reaction.emoji) \(summary?.total ?? 0)").font(.subheadline.weight(.semibold)).padding(.horizontal,12).frame(minHeight:44)
                        .background(summary?.mine == true ? ClimbTheme.forest.opacity(0.16) : Color.secondary.opacity(0.08),in:Capsule())
                }.buttonStyle(.plain).disabled(busy || social.me == nil || social.userID == entry.owner_id)
                    .accessibilityLabel("\(reaction.label), \(summary?.total ?? 0) reactions\(summary?.mine == true ? ", selected" : "")")
            }
        }
    }
    private func load() async {
        loaded=false
        do { summaries=try await social.reactions(auth,entry:entry.id);loaded=true;error=nil }
        catch { summaries=[];self.error=error.localizedDescription }
    }
}

struct SocialAvatar: View {
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    let id:UUID
    let name:String
    @State private var photo:Data?
    var body: some View {
        Group { if let photo { ProfileAvatar(photo:photo,size:48) } else { FriendInitials(name:name) } }
            .task(id:id) { photo=(try? await social.profileDetails(auth,id:id))?.photo }
            .accessibilityHidden(true)
    }
}
