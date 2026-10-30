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
    let feed = FriendsFeed()
    var entries: [SharedSession] { feed.entries }
    private(set) var blocks: [ClimberBlock] = []
    private(set) var busy = false
    let suggestions = FriendSuggestions()
    private(set) var mediaRevision = 0
    var errorMessage: String?
    let configuration: SupabaseConfiguration?
    private var accessToken: String?
    private var expiresAt = Date.distantPast
    private let network: URLSession

    init(configuration: SupabaseConfiguration? = .load(), network: URLSession = URLSession(configuration: .ephemeral)) {
        self.configuration = configuration; self.network = network
    }

    private struct TokenResponse: Decodable {
        struct User: Decodable { let id: UUID }
        let access_token: String
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
            guard let accessToken else { throw SocialError.signIn }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let values { request.httpBody = try JSONSerialization.data(withJSONObject: values) }
        let (data, response) = try await network.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let code = (try? JSONSerialization.jsonObject(with:data) as? [String:Any])?["code"] as? String
            if ["PGRST202","PGRST205","42P01"].contains(code ?? "") { throw SocialError.migrationNeeded }
            throw SocialError.server
        }
        return data
    }

    func authorize(_ auth: AccountSession) async throws {
        guard configuration != nil else { throw SocialError.setup }
        guard auth.account != nil else { throw SocialError.signIn }
        if accessToken != nil && expiresAt > .now { return }
        let token = try await auth.googleIdentityTokenForFriends()
        let data = try await request("/auth/v1/token?grant_type=id_token", method: "POST", values: ["provider": "google", "id_token": token], authenticated: false)
        let session = try JSONDecoder().decode(TokenResponse.self, from: data)
        // Tokens stay in memory. Google’s existing Keychain session supplies a fresh verified identity after relaunch.
        accessToken = session.access_token; userID = session.user.id
        expiresAt = .now.addingTimeInterval(TimeInterval(max(0, session.expires_in - 60)))
    }

    @discardableResult
    func perform(_ auth: AccountSession, operation: () async throws -> Void) async -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false; mediaRevision += 1 }
        do {
            try await authorize(auth)
            try await operation()
            errorMessage = nil
            return true
        } catch {
            accessToken = nil; expiresAt = .distantPast
            feed.reset() // Do not keep showing possibly revoked entries after a failed refresh.
            errorMessage = (error as? SocialError)?.localizedDescription ?? SocialError.server.localizedDescription
            return false
        }
    }

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
        peopleRecords = profiles; friendships = links; me = own.first; blocks = blocked
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
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard username.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) != nil, (1...60).contains(name.count),bio.count<=240,(photo?.count ?? 0)<=65_536 else {
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
        await perform(auth) {
            var values = entry.rpcValues
            if let photos {
                guard photos.count <= 3 else { throw SocialError.server }
                values["photos"] = try photos.map { try $0.validated().rpcValues }
            }
            _ = try await self.request(photos == nil ? "/rest/v1/rpc/save_shared_session" : "/rest/v1/rpc/save_shared_session_with_photos", method: "POST", values: values)
            try await self.reload()
        }
    }

    func routePhotos(_ auth: AccountSession, entryID: UUID) async throws -> [SharedRoutePhoto] {
        try await authorize(auth)
        let data = try await request("/rest/v1/shared_route_photos?entry_id=eq.\(entryID.uuidString)&select=id,entry_id,original_base64,highlighted_base64&order=position&limit=3")
        try Task.checkCancellation()
        let photos = try JSONDecoder().decode([SharedRoutePhoto].self, from:data)
        return try photos.map { try $0.validated() }
    }

    func removeShare(_ auth: AccountSession, sessionID: UUID) async -> Bool {
        await perform(auth) {
            _ = try await self.request("/rest/v1/rpc/remove_shared_session", method: "POST", values: ["source_id": sessionID.uuidString])
            self.feed.remove { $0.owner_id == self.userID && $0.source_session_id == sessionID }
        }
    }

    @discardableResult
    func safetyAction(_ auth: AccountSession, target: UUID, block: Bool, reason: String = "") async -> Bool {
        if block { suggestions.reset() }
        return await perform(auth) {
            _ = try await self.request("/rest/v1/rpc/\(block ? "block_climber" : "report_climber")", method: "POST", values: block ? ["target": target.uuidString] : ["target": target.uuidString, "reason": reason])
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
        suggestions.reset()
        return await perform(auth) {
            _ = try await self.request("/rest/v1/rpc/delete_social_profile", method: "POST", values: [:])
            self.suggestions.reset(); self.me = nil; self.feed.reset(); self.friendships = []; self.peopleRecords = []; self.blocks = []
        }
    }

    func sharedEntry(_ auth: AccountSession, session: ClimbingSession) async -> SharedSession? {
        var result: SharedSession?
        let success = await perform(auth) {
            let rows = try JSONDecoder().decode([SharedSession].self, from: await self.request("/rest/v1/shared_sessions?owner_id=eq.\(self.userID!.uuidString)&source_session_id=eq.\(session.id.uuidString)&select=*"))
            result = rows.first ?? SharedSession(session: session, owner: self.userID!)
        }
        return success ? result : nil
    }
}
