import Foundation

struct RoutePoint: Codable, Equatable { var x: Double; var y: Double }
struct RouteStroke: Codable, Equatable {
    var color: String
    var points: [RoutePoint]
}
enum RouteAnnotations {
    static func decode(_ json: String) throws -> [RouteStroke] {
        if json.isEmpty { return [] }
        guard json.utf8.count <= 500_000 else { throw BackupError.invalid("The route markup is too large.") }
        let strokes = try JSONDecoder().decode([RouteStroke].self, from: Data(json.utf8))
        guard strokes.count <= 200, strokes.allSatisfy({ stroke in
            ["orange","blue","white"].contains(stroke.color) && (1...2000).contains(stroke.points.count) && stroke.points.allSatisfy {
                $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)
            }
        }) else { throw BackupError.invalid("The route markup contains invalid points.") }
        return strokes
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
