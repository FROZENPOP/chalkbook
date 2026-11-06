import Foundation
import Observation

/// The database enforces all audiences. This client never uses a service-role key.
@MainActor @Observable
final class SocialStore {
    private(set) var userID: UUID?
    private(set) var me: SocialProfile?
    private var peopleRecords: [SocialProfile] = []
    var people: [SocialProfile] { peopleRecords + feed.profiles.filter { profile in !peopleRecords.contains { $0.id == profile.id } } }
    private(set) var friendships: [Friendship] = []
    let feed: FriendsFeed
    let removals: RemovalOutbox
    var entries: [SharedSession] { feed.entries }
    private(set) var blocks: [ClimberBlock] = []
    private(set) var busy = false
    let suggestions = FriendSuggestions()
    private(set) var mediaRevision = 0
    var errorMessage: String?
    /// Set after a photo post when Friends photo storage was full; the share screen shows it once.
    var photoNotice: String?
    /// Set when an Apple account has no saved Friends session and Apple must confirm the account again.
    private(set) var needsAppleSignIn = false
    let configuration: SupabaseConfiguration?
    private var accessToken: String?
    private var expiresAt = Date.distantPast
    private let network: URLSession
    private let accountKey: String
    private let identityToken: (AccountSession) async throws -> String
    private let sessions: FriendsSessionVault
    private weak var authorizedSession: AccountSession?
    private var retryScheduled = false

    init(configuration: SupabaseConfiguration? = .load(), network: URLSession = URLSession(configuration: .ephemeral),
         accountKey: String = "guest", removals: RemovalOutbox? = nil, sessions: FriendsSessionVault = .init(),
         identityToken: @escaping (AccountSession) async throws -> String = { try await $0.identityTokenForFriends() }) {
        self.configuration = configuration; self.network = network; self.accountKey = accountKey; self.identityToken = identityToken
        self.sessions = sessions
        let outbox = removals ?? RemovalOutbox(accountKey: accountKey)
        self.removals = outbox
        self.feed = FriendsFeed(isHidden: { outbox.hides($0) })
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--test-stale-photo-notice") { photoNotice = "Stale notice from an earlier share" }
        #endif
    }

    private struct TokenResponse: Decodable {
        struct User: Decodable { let id: UUID }
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
        let user: User
    }

    func request(_ path: String, method: String = "GET", values: [String: Any]? = nil, authenticated: Bool = true) async throws -> Data {
        guard let configuration else { throw SocialError.setup }
        guard let url = URL(string: path, relativeTo: configuration.projectURL) else { throw SocialError.setup }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.httpMethod = method
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if authenticated {
            guard let accessToken, authorizedSession?.account?.storageKey == accountKey else { throw SocialError.signIn }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let values { request.httpBody = try JSONSerialization.data(withJSONObject: values) }
        let (data, response) = try await network.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let code = (try? JSONSerialization.jsonObject(with:data) as? [String:Any])?["code"] as? String
            if ["PGRST202","PGRST205","42P01"].contains(code ?? "") { throw SocialError.migrationNeeded }
            if code == "SN001" { throw SocialError.contentRejected }
            throw RemovalHTTPError(status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                                   missingContent: (response as? HTTPURLResponse)?.statusCode == 410 ||
                                   ((response as? HTTPURLResponse)?.statusCode == 404 && code == "PGRST116"))
        }
        if authenticated { scheduleRemovals() }
        return data
    }

    func authorize(_ auth: AccountSession) async throws {
        guard configuration != nil else { throw SocialError.setup }
        guard let current = auth.account, current.storageKey == accountKey else { throw SocialError.signIn }
        authorizedSession = auth
        if accessToken != nil && expiresAt > .now { scheduleRemovals(); return }
        var data: Data?
        if let refresh = sessions.load(current.storageKey) {
            do { data = try await request("/auth/v1/token?grant_type=refresh_token", method: "POST", values: ["refresh_token": refresh], authenticated: false) }
            catch let rejected as RemovalHTTPError where (400..<500).contains(rejected.status) { sessions.clear(current.storageKey) }
        }
        if data == nil {
            let token = try await identityToken(auth)
            data = try await request("/auth/v1/token?grant_type=id_token", method: "POST",
                                     values: ["provider": current.provider.rawValue, "id_token": token], authenticated: false)
        }
        let session = try JSONDecoder().decode(TokenResponse.self, from: data ?? Data())
        guard auth.account == current else { throw SocialError.signIn }
        try removals.bind(owner: session.user.id, accountKey: current.storageKey)
        // Supabase rotates refresh tokens, so each new one replaces the last.
        if let refresh = session.refresh_token { sessions.save(refresh, for: current.storageKey) }
        accessToken = session.access_token; userID = session.user.id
        expiresAt = .now.addingTimeInterval(TimeInterval(max(0, session.expires_in - 60)))
        scheduleRemovals()
    }

