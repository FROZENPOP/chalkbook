#if DEBUG
import SwiftData
import SwiftUI

/// Realistic sample journal for App Store screenshots. Debug builds only, in the UI-test store.
/// Route photos and the avatar load at run time from `CHALKBOOK_DEMO_MEDIA` (marketing/demo-media), never from the app bundle.
@MainActor enum ScreenshotDemo {
    nonisolated static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--screenshot-demo") }

    static var startTab: Int { Int(argument("--start-tab") ?? "") ?? 0 }
    /// A screen pushed on top of the start tab: "session" (Journal) or "stats" (Progress).
    static var screen: String? { argument("--demo-screen") }
    private static func argument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard enabled, let i = args.firstIndex(of: name), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
    nonisolated static var mediaDirectory: URL? { ProcessInfo.processInfo.environment["CHALKBOOK_DEMO_MEDIA"].map { URL(fileURLWithPath: $0) } }
    static let climberName = "Robin Hale"
    /// Every demo wall's start hold sits here (see marketing/demo-media/render_demo_media.swift).
    static let startHold = RoutePoint(x: 0.5, y: 0.86)

    /// Fixed seed, so every capture shows the same journal.
    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
    }
    private struct Route {
        let name, color, grade: String; let styles: [ClimbStyle]; let gym: Int; var wall: String? = nil; var notes = ""
        var level: Int { Int(grade.dropFirst())! }
    }
    static let gymNames = ["Basalt Bouldering", "Northside Wall", "Quarry Lane Boulders"]
    private static let routes: [Route] = [
        Route(name: "Morning Mantle", color: "Yellow", grade: "V0", styles: [.slab, .balance], gym: 0),
        Route(name: "Jug Life", color: "Green", grade: "V1", styles: [.overhang], gym: 0),
        Route(name: "Flake News", color: "Orange", grade: "V2", styles: [.vertical], gym: 0),
        Route(name: "Pocket Rocket", color: "Blue", grade: "V3", styles: [.crimps, .vertical], gym: 0),
        Route(name: "Heel Yeah", color: "Purple", grade: "V4", styles: [.overhang, .power], gym: 0, wall: "wall-purple.jpg", notes: "Heel hook on the purple volume, then drop knee."),
        Route(name: "Sloper Season", color: "Teal", grade: "V4", styles: [.slopers], gym: 0),
        Route(name: "Gaston Martin", color: "White", grade: "V5", styles: [.vertical, .crimps], gym: 0),
        Route(name: "Pinch Me", color: "Pink", grade: "V5", styles: [.overhang], gym: 0, notes: "Thumb catch on the second pinch."),
        Route(name: "Arête You Ready", color: "White", grade: "V2", styles: [.balance], gym: 1),
        Route(name: "Dyno-mite", color: "Orange", grade: "V3", styles: [.power], gym: 1),
        Route(name: "Volume Control", color: "Teal", grade: "V4", styles: [.slopers, .balance], gym: 1),
        Route(name: "Compression Session", color: "Green", grade: "V5", styles: [.overhang, .slopers], gym: 1, wall: "wall-green.jpg"),
        Route(name: "Toe Hook Tuesday", color: "Purple", grade: "V6", styles: [.overhang], gym: 1),
        Route(name: "Chalk Talk", color: "Yellow", grade: "V1", styles: [.vertical], gym: 2),
        Route(name: "Lip Service", color: "Pink", grade: "V3", styles: [.overhang], gym: 2),
        Route(name: "Crimp Lord", color: "Blue", grade: "V6", styles: [.crimps], gym: 2),
    ]
    /// Projects follow their own script instead of the random sends.
    private static let sentProject = Route(name: "Tension Headache", color: "Pink", grade: "V7", styles: [.overhang, .power], gym: 0, wall: "wall-pink.jpg",
                                           notes: "Left heel high, match the pinch, then commit to the lip.")
    private static let activeProjects = [
        Route(name: "Undertow", color: "Blue", grade: "V8", styles: [.overhang, .crimps], gym: 0, wall: "wall-blue.jpg", notes: "Start is fine. The cross to the blue crimp is the crux."),
        Route(name: "Smear Campaign", color: "Yellow", grade: "V6", styles: [.slab, .balance], gym: 0, wall: "wall-yellow.jpg", notes: "Trust the feet. Hips into the wall."),
    ]
    private static let sessionNotes = [
        0: "Sent Tension Headache on the third go today! The heel finally stuck.",
        3: "Short one. Footwork drills on the slab wall.",
        11: "Felt strong today. Everything clicked.",
        20: "Board night with the crew. Fingers are toast.",
    ]

    static func seed(_ context: ModelContext, enabled: Bool = enabled, media: URL? = mediaDirectory,
                     profileDirectory: URL = URL.applicationSupportDirectory.appending(path: "UITestProfiles")) throws {
        guard enabled, try context.fetchCount(FetchDescriptor<ClimbingSession>()) == 0 else { return }
        let gyms = gymNames.enumerated().map { SavedGym(name: $1, isDefault: $0 == 0) }
        gyms.forEach(context.insert)
        var rng = Generator(state: 42)
        var climbs: [String: ClimbEntry] = [:]
        let today = Calendar.current.startOfDay(for: .now)
        let count = 36
        // About three sessions a week for thirteen weeks; the hardest grade sent rises from V4 to V7.
        for index in 0..<count {
            let ago = 90 - index * 89 / (count - 1), recent = count - 1 - index // recent 0 is yesterday's session
            let gymIndex = recent % 3 == 2 ? 1 : (recent % 7 == 5 ? 2 : 0)
            let gym = gyms[gymIndex]
            let start = Calendar.current.date(byAdding: .day, value: -ago, to: today)!.addingTimeInterval(Double(17 * 60 + Int.random(in: 0...90, using: &rng)) * 60)
            let session = ClimbingSession(date: start, location: gym.name, notes: sessionNotes[recent] ?? "")
            session.gymID = gym.id; session.isComplete = true; session.createdAt = start; session.updatedAt = start
            session.endedAt = start.addingTimeInterval(Double(Int.random(in: 75...130, using: &rng)) * 60)
            context.insert(session)
            let cap = 4 + index * 3 / count // hardest grade sent this session: V4 rising to V6, then the V7 project
            var picks = routes.filter { $0.gym == gymIndex && $0.level <= cap + 1 }.shuffled(using: &rng).prefix(Int.random(in: 4...6, using: &rng)).map { ($0, false) }
            if gymIndex == 0 && recent < 12 { picks += activeProjects.map { ($0, true) } }
            if gymIndex == 0 && recent < 16 { picks.append((sentProject, true)) }
            var minute = 10.0
            for (route, project) in picks {
                let climb = entry(route, gym: gym, session: session, context: context, climbs: &climbs)
                if project { climb.projectRaw = "active" }
                let tries: Int, sends: Bool
                if route.name == sentProject.name { tries = recent == 0 ? 3 : Int.random(in: 2...4, using: &rng); sends = recent == 0 }
                else if project { tries = Int.random(in: 2...4, using: &rng); sends = false }
                else if climb.isSent { tries = 1; sends = true }
                else if route.level <= cap { tries = route.level <= cap - 2 ? 1 : Int.random(in: 1...3, using: &rng); sends = true }
                else { tries = Int.random(in: 2...4, using: &rng); sends = false }
                for step in 0..<tries {
                    let attempt = ClimbAttempt(sequence: (climb.attempts.map(\.sequence).max() ?? -1) + 1, sent: sends && step == tries - 1,
                                               recordedAt: start.addingTimeInterval(minute * 60))
                    minute += Double(Int.random(in: 3...7, using: &rng))
                    attempt.climb = climb; attempt.sessionID = session.id; attempt.daySnapshot = session.day
                    attempt.gradeSnapshot = climb.descriptor.encoded; attempt.updatedAt = attempt.recordedAt
                    climb.attempts.append(attempt); context.insert(attempt)
                }
                if route.name == sentProject.name { session.selectedClimbID = climb.id }
            }
        }
        for (route, notes) in [(sentProject, ["Worked the lip in three parts. Heel, match, slap.", "Heel hook is everything. Go when the skin is fresh."]),
                               (activeProjects[0], ["Linked crux to the top twice. Need a fresh day."])] {
            guard let climb = climbs[route.gym.description + route.name] else { continue }
            for (offset, text) in notes.enumerated() {
                let note = ClimbNote(text: text, sessionID: climb.session?.id)
                note.createdAt = .now.addingTimeInterval(Double(-offset - 1) * 4 * 86_400); note.updatedAt = note.createdAt
                note.climb = climb; climb.notebook.append(note); context.insert(note)
            }
            if route.name == activeProjects[0].name { climb.pinnedNoteID = climb.notebook.first?.id }
        }
        if let media {
            for route in routes + [sentProject] + activeProjects {
                guard let wall = route.wall, let climb = climbs[route.gym.description + route.name],
                      let data = try? Data(contentsOf: media.appending(path: wall)) else { continue }
                let photo = RouteMedia(kind: .photo, filename: route.name + ".jpg", contentType: "public.jpeg", data: data)
                photo.annotationJSON = try RouteAnnotations.encode(RouteAnnotationDocument(strokes: [], highlight: .init(selections: [startHold])))
                photo.climb = climb; climb.media.append(photo); context.insert(photo)
            }
            if let avatar = try? Data(contentsOf: media.appending(path: "avatar.jpg")) {
                ProfileStore(key: "guest", directory: profileDirectory)
                    .save(name: climberName, bio: "Bouldering three times a week. Chasing my first V8.", photo: try ProfilePhoto.prepare(avatar))
            }
        }
        try context.save()
    }

    /// One entry per route and gym, carried across sessions like a real project.
    private static func entry(_ route: Route, gym: SavedGym, session: ClimbingSession, context: ModelContext, climbs: inout [String: ClimbEntry]) -> ClimbEntry {
        let key = route.gym.description + route.name
        if let existing = climbs[key] { session.linkedClimbs.append(existing); return existing }
        let climb = ClimbEntry(label: route.name, color: route.color, grade: route.grade, styles: route.styles.map(\.rawValue), prior: .newClimb, notes: route.notes)
        climb.gymID = gym.id; climb.gymName = gym.name; climb.session = session; climb.createdAt = session.startedAt; climb.updatedAt = session.startedAt
        session.climbs.append(climb); context.insert(climb); climbs[key] = climb
        return climb
    }
}

/// Pushes the screen named by `--demo-screen` on top of a tab's root, so the capture shows real navigation.
struct ScreenshotDemoPush: ViewModifier {
    let tab: Int
    @Query(sort: \ClimbingSession.startedAt, order: .reverse) private var sessions: [ClimbingSession]
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: $shown) {
                if tab == 0, let session = sessions.first { SessionDetailView(session: session) }
                else if tab == 2 { ProgressStatsView() }
            }
            .task { shown = ScreenshotDemo.startTab == tab && ScreenshotDemo.screen == (tab == 0 ? "session" : "stats") }
    }
}
#endif
