import Foundation

enum EntryVisibility: String, Codable, CaseIterable, Identifiable {
    case `private`, friends, `public`
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct SocialProfile: Codable, Identifiable, Equatable {
    let id: UUID
    let username: String
    let display_name: String
    let is_private: Bool
}

struct SocialProfileDetails: Codable, Equatable {
    var id: UUID
    var bio: String
    var avatar_base64: String?
    var photo: Data? {
        guard let avatar_base64,avatar_base64.utf8.count<=90_000,let data=Data(base64Encoded:avatar_base64),data.count<=65_536 else { return nil }
        return try? SocialPhoto.prepare(data)
    }
}

struct SocialProfilePage {
    var profile: SocialProfile
    var details: SocialProfileDetails?
    var entries: [SharedSession]
}

enum SessionReaction: String, CaseIterable, Identifiable {
    case clap, fire, strong
    var id: String { rawValue }
    var emoji: String { switch self { case .clap: "👏";case .fire:"🔥";case .strong:"💪" } }
    var label: String { switch self { case .clap: "Applause";case .fire:"Fire";case .strong:"Strong" } }
}
struct ReactionSummary: Decodable {
    var entry_id: UUID
    var kind: String
    var total: Int
    var mine: Bool
}

struct Friendship: Codable, Identifiable {
    let requester: UUID
    let recipient: UUID
    let status: String
    var id: String { "\(requester):\(recipient)" }
    func other(than user: UUID) -> UUID { requester == user ? recipient : requester }
}

struct ClimberBlock: Decodable, Identifiable {
    let target_id: UUID
    var id: UUID { target_id }
}

struct SharedSession: Codable, Identifiable {
    var id: UUID
    var owner_id: UUID
    var source_session_id: UUID
    var visibility: EntryVisibility
    var caption: String
    var session_day: String
    var attempts: Int?
    var sends: Int?
    var duration_minutes: Int?
    var completeness: String

    // Explicit allowlist: no local notes, gym, route media, exact times, or Health values.
    @MainActor
    init(session: ClimbingSession, owner: UUID) {
        id = UUID(); owner_id = owner; source_session_id = session.id
        visibility = .private; caption = ""; session_day = session.day
        attempts = session.totals.attempts; sends = session.totals.sends
        duration_minutes = session.durationMinutes; completeness = session.totals.label
    }

    var rpcValues: [String: Any] {
        ["source_session_id": source_session_id.uuidString, "visibility": visibility.rawValue,
         "caption": caption, "session_day": session_day, "attempts": attempts.map { $0 as Any } ?? NSNull(),
         "sends": sends.map { $0 as Any } ?? NSNull(),
         "duration_minutes": duration_minutes.map { $0 as Any } ?? NSNull(), "completeness": completeness]
    }
}

struct SupabaseConfiguration: Decodable {
    let projectURL: URL
    let publishableKey: String
    var inviteWebBaseURL: URL? = nil
    static func load(bundle: Bundle = .main) -> Self? {
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing"),
              let url = bundle.url(forResource: "Supabase.local", withExtension: "json"),
              let data = try? Data(contentsOf: url), let config = try? JSONDecoder().decode(Self.self, from: data),
              config.projectURL.scheme == "https", config.projectURL.host?.hasSuffix(".supabase.co") == true,
              config.publishableKey.hasPrefix("sb_publishable_") else { return nil }
        return config
    }
}

enum SocialError: LocalizedError {
    case setup, signIn, applePending, server, invalidProfile, migrationNeeded
    var errorDescription: String? {
        switch self {
        case .setup: "Friends is waiting for Supabase setup. Your private journal still works offline."
        case .signIn: "Sign in with Google to connect to Friends."
        case .applePending: "Apple account connection will be available after Apple developer setup. Your local journal is available."
        case .server: "The Friends service couldn’t complete this request. Check your connection and retry. No successful save has been confirmed."
        case .invalidProfile: "Choose a username with 3–24 lowercase letters, numbers or underscores, and a name with 1–60 characters."
        case .migrationNeeded: "This Friends update isn’t available yet. Please try again later. Your local journal is unaffected."
        }
    }
}
