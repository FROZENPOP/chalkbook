import SwiftUI

private enum FriendsSection: String, CaseIterable {
    case activity = "Activity", friends = "Friends", requests = "Requests"
}

struct FriendsView: View {
    #if DEBUG
    var auditProfile: SocialProfile? = nil
    #endif
    private var auditConnected: Bool {
        #if DEBUG
        return AccessibilityAuditFixtures.enabled && auditProfile != nil
        #else
        return false
        #endif
    }
    @Environment(AccountSession.self) private var auth
    @Environment(SocialStore.self) private var social
    @State private var login = false
    @State private var profile = false
    @State private var finding = false
    @State private var section = FriendsSection.activity
    private var friends: [Friendship] { social.friendships.filter { $0.status == "accepted" } }
    private var requests: [Friendship] { social.friendships.filter { $0.status == "pending" } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if social.configuration != nil, auth.account != nil {
                    RemovalStatusView(outbox: social.removals) { await social.retryRemovals(auth, force: true) }
                }
                if social.configuration == nil && !auditConnected {
                    EmptyState(title: "Friends is coming next", symbol: "person.2", message: "Supabase setup is pending. Your journal stays private and works offline.")
                } else if auth.account == nil && !auditConnected {
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Climbing is better together.").font(.title2.bold())
                            Text("Connect with your people and share the sessions you choose.").foregroundStyle(ClimbTheme.secondaryText)
                            Button("Sign in to find friends") { login = true }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                        }
                    }
                } else if social.me == nil && !auditConnected {
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: "person.2.fill").font(.largeTitle).foregroundStyle(ClimbTheme.forest)
                            Text("Find your climbing people.").font(.title2.bold())
                            Text("Choose a username so friends can find you. You decide which sessions to share.").foregroundStyle(ClimbTheme.secondaryText)
                            Button("Set up Friends") { profile = true }.buttonStyle(.borderedProminent).disabled(social.userID == nil || social.busy)
                            if !social.busy { Button("Connect / Retry") { Task { await social.refresh(auth) } } }
                        }
                    }
                } else {
                    header
                    if !requests.isEmpty {
                        Button { section = .requests } label: {
                            Label("\(requests.count) pending \(requests.count == 1 ? "request" : "requests")",systemImage:"person.crop.circle.badge.clock")
                        }.frame(minHeight:44).accessibilityLabel("View \(requests.count) pending friend requests")
                    }
                    if let viewer=social.userID {
                        SuggestedFriendsSection(state:social.suggestions,service:SocialSuggestionService(store:social,auth:auth),
                            excluded:Set(social.friendships.map { $0.other(than:viewer) }),blocked:Set(social.blocks.map(\.id)),viewer:viewer)
                    }
                    Picker("Friends section", selection: $section) {
                        ForEach(FriendsSection.allCases, id: \.self) { item in
                            Text(item == .requests && !requests.isEmpty ? "Requests (\(requests.count))" : item.rawValue).tag(item)
                        }
                    }.pickerStyle(.segmented)
                    sectionContent
                }
                if let message = social.errorMessage {
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Couldn’t connect", systemImage: "wifi.exclamationmark").font(.headline)
                            Text(message).font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
                            if social.needsAppleSignIn { AppleConfirmButton { await refresh() } }
                            else { Button("Try again") { Task { await social.refresh(auth) } }.frame(minHeight: 44) }
                        }
                    }
                }
                if social.busy { SwiftUI.ProgressView("Updating Friends…").frame(maxWidth: .infinity) }
            }.padding(20)
        }
        .background(ClimbTheme.background)
        .navigationTitle("Friends")
        .toolbar {
            if social.me != nil || auditConnected {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { profile = true } label: { Image(systemName: "person.crop.circle").frame(width: 44, height: 44) }.accessibilityLabel("Social profile and privacy")
                }
            }
        }
        .refreshable { await refresh() }
        .task { await refresh() }
        .sheet(isPresented: $login) { LoginPortalView() }
        .sheet(isPresented: $profile) { SocialProfileEditor() }
        .sheet(isPresented: $finding) { NavigationStack { AddFriendsView() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your climbing circle").font(.title2.bold())
                Spacer()
                Text("\(friends.count) \(friends.count == 1 ? "friend" : "friends")").font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
            }
            Button { finding = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "magnifyingglass").font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add friends").font(.headline)
                        Text("Name, username or QR code").font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "plus.circle.fill").font(.title2)
                }.padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain).foregroundStyle(ClimbTheme.forest).accessibilityIdentifier("findFriends")
        }
    }

    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .activity:
            FriendsFeedContent(feed:social.feed,refreshing:social.busy,next:{ await social.loadNextFeed(auth) },findFriends:{ finding=true }) { entry in
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            SocialAvatar(id:entry.owner_id,name:person(entry.owner_id)?.display_name ?? "Climber")
                            Text(person(entry.owner_id)?.display_name ?? "Climber").font(.headline)
                            Spacer()
                            Image(systemName: entry.visibility == .public ? "globe" : "person.2").foregroundStyle(ClimbTheme.secondaryText).accessibilityLabel(entry.visibility.title)
                        }
                        SharedSessionPreview(entry: entry)
                        SessionReactionBar(entry:entry)
                    }
                }
            }
        case .friends:
            if friends.isEmpty {
                FriendsEmptyCard(symbol: "person.2", title: "Your next climbing buddy is out there.", message: "Search their username and send a request. Once they accept, you’re friends.") {
                    Button("Find friends") { finding = true }.buttonStyle(.borderedProminent)
                }
            }
            ForEach(friends) { link in if let id = social.userID { FriendPersonRow(person: person(link.other(than: id)), personID: link.other(than: id)) } }
            if !social.blocks.isEmpty {
                DisclosureGroup("Blocked climbers (\(social.blocks.count))") {
                    ForEach(social.blocks) { block in
                        Button("Unblock climber \(block.id.uuidString.prefix(8))") { Task { await social.unblock(auth, target: block.id) } }.frame(minHeight: 44).disabled(social.busy)
                    }
                }.font(.subheadline)
            }
        case .requests:
            if requests.isEmpty {
                FriendsEmptyCard(symbol: "tray", title: "All caught up.", message: "Incoming and sent friend requests will show up here.") { EmptyView() }
            }
            ForEach(requests) { link in if let id = social.userID { FriendPersonRow(person: person(link.other(than: id)), personID: link.other(than: id)) } }
        }
    }

    private func person(_ id: UUID) -> SocialProfile? { social.people.first { $0.id == id } }
    private func refresh() async {
        #if DEBUG
        if auditConnected { await social.feed.refresh(AccessibilityAuditEmptyFeed()); return }
        #endif
        guard social.configuration != nil, auth.account != nil else { social.suggestions.reset(); return }
        await social.refresh(auth)
        guard social.errorMessage == nil, let viewer=social.userID, social.me != nil else { social.suggestions.reset(); return }
        await social.suggestions.load(SocialSuggestionService(store:social,auth:auth),owner:viewer,
            excluding:Set(social.friendships.map { $0.other(than:viewer) } + social.blocks.map(\.id)))
    }
}

struct FriendInitials: View {
    @ScaledMetric(relativeTo: .headline) private var size = 48.0
    let name: String
    private var initials: String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
    var body: some View {
        Text(initials.isEmpty ? "?" : initials).font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(ClimbTheme.forest).frame(width: size, height: size)
            .background(ClimbTheme.forest.opacity(0.1), in: Circle()).accessibilityHidden(true)
    }
}

struct FriendsEmptyCard<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: symbol).font(.largeTitle).foregroundStyle(ClimbTheme.forest)
                Text(title).font(.title3.bold())
                Text(message).font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
                actions.frame(minHeight: 44)
            }.padding(.vertical, 8)
        }
    }
}

#if DEBUG
@MainActor private struct AccessibilityAuditEmptyFeed: FriendsFeedReading {
    func page(after: FriendsFeedCursor?, limit: Int) async throws -> FriendsFeedPage { .init(entries: []) }
}
#endif
