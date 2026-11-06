import Foundation

extension SocialStore {
    func profilePage(_ auth:AccountSession,id:UUID) async throws -> SocialProfilePage {
        try await authorize(auth)
        // One climber by id, connected or not (search, suggestions, invites); the table only lists connected climbers.
        let profiles=try JSONDecoder().decode([SocialProfile].self,from:await request("/rest/v1/rpc/climber_profile",method:"POST",values:["target":id.uuidString]))
        guard let profile=profiles.first else { throw SocialError.server }
        let details=try await profileDetails(auth,id:id)
        let entries=try JSONDecoder().decode([SharedSession].self,from:await request("/rest/v1/shared_sessions?owner_id=eq.\(id.uuidString)&select=*&order=session_day.desc&limit=200"))
        return SocialProfilePage(profile:profile,details:details,entries:entries.filter { !removals.hides($0) })
    }

    func profileDetails(_ auth:AccountSession,id:UUID) async throws -> SocialProfileDetails? {
        try await authorize(auth)
        return try JSONDecoder().decode([SocialProfileDetails].self,from:await request("/rest/v1/climber_profile_details?id=eq.\(id.uuidString)&select=*")).first
    }

    func reactions(_ auth:AccountSession,entry:UUID) async throws -> [ReactionSummary] {
        #if DEBUG
        if SocialAuditSample.enabled { return auditReactions[entry] ?? [] }
        #endif
        try await authorize(auth)
        return try JSONDecoder().decode([ReactionSummary].self,from:await request("/rest/v1/rpc/reaction_summary",method:"POST",values:["entries":[entry.uuidString]]))
    }

    func react(_ auth:AccountSession,entry:UUID,reaction:SessionReaction?) async throws {
        #if DEBUG
        if SocialAuditSample.enabled {
            var rows=(auditReactions[entry] ?? []).compactMap { row -> ReactionSummary? in
                var row=row
                if row.mine { row.mine=false;row.total-=1 }
                return row.total > 0 ? row : nil
            }
            if let reaction {
                if let index=rows.firstIndex(where: { $0.kind == reaction.rawValue }) { rows[index].total+=1;rows[index].mine=true }
                else { rows.append(.init(entry_id:entry,kind:reaction.rawValue,total:1,mine:true)) }
            }
            auditReactions[entry]=rows
            return
        }
        #endif
        try await authorize(auth)
        _ = try await request("/rest/v1/rpc/set_session_reaction",method:"POST",values:["entry":entry.uuidString,"reaction":reaction?.rawValue as Any? ?? NSNull()])
    }

    /// The newest 200 comments, oldest first.
    // shortcut: a post's count stops at 200, upgrade to a server count if posts ever get that many.
    func comments(_ auth:AccountSession,entry:UUID) async throws -> [SessionComment] {
        #if DEBUG
        if SocialAuditSample.enabled { return auditComments[entry] ?? [] }
        #endif
        try await authorize(auth)
        let rows=try SessionComment.decoder.decode([SessionComment].self,from:await request("/rest/v1/session_comments?entry_id=eq.\(entry.uuidString)&select=*,author:climber_profiles(*)&order=created_at.desc,id.desc&limit=200"))
        return rows.reversed()
    }

    func addComment(_ auth:AccountSession,entry:UUID,body:String) async throws -> SessionComment {
        #if DEBUG
        if SocialAuditSample.enabled {
            if ProcessInfo.processInfo.arguments.contains("--test-comment-error") { throw SocialError.server }
            let comment=SessionComment(id:UUID(),entry_id:entry,user_id:SocialAuditSample.me.id,body:body,created_at:.now,author:SocialAuditSample.me)
            auditComments[entry,default:[]].append(comment)
            return comment
        }
        #endif
        try await authorize(auth)
        var comment=try SessionComment.decoder.decode(SessionComment.self,from:await request("/rest/v1/rpc/add_session_comment",method:"POST",values:["entry":entry.uuidString,"message":body]))
        comment.author=me
        return comment
    }

    func deleteComment(_ auth:AccountSession,id:UUID) async throws {
        #if DEBUG
        if SocialAuditSample.enabled { for key in auditComments.keys { auditComments[key]?.removeAll { $0.id == id } };return }
        #endif
        try await authorize(auth)
        _ = try await request("/rest/v1/rpc/delete_session_comment",method:"POST",values:["comment":id.uuidString])
    }
}
