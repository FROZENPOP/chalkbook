import Foundation
import SwiftData

enum ClimbingSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [ClimbingSession.self, ClimbEntry.self, ClimbAttempt.self] }

    @Model
    final class ClimbingSession {
        @Attribute(.unique) var id: UUID
        var day: String
        var timeZoneID: String
        var location: String
        var notes: String
        var startedAt: Date
        var endedAt: Date?
        var isComplete: Bool
        @Relationship(deleteRule: .cascade, inverse: \ClimbEntry.session) var climbs: [ClimbEntry]

        init(id: UUID = UUID(), date: Date = .now, location: String = "", notes: String = "") {
            self.id = id
            day = SessionDay.key(for: date)
            timeZoneID = TimeZone.current.identifier
            self.location = location
            self.notes = notes
            startedAt = .now
            isComplete = false
            climbs = []
        }

        var title: String { location.isEmpty ? "Bouldering session" : location }
        var orderedClimbs: [ClimbEntry] { climbs.sorted { $0.createdAt < $1.createdAt } }
        var attemptCount: Int { climbs.reduce(0) { $0 + $1.attempts.count } }
        var sendCount: Int { climbs.reduce(0) { $0 + $1.sendCount } }
        var completedClimbs: Int { climbs.filter(\.isSent).count }
    }

    @Model
    final class ClimbEntry {
        @Attribute(.unique) var id: UUID
        var label: String
        var color: String
        var scaleRaw: String
        var grade: String
        var styles: [String]
        var priorRaw: String
        var notes: String
        var createdAt: Date
        var session: ClimbingSession?
        @Relationship(deleteRule: .cascade, inverse: \ClimbAttempt.climb) var attempts: [ClimbAttempt]

        init(id: UUID = UUID(), label: String = "", color: String = "", scale: GradeScale = .vScale,
             grade: String = "V0", styles: [String] = [], prior: PriorExperience = .unknown, notes: String = "") {
            self.id = id
            self.label = label
            self.color = color
            scaleRaw = scale.rawValue
            self.grade = grade
            self.styles = styles
            priorRaw = prior.rawValue
            self.notes = notes
            createdAt = .now
            attempts = []
        }

        var scale: GradeScale { GradeScale(rawValue: scaleRaw) ?? .vScale }
        var prior: PriorExperience { PriorExperience(rawValue: priorRaw) ?? .unknown }
        var orderedAttempts: [ClimbAttempt] { attempts.sorted { $0.sequence < $1.sequence } }
        var sendCount: Int { attempts.filter(\.sent).count }
        var isSent: Bool { sendCount > 0 }
        var isFlash: Bool { prior == .newClimb && orderedAttempts.first?.sent == true }
        var title: String { label.isEmpty ? (color.isEmpty ? "Boulder" : "\(color) boulder") : label }
        var resultLabel: String {
            if !isSent { return attempts.isEmpty ? "Ready to try" : "Working on it" }
            if prior == .sent { return "Repeat" }
            if isFlash { return "Flash" }
            if orderedAttempts.first?.sent == true { return "First try this session" }
            return "Sent"
        }
    }

    @Model
    final class ClimbAttempt {
        @Attribute(.unique) var id: UUID
        var sequence: Int
        var sent: Bool
        var recordedAt: Date
        var climb: ClimbEntry?

        init(id: UUID = UUID(), sequence: Int, sent: Bool, recordedAt: Date = .now) {
            self.id = id
            self.sequence = sequence
            self.sent = sent
            self.recordedAt = recordedAt
        }
    }
}
