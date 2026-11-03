import SwiftUI

struct AddFriendsView: View {
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var search = FriendSearch()
    @State private var retry = 0
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !focused && query.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Find your people.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("Cheer on their sends. Share yours.").font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
                    }
                }
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(ClimbTheme.accent).accessibilityHidden(true)
                    TextField("Name or @username", text: $query, axis: .vertical).lineLimit(1...3)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                        .accessibilityLabel("Search by name or username").submitLabel(.search).focused($focused).accessibilityIdentifier("friendSearchField")
                        .onSubmit { focused = false }
                        .onChange(of: query) { _, value in
                            if value.contains(where: \.isNewline) {
                                query = value.filter { !$0.isNewline }; focused = false
                            }
                        }
                    if !query.isEmpty {
                        Button { query = ""; focused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(ClimbTheme.secondaryText).frame(width: 44, height: 44) }
                            .accessibilityLabel("Clear search").accessibilityIdentifier("clearFriendSearch")
                    }
                }
                .padding(.leading, 16).padding(.trailing, query.isEmpty ? 16 : 4).frame(minHeight: 56)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(focused ? ClimbTheme.accent : Color.secondary.opacity(0.2), lineWidth: focused ? 2 : 1) }

                results

                if query.isEmpty, let me = social.me {
                    Surface {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Or let them find you").font(.headline)
                            HStack {
                                Text("@\(me.username)").font(.system(.title3, design: .rounded, weight: .semibold)).textSelection(.enabled)
                                Spacer()
                NavigationLink { FriendInviteView(profile:me) } label: { Image(systemName:"qrcode").frame(width:44,height:44) }.accessibilityLabel("Your friend QR code and invite link")
                            }
                        }
                    }
                }
            }.padding(20)
        }
        .background(ClimbTheme.background).scrollDismissesKeyboard(.interactively)
        .navigationTitle("Add friends").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() }.accessibleToolbarAction() } }
        .task(id: "\(query)|\(retry)") { await search.search(query) { try await social.searchProfiles(auth, query: $0) } }
    }

    @ViewBuilder private var results: some View {
        switch search.state {
        case .idle:
            Label(query.isEmpty ? "Search a name or username to find a friend." : "Type at least two characters of their name or username.", systemImage: "at")
                .font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
        case .loading:
            SwiftUI.ProgressView("Finding climbers…").frame(maxWidth: .infinity, minHeight: 100)
        case .failed:
            FriendsEmptyCard(symbol: "wifi.exclamationmark", title: "Search couldn’t connect.", message: search.errorMessage ?? "Your search is kept. Check your connection and try again.") {
                Button("Try again") { retry += 1 }.buttonStyle(.bordered)
            }
        case .results:
            if search.results.isEmpty {
                FriendsEmptyCard(symbol: "magnifyingglass", title: "No climbers found.", message: "Check their name or username. Your friend may still need to set up their profile.") { EmptyView() }
            } else {
                Text("CLIMBERS").font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(ClimbTheme.secondaryText)
                ForEach(search.results.filter { person in !social.blocks.contains { $0.target_id == person.id } }) { person in FriendPersonRow(person: person, personID: person.id) }
                if search.results.count == 30 { Text("Showing the first 30 matches. Type more of their username to narrow it down.").font(.caption).foregroundStyle(ClimbTheme.secondaryText) }
            }
        }
    }
}

struct FriendPersonRow: View {
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    @Environment(\.dynamicTypeSize) private var typeSize
    let person: SocialProfile?
    let personID: UUID
    var showsProfileLink = true
    @State private var working = false
    @State private var failed = false
    private var link: Friendship? { social.friendships.first { $0.requester == personID || $0.recipient == personID } }

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    SocialAvatar(id:personID,name:person?.display_name ?? "Climber")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person?.display_name ?? "Climber").font(.headline)
                        if let person { Text("@\(person.username)").font(.subheadline).foregroundStyle(ClimbTheme.secondaryText) }
                    }
                    Spacer(minLength: 0)
                    if showsProfileLink { NavigationLink { SocialClimberProfileView(climberID:personID) } label: { Image(systemName:"person.crop.circle").frame(width:44,height:44) }.accessibilityLabel("View profile") }
                    Menu {
                        if link?.status == "accepted" { Button("Remove friend", role: .destructive) { act("remove") } }
                        if link?.status == "pending" && link?.requester == social.userID { Button("Cancel request") { act("cancel") } }
                        Button("Block climber", role: .destructive) { Task { await social.safetyAction(auth, target: personID, block: true) } }
                        NavigationLink("Report climber") { ReportClimberView(target: personID) }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Options for \(person?.display_name ?? "climber")")
                }
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
                layout {
                    if let link {
                        if link.status == "accepted" {
                            Label("Friends", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(ClimbTheme.accent)
                            Spacer(minLength: 0)
                            NavigationLink("View progress") { FriendProgressView(climberID: personID, name: person?.display_name ?? "Climber") }.buttonStyle(.bordered).frame(minHeight: 44)
                        } else if link.recipient == social.userID {
                            Button("Accept") { act("accept") }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                            Button("Decline") { act("decline") }.buttonStyle(.bordered).tint(.primary).frame(minHeight: 44)
                        } else {
                            Label("Request sent", systemImage: "clock").font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
                        }
                    } else {
                        Button { act("request") } label: { Label("Add friend", systemImage: "plus").frame(minHeight: 44) }.buttonStyle(.borderedProminent)
                    }
                    if working { SwiftUI.ProgressView().accessibilityLabel("Updating request") }
                }.disabled(social.busy || working)
                if failed { Text("Couldn’t update this request. Please try again.").font(.caption).foregroundStyle(ClimbTheme.error) }
            }
        }
    }

    private func act(_ action: String) {
        working = true; failed = false
        Task {
            await social.action(auth, target: personID, action: action)
            working = false; failed = social.errorMessage != nil
        }
    }
}
