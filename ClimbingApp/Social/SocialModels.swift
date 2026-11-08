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

struct SessionComment: Decodable, Identifiable, Equatable {
    let id: UUID
    let entry_id: UUID
    let user_id: UUID
    let body: String
    let created_at: Date
    var author: SocialProfile?
    static var decoder: JSONDecoder { let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601;return decoder }
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
    var route_photo_count: Int? = nil

    // Explicit allowlist: no local notes, gym, route media, exact times, or Health values.
    @MainActor
    init(session: ClimbingSession, owner: UUID) {
        id = UUID(); owner_id = owner; source_session_id = session.id
        visibility = .private; caption = ""; session_day = session.day
        // Leave out values the server would reject, so an unusual session still shares.
        let totals = session.totals
        let shownAttempts = totals.attempts.flatMap { $0 <= 100_000 ? $0 : nil }
        attempts = shownAttempts
        sends = totals.sends.flatMap { $0 <= 100_000 && $0 <= (shownAttempts ?? .max) ? $0 : nil }
        duration_minutes = session.durationMinutes.flatMap { $0 <= 10_080 ? $0 : nil }; completeness = totals.label
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
    case setup, signIn, appleSignIn, server, migrationNeeded, contentRejected, usernameTaken
    case removalPending, tooManyPhotos, photoUnreadable, climberUnavailable, feedPage
    var errorDescription: String? {
        switch self {
        case .setup: "Friends is waiting for Supabase setup. Your private journal still works offline."
        case .signIn: "Sign in to connect to Friends."
        case .appleSignIn: "Continue with Apple to connect to Friends. Your journal is unaffected."
        case .server: "The Friends service couldn’t complete this request. Check your connection and retry. No successful save has been confirmed."
        case .migrationNeeded: "This Friends update isn’t available yet. Please try again later. Your local journal is unaffected."
        case .contentRejected: "This includes words the community rules don’t allow. Edit it and try again."
        case .usernameTaken: "That username is taken. Try another one."
        case .removalPending: "This entry is waiting to be removed. Retry removals before publishing it again."
        case .tooManyPhotos: "Choose up to 3 photos and try again."
        case .photoUnreadable: "This photo couldn’t be prepared for sharing. Choose another photo."
        case .climberUnavailable: "This climber is no longer available."
        case .feedPage: "More posts couldn’t load. Pull down to refresh the feed."
        }
    }

    /// The most specific message for any Friends failure: connection, server answer or the server's own reason.
    static func message(for error: Error) -> String {
        switch error {
        case let error as SocialError: return error.localizedDescription
        case let error as RemovalHTTPError: return error.errorDescription ?? SocialError.server.localizedDescription
        case let error as FriendsProblem: return error.message
        case let error as URLError:
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return "You’re offline. Connect to the internet and try again."
            case .timedOut: return "Friends took too long to respond. Check your connection and try again."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed:
                return "Chalkbook couldn’t reach the Friends service. Try again in a few minutes."
            default: break
            }
        case is DecodingError: return "Friends sent a reply this version of Chalkbook can’t read. Update the app and try again."
        default: break
        }
        return SocialError.server.localizedDescription
    }
}

/// The Friends profile rules the server enforces (supabase/migrations), checked first so the climber sees why.
enum ProfileInput {
    static let reserved: Set<String> = ["admin", "administrator", "moderator", "mod", "support", "help", "official", "staff", "team", "security", "apple"]

    /// Controls, zero-width and text-direction characters, which can hide or reverse text other climbers read.
    /// U+200C and U+200D are allowed: emoji like 🧗‍♀️ and Persian and Indic text need them.
    static func hasHiddenCharacters(_ text: String, allowLineBreaks: Bool = false) -> Bool {
        text.unicodeScalars.contains { scalar in
            if allowLineBreaks && ["\t", "\n", "\r"].contains(scalar) { return false }
            switch scalar.value {
            case 0x00...0x1F, 0x7F...0x9F, 0x200B, 0x200E, 0x200F, 0x202A...0x202E, 0x2060, 0x2066...0x2069, 0xFEFF: return true
            default: return false
            }
        }
    }

    /// The first problem the server would refuse, or nil.
    static func problem(username: String, name: String, bio: String) -> String? {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if username.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) == nil { return "Usernames are 3–24 lowercase letters, numbers or underscores." }
        if reserved.contains(username) || username.contains("chalkbook") { return "That username is reserved. Choose another one." }
        if !(1...60).contains(name.unicodeScalars.count) { return "Enter a display name of 1–60 characters." }
        if hasHiddenCharacters(name) { return "Your display name has hidden or formatting characters. Retype it without them." }
        if name.localizedCaseInsensitiveContains("chalkbook") { return "Display names can’t include “Chalkbook”." }
        if bio.unicodeScalars.count > 240 { return "Keep your bio to 240 characters or fewer." }
        if hasHiddenCharacters(bio, allowLineBreaks: true) { return "Your bio has hidden or formatting characters. Retype it without them." }
        return nil
    }
}

/// A failure whose message was already worked out, passed on unchanged.
struct FriendsProblem: Error { let message: String }
