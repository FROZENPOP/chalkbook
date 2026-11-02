import SwiftUI

struct SharedRoutePhotosView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    let entryID: UUID
    var previewPhotos: [SharedRoutePhoto]? = nil
    @State private var photos: [SharedRoutePhoto] = []
    @State private var loading = true
    @State private var message: String?
    @State private var retry = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if loading { SwiftUI.ProgressView("Opening climb photos…") }
                if let message { Text(message); Button("Retry") { retry += 1 }.frame(minHeight:44) }
                if !loading && message == nil && photos.isEmpty {
                    ContentUnavailableView("No accessible photos", systemImage:"photo", description:Text("Route photos are available only to the owner and accepted friends while the entry is shared with them."))
                }
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    Text("Route photo \(index + 1)").font(.headline)
                    SharedRoutePhotoPairView(photo: photo)
                }
            }.padding(20)
        }.navigationTitle("Climb photos").background(ClimbTheme.background)
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: "\(social.mediaRevision):\(retry)") {
                photos = []; loading = true; message = nil
                do {
                    let loaded: [SharedRoutePhoto]
                    if let previewPhotos { loaded = previewPhotos }
                    else { loaded = try await social.routePhotos(auth, entryID:entryID) }
                    try Task.checkCancellation(); photos = loaded; loading = false
                } catch is CancellationError { }
                catch { loading = false; message = error.localizedDescription }
            }.refreshable { retry += 1 }.onDisappear { photos = [] }
    }
}

/// A post's first photo; tapping shows them all. Nothing shows if the viewer can't open this post's photos.
struct SharedPostPhoto: View {
    @Environment(SocialStore.self) private var social
    @Environment(AccountSession.self) private var auth
    let entryID: UUID
    let count: Int
    var previewPhotos: [SharedRoutePhoto]? = nil
    let open: () -> Void
    @State private var image: UIImage?
    @State private var failed = false
    @State private var loadedKey: String?
    var body: some View {
        let key = "\(entryID):\(social.mediaRevision):\(previewPhotos?.first?.id.uuidString ?? "")"
        VStack(spacing: 0) {
            if let image {
                Button(action: open) {
                    Color.clear.aspectRatio(4 / 3, contentMode: .fit)
                        .overlay { Image(uiImage: image).resizable().scaledToFill() }
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(alignment: .topTrailing) {
                            if count > 1 {
                                Text("\(count) photos").font(.caption.weight(.semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 5).background(.black.opacity(0.65), in: Capsule()).padding(8)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
                    .accessibilityLabel(count > 1 ? "View \(count) climb photos" : "View climb photo").accessibilityIdentifier("viewSharedRoutePhotos")
            } else if failed {
                Button("View climb photos", systemImage: "photo.on.rectangle", action: open)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).accessibilityIdentifier("viewSharedRoutePhotos")
            } else if loadedKey == nil {
                RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.08)).aspectRatio(4 / 3, contentMode: .fit)
                    .overlay { SwiftUI.ProgressView() }.accessibilityLabel("Loading climb photo")
            }
        }.task(id: key) {
            guard loadedKey != key else { return } // Scrolling back to a post shouldn't download its photo again.
            do {
                let first: SharedRoutePhoto?
                if let previewPhotos { first = previewPhotos.first }
                else { first = try await social.routePhotos(auth, entryID: entryID, limit: 1).first }
                let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    (first?.highlighted_base64 ?? first?.original_base64).flatMap { Data(base64Encoded: $0) }.flatMap { UIImage(data: $0) }
                }.value
                guard !Task.isCancelled else { return }
                image = decoded; failed = first != nil && decoded == nil; loadedKey = key
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}

struct SharedRoutePhotoPairView: View {
    let photo: SharedRoutePhoto
    @State private var original: UIImage?
    @State private var highlighted: UIImage?
    @State private var showOriginal = false
    @State private var failed = false
    var body: some View {
        VStack(spacing:12) {
            if photo.highlighted_base64 != nil {
                Picker("Photo version", selection:$showOriginal) { Text("Highlighted").tag(false); Text("Original").tag(true) }
                    .pickerStyle(.segmented).accessibilityIdentifier("sharedPhotoComparison")
            } else { Text("Original photo").font(.subheadline) }
            if let image = showOriginal ? original : highlighted ?? original {
                Image(uiImage:image).resizable().scaledToFit()
                    .accessibilityLabel(showOriginal || highlighted == nil ? "Original climb photo" : "Highlighted climb photo")
                    .accessibilityIdentifier("sharedRoutePhoto")
            } else if failed { Text("This shared photo couldn’t be opened.").foregroundStyle(ClimbTheme.secondaryText) }
            else { SwiftUI.ProgressView("Opening photo…") }
        }.task(id:photo.id) {
            let result = await Task.detached(priority:.userInitiated) { () -> (UIImage?,UIImage?) in
                guard (try? photo.validated()) != nil else { return (nil,nil) }
                return (Data(base64Encoded:photo.original_base64).flatMap { UIImage(data:$0) }, photo.highlighted_base64.flatMap { Data(base64Encoded:$0) }.flatMap { UIImage(data:$0) })
            }.value
            guard !Task.isCancelled else { return }
            original = result.0; highlighted = result.1; failed = result.0 == nil
        }
    }
}

#if DEBUG
/// Isolated image-only fixture; reachable solely behind --ui-testing (no live account/network).
struct SharedRoutePhotoFixtureView: View {
    @State private var photo: SharedRoutePhoto?
    @State private var message: String?
    var body: some View {
        ScrollView {
            VStack(spacing:16) {
                Text("Photo sharing test fixture").font(.headline)
                if let photo { SharedRoutePhotoPairView(photo:photo) }
                if let message { Text(message) }
            }.padding()
        }.task {
            do {
                guard let encoded = ProcessInfo.processInfo.environment["CLIMB_TEST_PHOTO"], let data = Data(base64Encoded:encoded) else { return }
                photo = try await SharedRoutePhoto.prepare(data:data,settings:.init(x:0.125,y:0.4,tolerance:0.35))
            } catch { message = error.localizedDescription }
        }
    }
}
#endif
