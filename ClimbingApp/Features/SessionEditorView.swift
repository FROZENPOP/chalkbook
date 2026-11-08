import SwiftUI
import SwiftData

struct SessionEditorView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(ClimbingStore.self) private var store
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedGym.name) private var gyms: [SavedGym]
    @State private var selectedGymID: UUID?
    @State private var initialized = false
    var session: ClimbingSession?
    var isRecap = false
    var onStart: (ClimbingSession) -> Void = { _ in }
    @State private var startTime = Date.now
    @State private var endTime = Date.now
    @State private var minutes = ""
    @State private var created: ClimbingSession?
    @State private var recap: ClimbingSession?
    @State private var date = Date.now
    @State private var location = ""
    @State private var notes = ""
    @State private var visibility = EntryVisibility.friends
    @State private var caption = ""
    @State private var shareAttempts = true
    @State private var shareSends = true
    @State private var shareDuration = true
    @State private var sharePhotos = true
    @State private var shareLoaded = false
    @State private var loadingShare = false
    @State private var loadProblem: String?
    @State private var syncing = false
    @State private var closeAfterSync = true
    @State private var shareProblem: String?
    @State private var shareNotice: String?
    @State private var editingClimb: ClimbEntry?
    @State private var climbContent: [String] = []
    @State private var login = false

    /// Signed in with Friends set up. The DEBUG audit sample stands in for an account and never reaches the network.
    private var friendsReady: Bool {
        #if DEBUG
        if SocialAuditSample.enabled { return true }
        #endif
        return auth.account != nil && social.configuration != nil && !social.profileMissing
    }
    private var captionTooLong: Bool { visibility != .private && caption.unicodeScalars.count > 1000 }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Session").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    GymSelectionRow(selectedID: $selectedGymID)
                    if selectedGymID == nil {
                        TextField("Other location (optional)", text: $location, axis: .vertical).lineLimit(1...3).textInputAutocapitalization(.words)
                            .accessibilityIdentifier("sessionLocation").frame(minHeight: 44)
                    }
                    if isRecap { DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date) }
                    if session == nil && friendsReady { visibilityPicker }
                }
                if session != nil {
                    Section(header: Text("Time").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        DatePicker("Started", selection: $startTime, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                        if session?.isComplete == true {
                            DatePicker("Ended", selection: $endTime, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                            LabeledContent("Duration", value: durationLabel)
                            if let session, session.pausedSeconds >= 60 { LabeledContent("Paused", value: Int(session.pausedSeconds / 60).counted("minute")) }
                        }
                    }
                } else if isRecap {
                    Section(header: Text("Duration").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        TextField("Minutes (optional)", text: $minutes).keyboardType(.numberPad)
                    }
                }
                Section(header: Text("Notes").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                    TextField("How are you feeling?", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                if let session {
                    friendsSection(session)
                    Section(header: Text("Photos and videos").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        if session.orderedClimbs.isEmpty { Text("Photos and videos are added to climbs. Add a climb to this session first.") }
                        ForEach(session.orderedClimbs) { climb in
                            Button { climbContent = SharedSession.content(of: session); editingClimb = climb } label: {
                                LabeledContent {
                                    Text("\(climb.media.filter { $0.kind == .photo }.count.counted("photo")) · \(climb.media.filter { $0.kind != .photo }.count.counted("video"))")
                                } label: { Label(climb.title, systemImage: "photo.on.rectangle") }
                                    .frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .foregroundStyle(.primary).accessibilityHint("Opens this climb to add photos and videos").accessibilityIdentifier("climbMedia")
                        }
                    }
                }
            }
            .id(textSize)
            .navigationTitle(session == nil ? (isRecap ? "Past session recap" : "New session") : "Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() }.accessibleToolbarAction() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(session == nil ? (isRecap ? "Create recap" : "Start") : "Save", systemImage: session == nil ? "play.fill" : "checkmark", action: submit).fontWeight(.semibold)
                        .accessibleToolbarAction().accessibilityIdentifier("saveSession")
                        .disabled(syncing || loadingShare || recap != nil || captionTooLong)
                }
            }
            .onAppear {
                guard !initialized else { return }; initialized = true
                if let session {
                    selectedGymID = session.gymID
                    date = SessionDay.date(for: session.day) ?? .now
                    location = session.location
                    notes = session.notes
                    startTime = session.startedAt; endTime = session.endedAt ?? .now
                } else { selectedGymID = gyms.first(where: \.isDefault)?.id ?? gyms.first?.id }
            }
            .task {
                // Posting needs a Friends profile; find out before offering a visibility.
                if friendsReady, auth.account != nil, social.configuration != nil { await social.loadProfile(auth, quietly: true) }
                if let session, friendsReady, !shareLoaded { await loadShare(session) }
            }
            .sheet(isPresented: $login) { LoginPortalView() }
            .sheet(item: $editingClimb, onDismiss: {
                // Media saved in the climb editor reaches Friends with the session's saved settings.
                // Unsaved settings on screen go out with Save instead.
                guard let session, session.isComplete, SharedSession.content(of: session) != climbContent, !settingsEdited(session) else { return }
                closeAfterSync = false; Task { await sync(session) }
            }) { ClimbEditorView(session: session, climb: $0) }
            .alert("Shared", isPresented: Binding(get: { shareNotice != nil }, set: { if !$0 { shareNotice = nil; if closeAfterSync { dismiss() } } })) {
                Button("OK") {}
            } message: { Text(shareNotice ?? "") }
        }
        .environment(\.timeZone, session.flatMap { TimeZone(identifier: $0.timeZoneID) } ?? .current)
        .sheet(item: $created, onDismiss: {
            guard let recap else { dismiss(); return }
            closeAfterSync = true; Task { await sync(recap) }
        }) { AggregateEditorView(session: $0) }
        .safeAreaInset(edge: .top) { VStack(spacing: 0) { SaveErrorBanner(); syncBanner } }
    }

    @ViewBuilder private var visibilityPicker: some View {
        Picker("Visibility", selection: $visibility) { ForEach(EntryVisibility.allCases) { Text($0.title).tag($0) } }
            .frame(minHeight: 44).accessibilityIdentifier("sessionVisibility")
        if social.me?.is_private == true { Text("On a private account, Public means friends only.").font(.caption) }
    }

    @ViewBuilder private func friendsSection(_ session: ClimbingSession) -> some View {
        if friendsReady {
            Section(header: Text("Friends").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                if shareLoaded {
                    visibilityPicker
                    if visibility != .private {
                        TextField("Caption (optional)", text: $caption, axis: .vertical).lineLimit(1...4).accessibilityIdentifier("shareCaption")
                        if captionTooLong { Text("Shorten the caption to 1,000 characters or fewer.").foregroundStyle(ClimbTheme.error) }
                        Toggle("Attempts", isOn: $shareAttempts)
                        Toggle("Sends", isOn: $shareSends)
                        Toggle("Recorded duration", isOn: $shareDuration)
                        Toggle("Share photos", isOn: $sharePhotos)
                        Text("The first 3 photos from this session’s climbs. Photos are never public, and videos stay on this device.").font(.caption)
                        SharedSessionPreview(entry: preview(session)).accessibilityIdentifier("sharePreview")
                        if sharePhotos, photoCount(session) > 0 { Text("Plus \(photoCount(session).counted("photo")).").font(.subheadline) }
                        Text("Only what’s shown here is sent. Notes, gym details, videos, markup and Health data stay private. Route photos are removed from Friends after 30 days.").font(.caption)
                    }
                    if !session.isComplete { Text("Posts to Friends when you finish the session.").font(.caption) }
                } else if let loadProblem {
                    Text(loadProblem).foregroundStyle(ClimbTheme.error)
                    Button("Retry") { Task { await loadShare(session) } }.frame(minHeight: 44).accessibilityIdentifier("retryShareSettings")
                } else {
                    SwiftUI.ProgressView("Loading Friends settings…")
                }
            }
        } else if social.configuration != nil && auth.account != nil {
            Section(header: Text("Friends").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                Text("Set up your Friends profile in the Friends tab to share sessions.")
            }
        } else if social.configuration != nil {
            Section(header: Text("Friends").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                Text("Sign in to share sessions with friends. This session stays private until you sign in and change its visibility.")
                Button("Sign in to share") { login = true }.frame(minHeight: 44).accessibilityIdentifier("shareSignIn")
            }
        }
    }

    @ViewBuilder private var syncBanner: some View {
        if let target = session ?? recap, syncing || shareProblem != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let shareProblem {
                    Label("Friends wasn’t updated", systemImage: "exclamationmark.triangle.fill").font(.headline)
                    Text("Your session is saved on this device. \(shareProblem)").font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Button("Retry") { Task { await sync(target) } }.buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("retryShare")
                } else { SwiftUI.ProgressView("Updating Friends…") }
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground)).accessibilityElement(children: .contain)
        }
    }

    private func photoCount(_ session: ClimbingSession) -> Int { session.sharedPhotoMedia.count }

    private func settingsEdited(_ session: ClimbingSession) -> Bool {
        shareLoaded && (visibility != session.visibility || caption != session.shareCaption || shareAttempts != session.shareAttempts
            || shareSends != session.shareSends || shareDuration != session.shareDuration || sharePhotos != session.sharePhotos)
    }

    /// What syncShare sends, apart from the photos.
    private func preview(_ session: ClimbingSession) -> SharedSession {
        var entry = SharedSession(session: session, owner: social.userID ?? UUID())
        entry.visibility = visibility; entry.caption = caption
        if !shareAttempts { entry.attempts = nil }
        if !shareSends { entry.sends = nil }
        if !shareDuration { entry.duration_minutes = nil }
        return entry
    }

    private func loadShare(_ session: ClimbingSession) async {
        loadProblem = nil
        if session.shareVisibility == nil {
            loadingShare = true; social.errorMessage = nil
            await social.adoptShare(auth, session: session)
            loadingShare = false
        }
        guard let chosen = session.visibility else { loadProblem = social.errorMessage ?? "Friends settings couldn’t be loaded. Check your connection and try again."; return }
        visibility = chosen; caption = session.shareCaption
        shareAttempts = session.shareAttempts; shareSends = session.shareSends; shareDuration = session.shareDuration; sharePhotos = session.sharePhotos
        shareLoaded = true
    }

    private func sync(_ target: ClimbingSession) async {
        syncing = true; shareProblem = nil
        shareProblem = await Self.syncShare(social, auth, target)
        syncing = false
        guard shareProblem == nil else { return }
        if let notice = social.photoNotice { shareNotice = notice; social.photoNotice = nil } else if closeAfterSync { dismiss() }
    }

    /// Brings Friends in line with a saved session. Nil when done, otherwise a plain-English problem.
    static func syncShare(_ social: SocialStore, _ auth: AccountSession, _ session: ClimbingSession) async -> String? {
        social.errorMessage = nil; social.photoNotice = nil
        // False without a message means Friends was busy or the request was cancelled.
        return await social.syncShare(auth, session: session) ? nil : social.errorMessage ?? "Couldn’t update Friends. Try again."
    }

    private func timesChanged(_ session: ClimbingSession) -> Bool {
        startTime != session.startedAt || (session.isComplete && endTime != session.endedAt)
    }

    private var durationLabel: String {
        guard let session, session.durationKnown || timesChanged(session) else { return "Not recorded" }
        return max(0, Int((endTime.timeIntervalSince(startTime) - session.pausedSeconds) / 60)).counted("minute")
    }

    private func submit() {
        let gym = gyms.first { $0.id == selectedGymID }
        let chosen = friendsReady ? visibility : .private
        if let session {
            if store.save({
                let oldDay = session.day
                if timesChanged(session) { session.durationKnown = true }
                session.day = SessionDay.key(for: startTime, in: TimeZone(identifier: session.timeZoneID) ?? .current)
                session.location = gym?.name ?? location.trimmingCharacters(in: .whitespacesAndNewlines)
                session.gymID = gym?.id
                guard session.isComplete == false || endTime >= startTime else { throw BackupError.invalid("End time must follow start time.") }
                session.startedAt = startTime; if session.isComplete { session.endedAt = endTime }
                session.updatedAt = .now
                for attempt in session.recordedAttempts where attempt.daySnapshot == oldDay || attempt.daySnapshot.isEmpty { attempt.daySnapshot = session.day; attempt.timePrecision = "day" }
                session.notes = notes
                if shareLoaded {
                    session.visibility = visibility; session.shareCaption = caption
                    session.shareAttempts = shareAttempts; session.shareSends = shareSends; session.shareDuration = shareDuration; session.sharePhotos = sharePhotos
                }
            }) {
                if session.isComplete { closeAfterSync = true; Task { await sync(session) } } else { dismiss() }
            }
        } else if isRecap {
            let entered = minutes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !entered.isEmpty && !(0...10_080).contains(Int(entered) ?? -1) { store.errorMessage = "Enter a duration of up to 10,080 minutes (one week), or leave it blank."; return }
            // Posted after the remembered totals sheet closes, so the post carries them.
            created = store.createRecap(date: date, gym: gym, location: location, notes: notes, minutes: Int(entered), visibility: chosen)
            recap = created
        } else if let started = store.start(date: .now, location: location, notes: notes, gym: gym, visibility: chosen) {
            onStart(started)
            dismiss()
        }
    }
}
