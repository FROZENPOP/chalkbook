import Foundation
import Observation

struct FriendSuggestion: Decodable, Identifiable, Equatable {
    let id: UUID
    let display_name: String
    let avatar_base64: String?
    let mutual_count: Int
    let mutual_names: [String]
    var mutualSummary: String {
        let count = "\(mutual_count) mutual \(mutual_count == 1 ? "friend" : "friends")"
        let names = mutual_names.prefix(3).joined(separator: ", ")
        return names.isEmpty ? count : "\(count) · \(names)"
    }
    static func ranked(_ rows: [Self], excluding: Set<UUID>) -> [Self] {
        var seen = Set<UUID>()
        return rows.filter { !excluding.contains($0.id) && $0.mutual_count > 0 && seen.insert($0.id).inserted }
            .sorted { $0.mutual_count == $1.mutual_count ? $0.id.uuidString < $1.id.uuidString : $0.mutual_count > $1.mutual_count }
    }
}

@MainActor protocol FriendSuggestionServing {
    func fetch(limit: Int, offset: Int) async throws -> [FriendSuggestion]
    func dismiss(_ id: UUID) async throws
    func add(_ id: UUID) async throws
    func discovery() async throws -> Bool
    func setDiscovery(_ enabled: Bool) async throws
}

/// Only server-confirmed changes are presented as saved. This cache is scoped to one account.
@MainActor @Observable final class FriendSuggestions {
    private(set) var items: [FriendSuggestion] = []
    private(set) var sent = Set<UUID>()
    private(set) var working = Set<UUID>()
    private(set) var retryDismiss = Set<UUID>()
    private(set) var rowErrors: [UUID: String] = [:]
    private(set) var errorMessage: String?
    private(set) var loading = false
    private(set) var hasMore = false
    private(set) var discoveryEnabled: Bool?
    private(set) var settingError: String?
    private(set) var savingSetting = false
    private var owner: UUID?
    private var offset = 0
    private var generation = UUID()

    func reset() {
        generation = UUID(); owner = nil; items = []; sent = []; working = []; rowErrors = [:]; retryDismiss = []
        errorMessage = nil; loading = false; hasMore = false; offset = 0
        discoveryEnabled = nil; settingError = nil; savingSetting = false
    }
    func load(_ service: any FriendSuggestionServing, owner: UUID, excluding: Set<UUID> = [], more: Bool = false) async {
        if self.owner != owner { reset(); self.owner = owner }
        guard !loading else { return }
        loading = true
        let token = generation
        defer { if generation == token { loading = false } }
        do {
            let page = try await service.fetch(limit: 10, offset: more ? offset : 0)
            guard generation == token else { return }
            items = FriendSuggestion.ranked((more ? items : []) + page, excluding: excluding.union([owner]))
            offset = (more ? offset : 0) + page.count; hasMore = page.count == 10
            if !more { sent = []; rowErrors = [:] }
            errorMessage = nil
        } catch {
            guard generation == token else { return }
            // Refresh may reflect a revoked block/setting. Never keep stale recommendations.
            items = []; hasMore = false; errorMessage = SocialError.message(for: error)
        }
    }
    func act(_ id: UUID, dismiss: Bool, service: any FriendSuggestionServing) async {
        guard items.contains(where: { $0.id == id }), !working.contains(id), !sent.contains(id) else { return }
        working.insert(id); rowErrors[id] = nil
        let token = generation
        defer { if generation == token { working.remove(id) } }
        do {
            if dismiss { try await service.dismiss(id) } else { try await service.add(id) }
            guard generation == token else { return }
            offset = max(0, offset - 1)
            if dismiss { items.removeAll { $0.id == id } } else { sent.insert(id) }
        } catch {
            guard generation == token else { return }
            if dismiss { retryDismiss.insert(id) } else { retryDismiss.remove(id) }
            rowErrors[id] = (dismiss ? "Couldn’t hide this suggestion. " : "Couldn’t send the request. ") + SocialError.message(for: error)
        }
    }
    func loadDiscovery(_ service: any FriendSuggestionServing) async {
        let token = generation
        do {
            let value = try await service.discovery()
            guard token == generation else { return }
            discoveryEnabled = value; settingError = nil
        } catch { if token == generation { discoveryEnabled = nil; settingError = "Couldn’t load discovery settings. Retry." } }
    }
    func setDiscovery(_ enabled: Bool, service: any FriendSuggestionServing) async {
        guard !savingSetting, discoveryEnabled != nil else { return }
        savingSetting = true
        let token = generation
        defer { if token == generation { savingSetting = false } }
        do {
            try await service.setDiscovery(enabled)
            guard token == generation else { return }
            discoveryEnabled = enabled; settingError = nil
        } catch { if token == generation { settingError = "Couldn’t confirm the discovery setting. Retry to check what’s saved." } }
    }
}

@MainActor struct SocialSuggestionService: FriendSuggestionServing {
    let store: SocialStore
    let auth: AccountSession
    func fetch(limit: Int, offset: Int) async throws -> [FriendSuggestion] {
        try await store.authorize(auth)
        return try JSONDecoder().decode([FriendSuggestion].self, from: await store.request("/rest/v1/rpc/suggested_friends", method:"POST", values:["p_limit":limit,"p_offset":offset]))
    }
    func dismiss(_ id: UUID) async throws {
        try await store.authorize(auth)
        _ = try await store.request("/rest/v1/rpc/dismiss_friend_suggestion",method:"POST",values:["target":id.uuidString])
    }
    func add(_ id: UUID) async throws {
        // The same request RPC as search/profile Add; never accepts on the caller's behalf.
        guard await store.action(auth,target:id,action:"request") else { throw FriendsProblem(message: store.errorMessage ?? SocialError.server.localizedDescription) }
    }
    func discovery() async throws -> Bool {
        try await store.authorize(auth)
        struct Setting: Decodable { let enabled: Bool }
        let rows = try JSONDecoder().decode([Setting].self,from:await store.request("/rest/v1/friend_discovery_settings?select=enabled"))
        return rows.first?.enabled ?? true
    }
    func setDiscovery(_ enabled: Bool) async throws {
        try await store.authorize(auth)
        _ = try await store.request("/rest/v1/rpc/set_friend_discovery",method:"POST",values:["enabled":enabled])
    }
}
