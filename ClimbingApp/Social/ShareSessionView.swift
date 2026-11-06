import SwiftUI

struct ShareSessionView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let session: ClimbingSession
    #if DEBUG
    var auditEntry: SharedSession? = nil
    #endif
    @State private var draft: SharedSession?
    @State private var includeAttempts = true
    @State private var includeSends = true
    @State private var includeDuration = true
    @State private var reviewedPhotos: [SharedRoutePhoto] = []
    @State private var photosLoaded = false
    @State private var preparingPhoto = false
    @State private var photoError: String?
    @State private var preparation: Task<Void,Never>?
    @State private var login = false

    var body: some View {
        NavigationStack {
            Form {
                if let draft {
                    Section(header: Text("Audience").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        Picker("Visibility", selection: Binding(get: { draft.visibility }, set: { self.draft?.visibility = $0 })) {
                            ForEach(EntryVisibility.allCases) { Text($0.title).tag($0) }
                        }
                        Text(social.me?.is_private == true ? "On a private account, Public means friends only." : "Public entries are visible to signed-in climbers.").font(.caption)
                    }
                    Section(header: Text("Choose what to share").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        TextField("Separate public caption", text: Binding(get: { draft.caption }, set: { self.draft?.caption = $0 }), axis: .vertical)
                        Toggle("Attempts", isOn: $includeAttempts)
                        Toggle("Sends", isOn: $includeSends)
                        Toggle("Recorded duration", isOn: $includeDuration)
                        Button("Refresh summary from journal") {
                            var value = SharedSession(session: session, owner: draft.owner_id)
                            value.caption = draft.caption; value.visibility = draft.visibility
                            self.draft = value
                        }
                    }
                    Section(header: Text("Climb photos (optional)").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        Text("Up to three. Photos are never public.").font(.caption)
                        ForEach(Array(availablePhotos.enumerated()), id: \.element.id) { index, media in
                            HStack(spacing:12) {
                                RouteThumbnail(data:media.data).frame(width:90,height:80).clipped()
                                Button("Add photo \(index + 1)") { prepare(media) }
                                    .frame(minHeight:44).disabled(preparingPhoto || reviewedPhotos.count >= 3 || !photosLoaded)
                                    .accessibilityIdentifier("addSharedRoutePhoto\(index + 1)")
                            }
                        }
                        if availablePhotos.isEmpty { Text("Add a route photo to a climb in this session to share it here.") }
                        if preparingPhoto { SwiftUI.ProgressView("Preparing photo versions…") }
                        ForEach(reviewedPhotos) { photo in
                            SharedRoutePhotoPairView(photo:photo)
                            Button("Remove this shared photo",role:.destructive) { reviewedPhotos.removeAll { $0.id == photo.id } }
                                .frame(minHeight:44)
                        }
                        if let photoError { Text(photoError).foregroundStyle(ClimbTheme.error); if !photosLoaded { Button("Retry photos") { Task { await load() } } } }
                    }
                    Section(header: Text("Exact preview").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
                        if let preview { SharedSessionPreview(entry: preview,routePhotos:reviewedPhotos) }
                        Text("Only what’s shown here is sent. Notes, gym details, videos, markup and Health data stay private. Route photos are removed from Friends after 30 days.").font(.caption)
                    }
                    Section {
                        Button("Save reviewed entry") { Task { if let preview, await social.publish(auth, entry: preview, photos:reviewedPhotos), social.photoNotice == nil { dismiss() } } }
                            .disabled(social.busy || preparingPhoto || !photosLoaded || draft.caption.unicodeScalars.count > 1000)
                    }
                } else if social.configuration != nil && auth.account == nil {
                    Section {
                        Text("Sign in to share this session with friends. It stays private on this device until you do.")
                        Button("Sign in to share") { login = true }.frame(minHeight: 44).accessibilityIdentifier("shareSignIn")
                    }
                } else {
                    Text(social.configuration == nil ? "Friends is waiting for Supabase setup. This session is private on this device." : "Connect and set up your social profile in Friends before sharing.")
                }
                if social.configuration != nil, auth.account != nil {
                    Section {
                        RemovalStatusView(outbox: social.removals) { await social.retryRemovals(auth, force: true) }
                        Button(role: .destructive) { Task { if await social.removeShare(auth, sessionID: session.id) { dismiss() } } } label: {
                            Label("Remove shared entry", systemImage: "trash").foregroundStyle(ClimbTheme.error)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Text("Removal works offline. Friends may still see the entry and its photos until it syncs.").font(.caption)
                    }
                }
                if social.busy { SwiftUI.ProgressView("Loading…") }
                if let message = social.errorMessage { Text(message).foregroundStyle(ClimbTheme.error); Button("Retry loading") { Task { await load() } } }
            }
            .id(textSize)
            .navigationTitle("Share session")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() }.accessibleToolbarAction() } }
            .task { await load() }
            .sheet(isPresented: $login) { LoginPortalView() }
            .alert("Shared", isPresented: Binding(get: { social.photoNotice != nil }, set: { if !$0 { social.photoNotice = nil; dismiss() } })) {
                Button("OK") {}
            } message: { Text(social.photoNotice ?? "") }
            .onDisappear { preparation?.cancel() }
        }
    }

    private var preview: SharedSession? {
        guard var value = draft else { return nil }
        if !includeAttempts { value.attempts = nil }
        if !includeSends { value.sends = nil }
        if !includeDuration { value.duration_minutes = nil }
        value.route_photo_count = reviewedPhotos.count
        return value
    }

    private func load() async {
        #if DEBUG
        if AccessibilityAuditFixtures.enabled, let auditEntry { draft = auditEntry; photosLoaded = true; return }
        #endif
        guard social.configuration != nil, auth.account != nil else { return }
        await social.refresh(auth)
        guard social.errorMessage == nil, social.me != nil, social.userID != nil else { return }
        if draft == nil { draft = await social.sharedEntry(auth, session: session) }
        if !photosLoaded, let draft {
            do {
                reviewedPhotos = (draft.route_photo_count ?? 0) > 0 ? try await social.routePhotos(auth,entryID:draft.id) : []
                try Task.checkCancellation(); photosLoaded = true; photoError = nil
            } catch is CancellationError { }
            catch { photoError = "Saved photos couldn’t be loaded. Retry before saving so they aren’t accidentally removed." }
        }
    }
    private var availablePhotos: [RouteMedia] { session.orderedClimbs.flatMap(\.media).filter { $0.kind == .photo } }
    private func prepare(_ media: RouteMedia) {
        guard !preparingPhoto, reviewedPhotos.count < 3 else { return }
        preparingPhoto = true; photoError = nil
        let data = media.data, annotations = media.annotationJSON
        preparation = Task {
            defer { preparingPhoto = false }
            do {
                let settings = try RouteAnnotations.document(annotations).highlight
                let photo = try await SharedRoutePhoto.prepare(data:data,settings:settings)
                try Task.checkCancellation(); reviewedPhotos.append(photo)
            } catch is CancellationError { }
            catch { photoError = error.localizedDescription }
        }
    }

}
