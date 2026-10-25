import Foundation

extension SocialStore {
    func profilePage(_ auth:AccountSession,id:UUID) async throws -> SocialProfilePage {
        try await authorize(auth)
        let profiles=try JSONDecoder().decode([SocialProfile].self,from:await request("/rest/v1/climber_profiles?id=eq.\(id.uuidString)&select=*"))
        guard let profile=profiles.first else { throw SocialError.server }
        let details=try await profileDetails(auth,id:id)
        let entries=try JSONDecoder().decode([SharedSession].self,from:await request("/rest/v1/shared_sessions?owner_id=eq.\(id.uuidString)&select=*&order=session_day.desc&limit=200"))
        return SocialProfilePage(profile:profile,details:details,entries:entries)
    }

    func profileDetails(_ auth:AccountSession,id:UUID) async throws -> SocialProfileDetails? {
        try await authorize(auth)
        return try JSONDecoder().decode([SocialProfileDetails].self,from:await request("/rest/v1/climber_profile_details?id=eq.\(id.uuidString)&select=*")).first
    }

    func reactions(_ auth:AccountSession,entry:UUID) async throws -> [ReactionSummary] {
        try await authorize(auth)
        return try JSONDecoder().decode([ReactionSummary].self,from:await request("/rest/v1/rpc/reaction_summary",method:"POST",values:["entries":[entry.uuidString]]))
    }

    func react(_ auth:AccountSession,entry:UUID,reaction:SessionReaction?) async throws {
        try await authorize(auth)
        _ = try await request("/rest/v1/rpc/set_session_reaction",method:"POST",values:["entry":entry.uuidString,"reaction":reaction?.rawValue as Any? ?? NSNull()])
    }
}
