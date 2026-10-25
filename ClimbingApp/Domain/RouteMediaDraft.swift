import CoreTransferable
import Foundation
import PhotosUI
import UniformTypeIdentifiers

enum RouteMediaKind: String, Codable, Sendable { case photo, video }

struct RouteMediaDraft: Identifiable, Sendable {
    static let maximumBytes = 25_000_000
    static let maximumItems = 3
    var id: UUID
    var kind: RouteMediaKind
    var filename: String
    var contentType: String
    var data: Data
    var annotationJSON: String = ""

    init(id: UUID = UUID(), kind: RouteMediaKind, filename: String, contentType: String, data: Data) {
        self.id = id; self.kind = kind; self.filename = filename; self.contentType = contentType; self.data = data
    }

    func validate() throws {
        guard !data.isEmpty, data.count <= Self.maximumBytes,
              let type = UTType(contentType),
              kind == .photo ? type.conforms(to: .image) : type.conforms(to: .movie) else {
            throw BackupError.invalid("Choose a photo or video smaller than 25 MB.")
        }
    }
}

struct ImportedRouteFile: Transferable, Sendable {
    let draft: RouteMediaDraft

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { file in try read(file.file, kind: .photo) }
        FileRepresentation(importedContentType: .movie) { file in try read(file.file, kind: .video) }
    }

    static func read(_ url: URL, kind: RouteMediaKind) throws -> Self {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= RouteMediaDraft.maximumBytes else {
            throw BackupError.invalid("Choose a photo or video smaller than 25 MB.")
        }
        let type = UTType(filenameExtension: url.pathExtension) ?? (kind == .photo ? .image : .movie)
        let draft = RouteMediaDraft(kind: kind, filename: url.lastPathComponent, contentType: type.identifier, data: try Data(contentsOf: url))
        try draft.validate()
        return Self(draft: draft)
    }
}

extension RouteMedia {
    var draft: RouteMediaDraft {
        var result=RouteMediaDraft(id: id, kind: kind, filename: filename, contentType: contentType, data: data)
        result.annotationJSON=annotationJSON;return result
    }
}
