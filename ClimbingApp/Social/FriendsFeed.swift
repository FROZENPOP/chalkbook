import Foundation
import Observation

/// Preserve the feed's session-date ordering, with a deterministic UUID tiebreaker.
/// A refresh reconciles corrected dates; inserts above the cursor never shift later pages.
struct FriendsFeedCursor: Equatable {
    let day: String
    let id: UUID
    static func path(viewer: UUID, after: Self?, limit: Int = 20) throws -> String {
        var query = [URLQueryItem(name:"select",value:"*"),
                     URLQueryItem(name:"owner_id",value:"neq.\(viewer.uuidString)"),
                     URLQueryItem(name:"order",value:"session_day.desc,id.desc"),
                     URLQueryItem(name:"limit",value:String(min(20,max(1,limit))))]
        if let after {
            guard after.day.utf8.count == 10, after.day.range(of:"^[0-9]{4}-[0-9]{2}-[0-9]{2}$",options:.regularExpression) != nil else { throw SocialError.server }
            query.append(URLQueryItem(name:"or",value:"(session_day.lt.\(after.day),and(session_day.eq.\(after.day),id.lt.\(after.id.uuidString)))"))
        }
        var parts = URLComponents(); parts.path = "/rest/v1/shared_sessions"; parts.queryItems = query
        guard let path = parts.string else { throw SocialError.server }
        return path
    }
}

struct FriendsFeedPage {
    var entries: [SharedSession]
    var profiles: [SocialProfile] = []
}

@MainActor protocol FriendsFeedReading {
    func page(after: FriendsFeedCursor?, limit: Int) async throws -> FriendsFeedPage
}

@MainActor @Observable final class FriendsFeed {
    static let pageSize = 20
    private(set) var entries: [SharedSession] = []
    private(set) var profiles: [SocialProfile] = []
    private(set) var cursor: FriendsFeedCursor?
    private(set) var loading = false
    private(set) var hasLoaded = false
    private(set) var hasMore = true
    private(set) var errorMessage: String?
    private var generation = UUID()

    func reset() {
        generation = UUID(); entries = []; profiles = []; cursor = nil
        loading = false; hasLoaded = false; hasMore = true; errorMessage = nil
    }
    func refresh(_ reader: any FriendsFeedReading) async {
        reset(); await loadNext(reader)
    }
    func loadNext(_ reader: any FriendsFeedReading) async {
        guard !loading, hasMore else { return }
        loading = true; errorMessage = nil
        let token = generation
        defer { if generation == token { loading = false } }
        do {
            let page = try await reader.page(after:cursor,limit:Self.pageSize)
            guard generation == token else { return }
            var merged = Dictionary(entries.map { ($0.id,$0) },uniquingKeysWith:{ _,new in new })
            for entry in page.entries { merged[entry.id] = entry }
            entries = merged.values.sorted {
                $0.session_day == $1.session_day ? $0.id.uuidString > $1.id.uuidString : $0.session_day > $1.session_day
            }
            // Advance from the raw response, not the de-duplicated cache or locally removed rows.
            if let last = page.entries.last { cursor = .init(day:last.session_day,id:last.id) }
            let owners = Set(entries.map(\.owner_id))
            var people = Dictionary(profiles.map { ($0.id,$0) },uniquingKeysWith:{ _,new in new })
            for profile in page.profiles where owners.contains(profile.id) { people[profile.id] = profile }
            profiles = people.values.filter { owners.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString }
            hasLoaded = true; hasMore = page.entries.count == Self.pageSize
        } catch {
            guard generation == token else { return }
            // Later-page errors keep every previously loaded row and the last confirmed cursor.
            errorMessage = "Couldn’t load activity. Check your connection and retry."
        }
    }
    func remove(where predicate: (SharedSession) -> Bool) {
        entries.removeAll(where:predicate)
        let owners = Set(entries.map(\.owner_id)); profiles.removeAll { !owners.contains($0.id) }
    }
}

@MainActor struct SocialFeedReader: FriendsFeedReading {
    let store: SocialStore
    var auth: AccountSession? = nil
    func page(after: FriendsFeedCursor?, limit: Int) async throws -> FriendsFeedPage {
        if let auth { try await store.authorize(auth) }
        guard let viewer = store.userID else { throw SocialError.signIn }
        let rows = try JSONDecoder().decode([SharedSession].self,from:await store.request(FriendsFeedCursor.path(viewer:viewer,after:after,limit:limit)))
        let ids = Set(rows.map(\.owner_id)).subtracting(store.people.map(\.id)).sorted { $0.uuidString < $1.uuidString }
        var profiles: [SocialProfile] = []
        for start in stride(from:0,to:ids.count,by:50) {
            let batch = ids[start..<min(start+50,ids.count)].map(\.uuidString).joined(separator:",")
            profiles += try JSONDecoder().decode([SocialProfile].self,from:await store.request("/rest/v1/climber_profiles?id=in.(\(batch))&select=*"))
        }
        return .init(entries:rows,profiles:profiles)
    }
}
