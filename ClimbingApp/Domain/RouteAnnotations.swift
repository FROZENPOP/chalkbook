import Foundation

struct RoutePoint: Codable, Equatable, Sendable { var x: Double; var y: Double }
struct RouteStroke: Codable, Equatable, Sendable {
    var color: String
    var points: [RoutePoint]
}
struct RouteAnnotationDocument: Codable, Equatable, Sendable {
    var version = 1
    var strokes: [RouteStroke]
    var highlight: HoldHighlightSettings?
}

enum RouteAnnotations {
    static func document(_ json: String) throws -> RouteAnnotationDocument {
        guard json.utf8.count <= 500_000 else { throw BackupError.invalid("The route markup is too large.") }
        if json.isEmpty { return RouteAnnotationDocument(strokes: [], highlight: nil) }
        let data = Data(json.utf8)
        if let legacy = try? JSONDecoder().decode([RouteStroke].self, from: data) {
            try validate(legacy)
            return RouteAnnotationDocument(strokes: legacy, highlight: nil)
        }
        let value = try JSONDecoder().decode(RouteAnnotationDocument.self, from: data)
        guard value.version == 1, value.highlight?.isValid != false else { throw BackupError.invalid("Invalid hold highlight settings.") }
        try validate(value.strokes)
        return value
    }

    static func encode(_ document: RouteAnnotationDocument) throws -> String {
        let json = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
        _ = try self.document(json)
        return json
    }

    static func decode(_ json: String) throws -> [RouteStroke] {
        try document(json).strokes
    }
    private static func validate(_ strokes: [RouteStroke]) throws {
        guard strokes.count <= 200, strokes.allSatisfy({ stroke in
            ["orange","blue","white"].contains(stroke.color) && (1...2000).contains(stroke.points.count) && stroke.points.allSatisfy {
                $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)
            }
        }) else { throw BackupError.invalid("The route markup contains invalid points.") }
    }
    static func encode(_ strokes: [RouteStroke]) throws -> String {
        let json = String(decoding: try JSONEncoder().encode(strokes), as: UTF8.self)
        _ = try decode(json); return json
    }
}

extension ClimbEntry {
    var pinnedNote: ClimbNote? { notebook.first { $0.id == pinnedNoteID } }
    var recentNotebook: [ClimbNote] { Array(notebook.filter { $0.id != pinnedNoteID }.sorted { $0.updatedAt > $1.updatedAt }.prefix(2)) }
}