    @discardableResult
    func perform(_ auth: AccountSession, operation: () async throws -> Void) async -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false; mediaRevision += 1; scheduleRemovals(auth) }
        do {
            try await authorize(auth)
            try await operation()
            errorMessage = nil; needsAppleSignIn = false
            return true
        } catch {
            accessToken = nil; expiresAt = .distantPast
            feed.reset() // Do not keep showing possibly revoked entries after a failed refresh.
            errorMessage = (error as? SocialError)?.localizedDescription ?? SocialError.server.localizedDescription
            needsAppleSignIn = error as? SocialError == .appleSignIn
            return false
        }
    }

    #if DEBUG
    var auditReactions: [UUID: [ReactionSummary]] = [:]
    var auditComments: [UUID: [SessionComment]] = [:]
    func loadAuditSample() {
        guard me == nil else { return } // Friends reloads on every return; keep comments added during the run.
        userID = SocialAuditSample.me.id; me = SocialAuditSample.me
        peopleRecords = SocialAuditSample.people; friendships = SocialAuditSample.friendships
        auditReactions = SocialAuditSample.reactions(); auditComments = SocialAuditSample.comments()
    }
    #endif

    private func reload() async throws {
        // Invalidate pending pages before refreshing relationships/visibility.
        feed.reset()
        let links = try JSONDecoder().decode([Friendship].self, from: await request("/rest/v1/friendships?select=*"))
        // Always retrieve own profile even if it falls outside the discovery page.
        let own = try JSONDecoder().decode([SocialProfile].self, from: await request("/rest/v1/climber_profiles?id=eq.\(userID!.uuidString)&select=*"))
        let blocked = try JSONDecoder().decode([ClimberBlock].self, from: await request("/rest/v1/climber_blocks?select=target_id"))
        let ids = Set(links.flatMap { [$0.requester, $0.recipient] }).sorted { $0.uuidString < $1.uuidString }
        var profiles = own
        // Fetch people actually referenced in the feed/requests. Discovery uses a separate server search.
        for start in stride(from: 0, to: ids.count, by: 50) {
            let batch = ids[start..<min(start + 50, ids.count)].map(\.uuidString).joined(separator: ",")
            let rows = try JSONDecoder().decode([SocialProfile].self, from: await request("/rest/v1/climber_profiles?id=in.(\(batch))&select=*"))
            profiles += rows.filter { row in !profiles.contains { $0.id == row.id } }
        }
        if Set(friendships.filter { $0.status == "accepted" }.map(\.id)) != Set(links.filter { $0.status == "accepted" }.map(\.id)) || Set(blocks.map(\.id)) != Set(blocked.map(\.id)) {
            suggestions.reset() // Mutual-name evidence may have changed; discard stale recommendations.
        }
        peopleRecords = profiles; friendships = removals.removingProfile ? [] : links; me = removals.removingProfile ? nil : own.first; blocks = blocked
        // First and subsequent pages use the same RLS-protected reader. No offset or privileged RPC.
        await feed.loadNext(SocialFeedReader(store:self))
    }

    func refresh(_ auth: AccountSession) async { await perform(auth) { try await self.reload() } }

    func loadNextFeed(_ auth: AccountSession) async {
        guard !busy, configuration != nil, auth.account != nil else { return }
        await feed.loadNext(SocialFeedReader(store:self,auth:auth))
    }

    func searchProfiles(_ auth: AccountSession, query: FriendSearchQuery) async throws -> [SocialProfile] {
        try await authorize(auth)
        try Task.checkCancellation()
        let profiles = try JSONDecoder().decode([SocialProfile].self, from: await request(query.path,method:"POST",values:query.rpcValues))
        return profiles.filter { $0.id != userID }
    }

    func saveProfile(_ auth: AccountSession, username: String, name: String, isPrivate: Bool, bio: String = "", photo: Data? = nil) async -> Bool {
        guard !removals.removingProfile else { errorMessage = "Your profile removal is waiting to sync. Retry removals before creating another profile."; return false }
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard username.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) != nil, (1...60).contains(name.unicodeScalars.count),bio.unicodeScalars.count<=240,(photo?.count ?? 0)<=65_536 else {
            errorMessage = SocialError.invalidProfile.localizedDescription; return false
        }
        return await perform(auth) {
            _ = try await self.request("/rest/v1/rpc/save_social_profile_v2", method: "POST", values: ["username": username, "display_name": name, "is_private": isPrivate,"bio":bio,"avatar_base64":photo?.base64EncodedString() as Any? ?? NSNull()])
            try await self.reload()
        }
    }

    @discardableResult
    func action(_ auth: AccountSession, target: UUID, action: String) async -> Bool {
        await perform(auth) {
            _ = try await self.request("/rest/v1/rpc/friend_action", method: "POST", values: ["target": target.uuidString, "action": action])
            try await self.reload()
        }
    }

    func publish(_ auth: AccountSession, entry: SharedSession, photos: [SharedRoutePhoto]? = nil) async -> Bool {
        guard !removals.contains(sessionID: entry.source_session_id) else {
            errorMessage = "This entry is waiting to be removed. Retry removals before publishing it again."
            return false
        }
        var stored = false
        let refreshed = await perform(auth) {
            guard !self.removals.contains(sessionID: entry.source_session_id) else { throw SocialError.server }
            var values = entry.rpcValues
            if let photos {
                guard photos.count <= 3 else { throw SocialError.server }
                values["photos"] = try photos.map { try $0.validated().rpcValues }
            }
            let saved = try await self.request(photos == nil ? "/rest/v1/rpc/save_shared_session" : "/rest/v1/rpc/save_shared_session_with_photos", method: "POST", values: values)
            if photos != nil { self.photoNotice = Self.photoNotice(saved) }
            stored = true
            try await self.reload()
        }
        // perform already reset the feed and token, so the next load fetches everything again.
        if stored && !refreshed {
            let refresh = "Your post was saved, but Friends couldn’t refresh. Check your connection and pull to refresh."
            photoNotice = photoNotice.map { "\($0) \(refresh)" } ?? refresh
            errorMessage = nil // perform's message says nothing was saved, which is false here.
        }
        return stored
    }

    /// The server reports how a photo post fit in Friends photo storage.
    nonisolated static func photoNotice(_ response: Data) -> String? {
        switch try? JSONDecoder().decode(String.self, from: response) {
        case "trimmed": "Friends photo storage is full, so photos were removed from your older Friends posts to make room. They’re still saved in your log on this iPhone."
        case "no_space": "Friends photo storage is full, so this post was shared without photos. Your photos are still saved in your log on this iPhone."
        default: nil
        }
    }

    func routePhotos(_ auth: AccountSession, entryID: UUID, limit: Int = 3) async throws -> [SharedRoutePhoto] {
        #if DEBUG
        if SocialAuditSample.enabled { return Array(SocialAuditSample.photos(for: entryID).prefix(limit)) }
        #endif
        try await authorize(auth)
        let data = try await request("/rest/v1/shared_route_photos?entry_id=eq.\(entryID.uuidString)&select=id,entry_id,original_base64,highlighted_base64&order=position&limit=\(limit)")
        try Task.checkCancellation()
        let photos = try JSONDecoder().decode([SharedRoutePhoto].self, from:data)
        return try photos.map { try $0.validated() }
    }

    /// A true result means the intent is safely saved locally, not that friends have lost access yet.
    func removeShare(_ auth: AccountSession, sessionID: UUID) async -> Bool {
        guard queueRemoval(auth, contentID: sessionID, kind: .sessionSnapshot) else { return false }
        scheduleRemovals(auth)
        return true
    }

    func deleteSession(_ session: ClimbingSession, store: ClimbingStore, auth: AccountSession) -> Bool {
        if configuration != nil, auth.account != nil {
            guard queueRemoval(auth, contentID: session.id, kind: .sessionSnapshot) else {
                store.errorMessage = errorMessage; return false
            }
        }
        let deleted = store.delete(session)
        if deleted { scheduleRemovals(auth) }
        return deleted
    }

    private func queueRemoval(_ auth: AccountSession, contentID: UUID, kind: PendingRemoval.Kind) -> Bool {
        guard configuration != nil, auth.account?.storageKey == accountKey, removals.accountKey == accountKey, accountKey != "guest" else {
            errorMessage = SocialError.signIn.localizedDescription; return false
        }
        do {
            if removals.storageError != nil { removals.reload() }
            try removals.enqueue(contentID: contentID, kind: kind)
            feed.remove { removals.hides($0) }; mediaRevision += 1; errorMessage = nil
            return true
        } catch {
            errorMessage = removals.storageError ?? "The removal couldn’t be saved. Your local data was kept."
            return false
        }
    }

    /// Called by app launch/foreground, verified sign-in, and successful authenticated requests.
    private func scheduleRemovals(_ auth: AccountSession? = nil) {
        guard !retryScheduled, !removals.entries.isEmpty, let auth = auth ?? authorizedSession,
              auth.account?.storageKey == accountKey else { return }
        retryScheduled = true
        Task { [weak self, weak auth] in
            guard let self else { return }
            defer { self.retryScheduled = false }
            if let auth { await self.retryRemovals(auth) }
        }
    }

    func retryRemovals(_ auth: AccountSession, force: Bool = false) async {
        // A pending publish/profile save finishes before the removal RPC, so late saves cannot resurrect content.
        guard !busy, configuration != nil, auth.account?.storageKey == accountKey, !removals.draining else { return }
        if force {
            removals.reload()
            // A previous 401 may have left an expired/revoked token cached in this process.
            accessToken = nil; expiresAt = .distantPast
        }
        guard !removals.entries.isEmpty, removals.storageError == nil, removals.hasDue(force: force) else { return }
        do {
            try await authorize(auth)
            await removals.retry(owner: userID, accountKey: auth.account?.storageKey, force: force) { removal in
                // Check identity again immediately before each request; never reuse another account's token.
                guard auth.account?.storageKey == self.accountKey, self.userID == removal.ownerID else { throw SocialError.signIn }
                let path = removal.kind == .socialProfile ? "delete_social_profile" : "remove_shared_session"
                _ = try await self.request("/rest/v1/rpc/\(path)", method: "POST",
                    values: removal.kind == .socialProfile ? [:] : ["source_id": removal.contentID.uuidString])
            }
            mediaRevision += 1
        } catch {
            // Authorization/network failures also get durable backoff, even before an RPC could start.
            removals.connectionFailed(accountKey: auth.account?.storageKey, error: error)
        }
    }

    @discardableResult
    func safetyAction(_ auth: AccountSession, target: UUID, block: Bool, reason: String = "", comment: UUID? = nil, entry: UUID? = nil) async -> Bool {
        if block { suggestions.reset() }
        return await perform(auth) {
            var values = block ? ["target": target.uuidString] : ["target": target.uuidString, "reason": reason]
            if let comment { values["comment"] = comment.uuidString }
            if let entry { values["entry"] = entry.uuidString }
            _ = try await self.request("/rest/v1/rpc/\(block ? "block_climber" : "report_climber")", method: "POST", values: values)
            // The report is already saved, so a failed ping to the moderator must not fail it.
            if !block { _ = try? await self.request("/functions/v1/report-alert", method: "POST", values: [:]) }
            try await self.reload()
        }
    }

    func unblock(_ auth: AccountSession, target: UUID) async {
        await perform(auth) {
            _ = try await self.request("/rest/v1/rpc/unblock_climber", method: "POST", values: ["target": target.uuidString])
            try await self.reload()
        }
    }

    func deleteProfile(_ auth: AccountSession) async -> Bool {
        guard queueRemoval(auth, contentID: removals.ownerID ?? UUID(), kind: .socialProfile) else { return false }
        suggestions.reset(); me = nil; feed.reset(); friendships = []; peopleRecords = []; blocks = []
        scheduleRemovals(auth)
        return true
    }

    /// Deletes the server account, which cascades to everything social, then signs out.
    func deleteAccount(_ auth: AccountSession) async -> Bool {
        var appleGrantRemains = false
        if configuration != nil {
            let isApple = auth.account?.provider == .apple
            let appleCode = auth.takeAppleAuthorizationCode()
            var revoked = false
            guard await perform(auth, operation: {
                // Apple requires this, but a failure must never keep someone's data on the server.
                if let appleCode { revoked = (try? await self.request("/functions/v1/revoke-apple", method: "POST", values: ["authorization_code": appleCode])) != nil }
                _ = try await self.request("/rest/v1/rpc/delete_account", method: "POST", values: [:])
            }) else { return false }
            removals.clearAfterAccountDeletion()
            appleGrantRemains = isApple && !revoked
        }
        suggestions.reset(); me = nil; feed.reset(); friendships = []; peopleRecords = []; blocks = []
        auth.signOut()
        if appleGrantRemains { auth.errorMessage = "Your account is deleted. To remove Chalkbook from your Apple Account too, go to iPhone Settings > your name > Sign-In & Security > Sign in with Apple." }
        return auth.account == nil
    }

    func sharedEntry(_ auth: AccountSession, session: ClimbingSession) async -> SharedSession? {
        guard !removals.contains(sessionID: session.id) else { return nil }
        var result: SharedSession?
        let success = await perform(auth) {
            let rows = try JSONDecoder().decode([SharedSession].self, from: await self.request("/rest/v1/shared_sessions?owner_id=eq.\(self.userID!.uuidString)&source_session_id=eq.\(session.id.uuidString)&select=*"))
            result = rows.first ?? SharedSession(session: session, owner: self.userID!)
        }
        return success ? result : nil
    }
}
