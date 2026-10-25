import SwiftUI

private enum FriendsSection: String, CaseIterable {
    case activity = "Activity", friends = "Friends", requests = "Requests"
}

struct FriendsView: View {
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
            VStack(alignment: .leading, spacing: 24) {
                if social.configuration == nil {
                    EmptyState(title: "Friends is coming next", symbol: "person.2", message: "Supabase setup is pending. Your journal stays private and works offline.")
                } else if auth.account == nil {
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Climbing is better together.").font(.title2.bold())
                            Text("Connect with your people and share the sessions you choose.").foregroundStyle(.secondary)
                            Button("Sign in to find friends") { login = true }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                        }
                    }
                } else if social.me == nil {
                    Surface {
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: "person.2.fill").font(.largeTitle).foregroundStyle(ClimbTheme.forest)
                            Text("Find your climbing people.").font(.title2.bold())
                            Text("Choose a username so friends can find you. You decide which sessions to share.").foregroundStyle(.secondary)
                            Button("Set up Friends") { profile = true }.buttonStyle(.borderedProminent).disabled(social.userID == nil || social.busy)
                            if !social.busy { Button("Connect / Retry") { Task { await social.refresh(auth) } } }
                        }
                    }
                } else {
                    header
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
                            Text(message).font(.subheadline).foregroundStyle(.secondary)
                            Button("Try again") { Task { await social.refresh(auth) } }.frame(minHeight: 44)
                        }
                    }
                }
                if social.busy { SwiftUI.ProgressView("Updating Friends…").frame(maxWidth: .infinity) }
            }.padding(20)
        }
        .background(ClimbTheme.background)
        .navigationTitle("Friends")
        .toolbar {
            if social.me != nil {
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
                Text("\(friends.count) \(friends.count == 1 ? "friend" : "friends")").font(.subheadline).foregroundStyle(.secondary)
            }
            Button { finding = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "magnifyingglass").font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add friends").font(.headline)
                        Text("Name, username or QR code").font(.subheadline).foregroundStyle(.secondary)
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
            let shared = social.entries.filter { $0.owner_id != social.userID }
            if shared.isEmpty {
                FriendsEmptyCard(symbol: "figure.climbing", title: "A little encouragement goes a long way.", message: "Shared sessions from your friends will appear here. Find a climbing buddy to get started.") {
                    Button("Add friends", systemImage: "person.badge.plus") { finding = true }.buttonStyle(.borderedProminent)
                }
            }
            ForEach(shared) { entry in
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            SocialAvatar(id:entry.owner_id,name:person(entry.owner_id)?.display_name ?? "Climber")
                            Text(person(entry.owner_id)?.display_name ?? "Climber").font(.headline)
                            Spacer()
                            Image(systemName: entry.visibility == .public ? "globe" : "person.2").foregroundStyle(.secondary).accessibilityLabel(entry.visibility.title)
                        }
                        SharedSessionPreview(entry: entry)
                        SessionReactionBar(entry:entry)
                    }
                }
            }
            if !shared.isEmpty { Text("Only sessions shared with you appear here, not anyone’s complete journal.").font(.caption).foregroundStyle(.secondary) }
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
    private func refresh() async { if social.configuration != nil && auth.account != nil { await social.refresh(auth) } }
}

struct FriendInitials: View {
    let name: String
    private var initials: String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
    var body: some View {
        Text(initials.isEmpty ? "?" : initials).font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(ClimbTheme.forest).frame(width: 48, height: 48)
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
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                actions.frame(minHeight: 44)
            }.padding(.vertical, 8)
        }
    }
}
