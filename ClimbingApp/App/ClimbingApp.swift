import AuthenticationServices
import GoogleSignIn
import SwiftUI
import SwiftData

@main
struct ClimbingApp: App {
    @State private var auth: AccountSession
    @State private var invitations = FriendInviteRouter()
    @AppStorage("appearance", store: .standard) private var appearance = "dark"
    @Environment(\.scenePhase) private var scenePhase
    private let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    // UI tests opt in so every other test still starts in the journal.
    @State private var welcome = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        ? ProcessInfo.processInfo.arguments.contains("--show-welcome") : !UserDefaults.standard.bool(forKey: "chosenStart")

    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let configured = LoginConfiguration.appleEnabled || LoginConfiguration.googleClientID != nil
        let vault: any AccountVault = testing || !configured ? GuestAccountVault() : KeychainAccountVault()
        _auth = State(initialValue: AccountSession(vault: vault))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if welcome && auth.account == nil {
                    LoginPortalView { welcome = false; if !testing { UserDefaults.standard.set(true, forKey: "chosenStart") } }
                } else {
                    WorkspaceRoot(accountKey: auth.account?.storageKey, testing: testing)
                        .id(auth.account?.storageKey ?? "guest")
                }
            }
            // UI tests keep the system appearance; audits pick light or dark themselves.
            .preferredColorScheme(testing ? nil : appearance == "light" ? .light : appearance == "system" ? nil : .dark)
            .environment(auth)
            .environment(invitations)
            .onOpenURL { url in invitations.open(url); _ = GIDSignIn.sharedInstance.handle(url) }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in if let url=activity.webpageURL { invitations.open(url) } }
            .task { if !testing { await auth.restore() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && !testing { Task { await auth.verifyExistingSession() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
                if auth.account?.provider == .apple { auth.signOut() }
            }
        }
    }
}

private struct WorkspaceRoot: View {
    let accountKey: String?
    let testing: Bool
    @State private var container: ModelContainer?
    @State private var startupError: String?

    var body: some View {
        Group {
            if let container {
                AppRoot(container: container, profileKey: accountKey ?? "guest", profileDirectory: testing ? URL.applicationSupportDirectory.appending(path: "UITestProfiles") : nil)
                    .modelContainer(container)
                    .defaultAppStorage(testing ? UserDefaults(suiteName: "ClimbLog.UITesting")! : accountKey.flatMap { UserDefaults(suiteName: "ClimbLog.\($0)") } ?? .standard)
            } else if let startupError {
                ContentUnavailableView {
                    Label("Your log couldn’t open", systemImage: "externaldrive.badge.exclamationmark")
                } description: { Text("Your stored data has not been replaced.\n\n\(startupError)") }
                actions: { Button("Try again", action: load) }
            } else {
                SwiftUI.ProgressView("Opening your log…")
            }
        }
        .task { load() }
    }

    private func load() {
        do {
            if testing {
                #if DEBUG
                // Seed source files only; the UI tests still import them through the real Files picker.
                let documents = URL.documentsDirectory
                try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
                for (key, filename) in [("CLIMB_TEST_PHOTO", "route-photo.png"), ("CLIMB_TEST_VIDEO", "route-video.mov")] {
                    if let value = ProcessInfo.processInfo.environment[key], let data = Data(base64Encoded: value), data.count < 1_000_000 {
                        try data.write(to: documents.appending(path: filename), options: .atomic)
                    }
                }
                #endif
                let schema = Schema(versionedSchema: ClimbingSchemaV6.self)
                let url = URL.applicationSupportDirectory.appending(path: "ClimbingUITests.store")
                try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
                if ProcessInfo.processInfo.arguments.contains("--reset-test-data") {
                    UserDefaults.standard.removePersistentDomain(forName: "ClimbLog.UITesting")
                    let profiles = URL.applicationSupportDirectory.appending(path: "UITestProfiles")
                    if FileManager.default.fileExists(atPath: profiles.path) { try FileManager.default.removeItem(at: profiles) }
                    for suffix in ["", "-shm", "-wal"] {
                        let path = URL(fileURLWithPath: url.path + suffix)
                        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
                    }
                }
                let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
                let store = try ModelContainer(for: schema, migrationPlan: ClimbingMigrationPlan.self, configurations: [config])
                store.mainContext.autosaveEnabled = false
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--health-insights-fixture"), try store.mainContext.fetchCount(FetchDescriptor<ClimbingSession>()) == 0 {
                    let session = ClimbingSession(date: .now.addingTimeInterval(-7200), location: "Health fixture session")
                    session.endedAt = session.startedAt.addingTimeInterval(3600); session.isComplete = true
                    store.mainContext.insert(session)
                    store.mainContext.insert(HealthWorkoutLink(sessionID: session.id, workoutID: HealthInsightsFixtureReader.workoutID, sourceName: "UI test watch", sourceBundle: "test.health"))
                    let unlinked = ClimbingSession(date: .now.addingTimeInterval(-3600), location: "Unlinked fixture session")
                    unlinked.endedAt = unlinked.startedAt.addingTimeInterval(1800); unlinked.isComplete = true
                    store.mainContext.insert(unlinked)
                    try store.mainContext.save()
                }
                #endif
                #if DEBUG
                if AccessibilityAuditFixtures.enabled { try AccessibilityAuditFixtures.seed(store.mainContext) }
                #endif
                container = store
            } else {
                container = try Persistence.container(accountKey: accountKey)
            }
            startupError = nil
        } catch { startupError = error.localizedDescription }
    }
}

