#if DEBUG
import UIKit

/// Local sample people, requests, posts, reactions and comments for the real Friends screens.
/// Requires the audit launch arguments or the screenshot demo; never contacts the backend.
@MainActor enum SocialAuditSample {
    static var enabled: Bool { (AccessibilityAuditFixtures.audit && ProcessInfo.processInfo.arguments.contains("--audit-social-sample")) || ScreenshotDemo.enabled }
    private static func id(_ number: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))! }
    static let me = SocialProfile(id: id(1), username: "you", display_name: "You", is_private: true)
    private static let alex = SocialProfile(id: id(2), username: "alex_climbs", display_name: "Alex Rivera", is_private: true)
    private static let sam = SocialProfile(id: id(3), username: "sam_sends", display_name: "Sam Okafor", is_private: false)
    private static let jordan = SocialProfile(id: id(4), username: "jordan_lee", display_name: "Jordan Lee", is_private: true)
    private static let priya = SocialProfile(id: id(5), username: "priya_v", display_name: "Priya Varma", is_private: true)
    private static let theo = SocialProfile(id: id(6), username: "theo_on_slab", display_name: "Theo Marsh", is_private: true)
    private static let noor = SocialProfile(id: id(7), username: "noor_crimps", display_name: "Noor Haddad", is_private: false)
    static let people = [me, alex, sam, jordan, priya, theo, noor]
    static let friendships = [
        Friendship(requester: me.id, recipient: alex.id, status: "accepted"),
        Friendship(requester: sam.id, recipient: me.id, status: "accepted"),
        Friendship(requester: jordan.id, recipient: me.id, status: "pending"),
        Friendship(requester: me.id, recipient: priya.id, status: "pending"),
        Friendship(requester: theo.id, recipient: me.id, status: "accepted"),
        Friendship(requester: me.id, recipient: noor.id, status: "accepted"),
    ]

    private static func post(_ number: Int, owner: SocialProfile, daysAgo: Int, caption: String, attempts: Int, sends: Int, minutes: Int?, visibility: EntryVisibility = .friends, photos: Int = 0) -> SharedSession {
        var entry = SharedSession(session: ClimbingSession(), owner: owner.id)
        entry.id = id(100 + number); entry.visibility = visibility; entry.caption = caption
        entry.session_day = SessionDay.key(for: .now.addingTimeInterval(Double(-daysAgo) * 86_400))
        entry.attempts = attempts; entry.sends = sends; entry.duration_minutes = minutes; entry.route_photo_count = photos
        return entry
    }
    static let posts = [
        post(1, owner: alex, daysAgo: 0, caption: "Finally sent the blue slab project!", attempts: 24, sends: 9, minutes: 95, photos: 3),
        post(2, owner: sam, daysAgo: 1, caption: "Quick board session after work.", attempts: 12, sends: 5, minutes: nil, visibility: .public),
        post(3, owner: me, daysAgo: 2, caption: "New gym, new problems.", attempts: 18, sends: 7, minutes: 80, photos: 1),
        // Later posts fill out the screenshot feed; the audit UI tests read only the first three.
        post(4, owner: theo, daysAgo: 1, caption: "Quarry Lane reset is spicy. Two new V5s down.", attempts: 21, sends: 8, minutes: 110, photos: 2),
        post(5, owner: noor, daysAgo: 3, caption: "Comp prep: 4x4s on the 45° wall.", attempts: 32, sends: 14, minutes: 75, visibility: .public),
        post(6, owner: alex, daysAgo: 4, caption: "Slab day. My toes have filed a complaint.", attempts: 15, sends: 6, minutes: 70, photos: 1),
    ]
    static func photos(for entry: UUID) -> [SharedRoutePhoto] {
        (0..<(posts.first { $0.id == entry }?.route_photo_count ?? 0)).map {
            let demo = demoPhoto(entry, $0)
            return SharedRoutePhoto(id: id(300 + $0), entry_id: entry, original_base64: (demo?.original ?? samplePhoto(seed: $0)).base64EncodedString(),
                                    highlighted_base64: demo?.highlighted.base64EncodedString())
        }
    }
    /// The screenshot demo shows the rendered walls from marketing/demo-media when the capture script passes them.
    private static func demoPhoto(_ entry: UUID, _ index: Int) -> (original: Data, highlighted: Data)? {
        guard ScreenshotDemo.enabled, let media = ScreenshotDemo.mediaDirectory else { return nil }
        let walls = ["wall-blue", "wall-green", "wall-purple", "wall-yellow", "wall-pink"]
        let wall = walls[((posts.firstIndex { $0.id == entry } ?? 0) + index) % walls.count]
        guard let original = try? Data(contentsOf: media.appending(path: wall + ".jpg")),
              let highlighted = try? Data(contentsOf: media.appending(path: wall + "-highlighted.jpg")) else { return nil }
        return (original, highlighted)
    }
    /// A drawn climbing wall, so sample posts need no bundled images.
    private static func samplePhoto(seed: Int) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let colors: [UIColor] = [.systemBlue, .systemYellow, .systemGreen, .systemPink, .systemOrange, .systemPurple]
        return UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600), format: format).jpegData(withCompressionQuality: 0.7) { context in
            UIColor(white: 0.84 - CGFloat(seed) * 0.08, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
            UIColor(white: 0.74 - CGFloat(seed) * 0.08, alpha: 1).setFill(); UIBezierPath(rect: CGRect(x: 300 + seed * 90, y: 0, width: 240, height: 600)).fill()
            for hold in 0..<48 {
                colors[(hold + seed) % colors.count].setFill()
                let size = CGFloat(22 + (hold * 7) % 26)
                UIBezierPath(ovalIn: CGRect(x: CGFloat((hold * 137 + seed * 53) % 780), y: CGFloat((hold * 89 + seed * 31) % 580), width: size, height: size * 0.8)).fill()
            }
        }
    }
    static func reactions() -> [UUID: [ReactionSummary]] {
        [posts[0].id: [.init(entry_id: posts[0].id, kind: "clap", total: 3, mine: false), .init(entry_id: posts[0].id, kind: "fire", total: 2, mine: true)],
         posts[2].id: [.init(entry_id: posts[2].id, kind: "strong", total: 1, mine: false)],
         posts[3].id: [.init(entry_id: posts[3].id, kind: "fire", total: 4, mine: true), .init(entry_id: posts[3].id, kind: "clap", total: 1, mine: false)],
         posts[4].id: [.init(entry_id: posts[4].id, kind: "strong", total: 3, mine: false)],
         posts[5].id: [.init(entry_id: posts[5].id, kind: "clap", total: 2, mine: false)]]
    }
    private static func comment(_ number: Int, on post: SharedSession, by person: SocialProfile, _ body: String, minutesAgo: Double) -> SessionComment {
        SessionComment(id: id(200 + number), entry_id: post.id, user_id: person.id, body: body, created_at: .now.addingTimeInterval(-minutesAgo * 60), author: person)
    }
    static func comments() -> [UUID: [SessionComment]] {
        [posts[0].id: [comment(1, on: posts[0], by: sam, "That slab has been shutting everyone down. Huge!", minutesAgo: 90),
                       comment(2, on: posts[0], by: me, "What was the beta on the top move?", minutesAgo: 25)],
         posts[2].id: [comment(3, on: posts[2], by: alex, "Save me a spot next time.", minutesAgo: 600)],
         posts[3].id: [comment(4, on: posts[3], by: noor, "The green one on the cave? So good.", minutesAgo: 300),
                       comment(5, on: posts[3], by: alex, "That reset looks so fun.", minutesAgo: 200),
                       comment(7, on: posts[3], by: me, "Saturday session there?", minutesAgo: 120)],
         posts[4].id: [comment(6, on: posts[4], by: theo, "Strong! Save some skin for Saturday.", minutesAgo: 2_000)]]
    }
}

@MainActor struct SocialAuditSampleFeed: FriendsFeedReading {
    func page(after: FriendsFeedCursor?, limit: Int) async throws -> FriendsFeedPage {
        .init(entries: after == nil ? SocialAuditSample.posts : [], profiles: SocialAuditSample.people)
    }
}
#endif
