#if DEBUG
import SwiftData
import SwiftUI

/// Isolated launch routes to the actual screens. Both arguments are required; no real account,
/// HealthKit access, or backend is used. These records live only in the existing UI-test store.
@MainActor enum AccessibilityAuditFixtures {
    /// The audit, or the screenshot demo, which reuses the audit's local Friends screens.
    static var enabled: Bool { audit || ScreenshotDemo.enabled }
    static var audit: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--accessibility-audit") }
    static var screen: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--accessibility-audit"), args.indices.contains(i + 1) else { return "home" }
        return args[i + 1]
    }
    static func seed(_ context: ModelContext) throws {
        guard audit, !ProcessInfo.processInfo.arguments.contains("--audit-empty") else { return }
        let session = ClimbingSession(date: .now.addingTimeInterval(-7200), location: "Audit gym")
        session.isComplete = true; session.endedAt = session.startedAt.addingTimeInterval(3600)
        session.visibility = .friends
        context.insert(session)
        let climb = ClimbEntry(label: "Yellow slab", color: "Yellow", grade: "V2")
        climb.projectRaw = "active"; climb.session = session; session.climbs.append(climb); context.insert(climb)
        let attempt = ClimbAttempt(sequence: 0, sent: false)
        attempt.climb = climb; attempt.sessionID = session.id; climb.attempts.append(attempt); context.insert(attempt)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240))
        let image = renderer.pngData { drawing in
            UIColor.darkGray.setFill(); drawing.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
            UIColor.yellow.setFill(); drawing.fill(CGRect(x: 100, y: 80, width: 100, height: 80))
        }
        let media = RouteMedia(kind: .photo, filename: "audit-wall.png", contentType: "public.png", data: image)
        media.annotationJSON = try RouteAnnotations.encode(RouteAnnotationDocument(strokes: [RouteStroke(color: "orange", points: [.init(x: 0.3, y: 0.4), .init(x: 0.6, y: 0.6)])], highlight: .init(x: 0.5, y: 0.5, tolerance: 0.35)))
        media.climb = climb; climb.media.append(media); context.insert(media)
        context.insert(SavedGym(name: "Audit gym"))
        context.insert(HealthWorkoutLink(sessionID: session.id, workoutID: HealthInsightsFixtureReader.workoutID, sourceName: "Fixture watch", sourceBundle: "test.health"))
        try context.save()
    }
}

struct AccessibilityAuditDestination: View {
    @Query private var sessions: [ClimbingSession]
    @Query private var climbs: [ClimbEntry]
    @Environment(ClimbingStore.self) private var store
    @State private var presenting = true
    private var modal: Bool { ["session-editor", "climb-editor", "share", "annotation", "highlight"].contains(AccessibilityAuditFixtures.screen) }
    private var arguments: [String] { ProcessInfo.processInfo.arguments }
    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if modal {
                    Color.clear.sheet(isPresented: $presenting) { destination.preferredColorScheme(arguments.contains("--audit-dark") ? .dark : .light) }
                } else { destination }
            }
            .task {
                guard let index = arguments.firstIndex(of: "--audit-scroll-anchor"),
                      arguments.indices.contains(index + 1) else { return }
                let anchor = arguments[index + 1]
                // Audit a named section after layout rather than an arbitrary physics
                // swipe endpoint with oversized text partly behind native chrome.
                await Task.yield()
                proxy.scrollTo(anchor, anchor: anchor == "journalSessionActions" ? .bottom : .top)
            }
        }
            .preferredColorScheme(arguments.contains("--audit-dark") ? .dark : .light)
            .transaction { if arguments.contains("--audit-reduce-motion") { $0.disablesAnimations = true } }
            .task {
                if arguments.contains("--audit-save-error") { store.errorMessage = "This change couldn’t be saved. Retry when storage is available." }
            }
    }
    @ViewBuilder private var destination: some View {
        switch AccessibilityAuditFixtures.screen {
        case "home": HomeView()
        case "history": HistoryView()
        case "session": if let session = sessions.first { SessionDetailView(session: session) }
        case "session-editor": SessionEditorView(session: sessions.first)
        case "climb-editor": ClimbEditorView(climb: climbs.first)
        case "projects": ProjectsView()
        case "progress": ProgressViewScreen()
        case "progress-stats": ProgressStatsView()
        case "session-log": if let session = sessions.first(where: { $0.location == "Audit gym" }) { SessionLogView(session: session) }
        case "gyms": GymsView()
        case "settings": SettingsView()
        case "friends": FriendsView(auditProfile: arguments.contains("--audit-empty") ? nil : .init(id: UUID(), username: "audit_climber", display_name: "Audit Climber", is_private: true))
        case "feed": FriendsFeedFixtureView()
        case "add-friends": AddFriendsView()
        case "suggested": SuggestedFriendsFixtureView()
        case "social-profile":
            SocialClimberProfileView(climberID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, auditPage: .init(profile: .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, username: "slab_climber", display_name: "Alex Climber", is_private: true), details: .init(id: UUID(), bio: "Working on slab technique.", avatar_base64: nil), entries: []))
        case "share": SessionEditorView(session: sessions.first) // Edit session's Friends section; tests add --audit-social-sample
        case "annotation": if let media = climbs.first?.media.first { RouteAnnotationView(media: media) }
        case "highlight": if let media = climbs.first?.media.first {
            HoldHighlightView(item: draft(media), save: { _ in true })
        }
        default: HomeView()
        }
    }
    private func draft(_ media: RouteMedia) -> RouteMediaDraft {
        var value = RouteMediaDraft(kind: .photo, filename: media.filename, contentType: media.contentType, data: media.data)
        value.annotationJSON = media.annotationJSON; return value
    }
}
#endif