struct AppRoot: View {
    @Environment(AccountSession.self) private var auth
    @Environment(FriendInviteRouter.self) private var invitations
    @State private var store: ClimbingStore
    @State private var profiles: ProfileStore
    @State private var social: SocialStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var setupProfile = false

    init(container: ModelContainer, profileKey: String = "guest", profileDirectory: URL? = nil) {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let outbox = RemovalOutbox(accountKey: profileKey, directory: testing ? URL.applicationSupportDirectory.appending(path: "UITestRemovalOutboxes") : nil)
        _social = State(initialValue: SocialStore(accountKey: profileKey, removals: outbox))
        _store = State(initialValue: ClimbingStore(context: container.mainContext))
        _profiles = State(initialValue: ProfileStore(key: profileKey, directory: profileDirectory))
    }

    var body: some View {
        VStack(spacing: 0) {
            SaveErrorBanner()
            TabView {
                NavigationStack {
                    #if DEBUG
                    if AccessibilityAuditFixtures.enabled { AccessibilityAuditDestination() } else { HomeView() }
                    #else
                    HomeView()
                    #endif
                }.tabItem { Label("Journal", systemImage: "book") }
                NavigationStack { ProjectsView() }.tabItem { Label("Projects", systemImage: "figure.climbing") }
                NavigationStack { ProgressViewScreen() }.tabItem { Label("Progress", systemImage: "chart.bar.xaxis") }
                NavigationStack { friendsRoot }.tabItem { Label("Friends", systemImage: "person.2") }
            }
        }
        .id(store.dataRevision)
        .tint(ClimbTheme.accent)
        .environment(store)
        .environment(profiles)
        .environment(social)
        .task {
            setupProfile = invitations.target == nil && auth.account != nil && profiles.profile == nil && profiles.errorMessage == nil
            await social.retryRemovals(auth)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await social.retryRemovals(auth) } }
        }
        .sheet(isPresented: $setupProfile) {
            ProfileEditorView(setup: true).environment(profiles)
        }
        .sheet(isPresented:Binding(get:{ invitations.target != nil },set:{ if !$0 { invitations.target=nil } })) {
            NavigationStack {
                if let target=invitations.target {
                    if auth.account != nil { SocialClimberProfileView(climberID:target) }
                    else { LoginPortalView() }
                }
            }
        }
    }

    @ViewBuilder private var friendsRoot: some View {
        #if DEBUG
        // Isolated Debug social UI fixtures for accessibility tests; never contact live accounts.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--test-removal-outbox") {
            RemovalOutboxFixtureView()
        } else if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--test-friend-feed") {
            FriendsFeedFixtureView()
        } else if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--test-friend-suggestions") {
            SuggestedFriendsFixtureView()
        } else if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--test-shared-route-photo") {
            SharedRoutePhotoFixtureView()
        } else if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--test-friend-search") {
            AddFriendsView()
        } else { FriendsView() }
        #else
        FriendsView()
        #endif
    }
}

#Preview {
    let container = try! Persistence.container(inMemory: true)
    AppRoot(container: container).modelContainer(container).environment(AccountSession(vault: GuestAccountVault())).environment(FriendInviteRouter())
}
