import AVKit
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct RouteMediaEditor: View {
    @Binding var attachments: [RouteMediaDraft]
    @Binding var isLoading: Bool
    @State private var selection: [PhotosPickerItem] = []
    @State private var message: String?
    @State private var preview: RouteMediaDraft?
    @State private var importFiles = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(attachments) { item in
                HStack {
                    Button { preview = item } label: { MediaLabel(kind: item.kind, filename: item.filename) }
                    Spacer()
                    Button(role: .destructive) { attachments.removeAll { $0.id == item.id } } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                    }.accessibilityLabel("Remove \(item.kind == .photo ? "photo" : "video")")
                }
            }
            if attachments.count < RouteMediaDraft.maximumItems {
                PhotosPicker(selection: $selection, maxSelectionCount: RouteMediaDraft.maximumItems - attachments.count,
                             matching: .any(of: [.images, .videos])) {
                    Label("Add photo or video", systemImage: "photo.on.rectangle.angled").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.disabled(isLoading).accessibilityIdentifier("addRouteMedia")
                Button { importFiles = true } label: {
                    Label("Choose from Files", systemImage: "folder").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                    .disabled(isLoading).accessibilityIdentifier("addRouteMediaFromFiles")
            }
            if isLoading { SwiftUI.ProgressView("Adding media…") }
            if let message { Text(message).font(.caption).foregroundStyle(.red).accessibilityIdentifier("mediaError") }
        }
        .buttonStyle(.borderless)
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            isLoading = true
        }
        .task(id: selection) {
            let items = selection
            guard !items.isEmpty else { return }
            message = nil
            var imported: [RouteMediaDraft] = []
            do {
                for item in items {
                    try Task.checkCancellation()
                    guard let file = try await item.loadTransferable(type: ImportedRouteFile.self) else {
                        throw BackupError.invalid("This item couldn’t be opened. Try another photo or video.")
                    }
                    imported.append(file.draft)
                }
                try Task.checkCancellation()
                attachments.append(contentsOf: imported.prefix(RouteMediaDraft.maximumItems - attachments.count))
            } catch is CancellationError {
                return
            } catch { message = error.localizedDescription }
            isLoading = false
            selection = []
        }
        .fileImporter(isPresented: $importFiles, allowedContentTypes: [.image, .movie], allowsMultipleSelection: true) { result in
            switch result {
            case let .success(urls):
                guard urls.count <= RouteMediaDraft.maximumItems - attachments.count else {
                    message = "Add up to 3 attachments per climb."; return
                }
                isLoading = true; message = nil
                Task {
                    do {
                        let imported = try await Task.detached(priority: .userInitiated) {
                            try urls.map { url in
                                let accessing = url.startAccessingSecurityScopedResource()
                                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                                guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) || type.conforms(to: .movie) else {
                                    throw BackupError.invalid("Choose a photo or video file.")
                                }
                                return try ImportedRouteFile.read(url, kind: type.conforms(to: .image) ? .photo : .video).draft
                            }
                        }.value
                        attachments.append(contentsOf: imported)
                    } catch { message = error.localizedDescription }
                    isLoading = false
                }
            case let .failure(error):
                if (error as NSError).code != NSUserCancelledError { message = error.localizedDescription }
            }
        }
        .sheet(item: $preview) { item in
            RouteMediaPreview(item: item) { json in
                guard let index = attachments.firstIndex(where: { $0.id == item.id }) else { return false }
                attachments[index].annotationJSON = json
                return true
            }
        }
    }
}

struct MediaLabel: View {
    let kind: RouteMediaKind
    let filename: String
    var body: some View {
        Label {
            Text(filename).lineLimit(1).truncationMode(.middle)
        } icon: { Image(systemName: kind == .photo ? "photo" : "play.rectangle") }
        .font(.subheadline).frame(minHeight: 44)
        .accessibilityLabel(kind == .photo ? "View route photo" : "Play route video")
    }
}

struct RouteMediaPreview: View {
    let item: RouteMediaDraft
    var saveAnnotations: ((String) -> Bool)? = nil
    @State private var annotationJSON: String = ""
    @State private var highlighting = false
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var temporaryURL: URL?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Group {
                if image != nil {
                    HighlightedRoutePhoto(data: item.data, annotationJSON: annotationJSON)
                        .accessibilityIdentifier("routePhotoPreview")
                } else if let player { VideoPlayer(player: player) }
                else if let message { ContentUnavailableView("Can’t open media", systemImage: "photo.badge.exclamationmark", description: Text(message)) }
                else { SwiftUI.ProgressView("Opening media…") }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(item.kind == .photo ? "Route photo" : "Route video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    if item.kind == .photo, saveAnnotations != nil {
                        Button("Highlight holds", systemImage: "scope") { highlighting = true }
                            .frame(minHeight: 44).disabled(image == nil).accessibilityIdentifier("highlightHolds")
                    }
                }
            }
            .sheet(isPresented: $highlighting) {
                var draft = item
                draft.annotationJSON = annotationJSON
                return HoldHighlightView(item: draft) { json in
                    guard saveAnnotations?(json) == true else { return false }
                    annotationJSON = json
                    return true
                }
            }
            .task {
                do {
                    annotationJSON = item.annotationJSON
                    try item.validate()
                    if item.kind == .photo {
                        let data = item.data
                        image = await Task.detached(priority: .userInitiated) {
                            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                                    kCGImageSourceThumbnailMaxPixelSize: 2048,
                                    kCGImageSourceCreateThumbnailWithTransform: true
                                  ] as CFDictionary) else { return UIImage?.none }
                            return UIImage(cgImage: image)
                        }.value
                        if image == nil { throw BackupError.invalid("This photo format couldn’t be displayed.") }
                    } else {
                        let ext = UTType(item.contentType)?.preferredFilenameExtension ?? "mov"
                        let url = FileManager.default.temporaryDirectory.appending(path: "route-\(UUID().uuidString).\(ext)")
                        try item.data.write(to: url, options: [.atomic, .completeFileProtection])
                        temporaryURL = url
                        player = AVPlayer(url: url)
                    }
                } catch { message = error.localizedDescription }
            }
            .onDisappear {
                player?.pause(); player = nil
                if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
            }
        }.tint(.primary)
    }
}
