import Foundation
import SwiftData

enum ClimbingSchemaV8: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }
    static var models: [any PersistentModel.Type] { [ClimbingSession.self, ClimbEntry.self, ClimbAttempt.self, SavedGym.self, RouteMedia.self, AggregateEntry.self, ClimbNote.self, HealthWorkoutLink.self] }

    @Model
    final class ClimbingSession {
        @Attribute(.unique) var id: UUID
        var day: String
        var timeZoneID: String
        var location: String
        var gymID: UUID? = nil
        var notes: String
        var startedAt: Date
        var endedAt: Date?
        var isComplete: Bool
        @Relationship(deleteRule: .nullify, inverse: \ClimbEntry.session) var climbs: [ClimbEntry]

        var createdAt: Date = Date.distantPast
        var updatedAt: Date = Date.distantPast
        var durationKnown: Bool = true
        var pausedAt: Date? = nil
        var pausedSeconds: Double = 0
        var selectedClimbID: UUID? = nil
        @Relationship(deleteRule: .nullify, inverse: \ClimbEntry.sessions) var linkedClimbs: [ClimbEntry] = []
        @Relationship(deleteRule: .cascade, inverse: \AggregateEntry.session) var aggregates: [AggregateEntry] = []
        var shareVisibility: String? = nil // nil: made before share settings existed, nothing chosen yet
        var shareCaption: String = ""
        var shareAttempts: Bool = true
        var shareSends: Bool = true
        var shareDuration: Bool = true
        var sharePhotos: Bool = true

        init(id: UUID = UUID(), date: Date = .now, location: String = "", notes: String = "") {
            self.id = id
            day = SessionDay.key(for: date)
            timeZoneID = TimeZone.current.identifier
            self.location = location
            self.notes = notes
            startedAt = date
            createdAt = .now; updatedAt = .now
            isComplete = false
            climbs = []
        }

        var title: String { location.isEmpty ? "Bouldering session" : location }
        var visibility: EntryVisibility? {
            get { shareVisibility.flatMap(EntryVisibility.init(rawValue:)) }
            set { shareVisibility = newValue?.rawValue }
        }
        var allClimbs: [ClimbEntry] {
            var seen = Set<UUID>()
            return (climbs + linkedClimbs).filter { seen.insert($0.id).inserted }
        }
        var orderedClimbs: [ClimbEntry] { allClimbs.sorted { $0.createdAt < $1.createdAt } }
        var recordedAttempts: [ClimbAttempt] { allClimbs.flatMap(\.attempts).filter { $0.effectiveSessionID == id } }
        var totals: ActivityTotals { totals(recordedAttempts) }
        // Takes the attempts so callers walk the relationships once; that walk dominates large journals.
        private func totals(_ recorded: [ClimbAttempt]) -> ActivityTotals { JournalRules.totals(detailedAttempts: recorded.count, detailedSends: recorded.filter(\.sent).count, batches: aggregates.map(\.batch)) }
        var durationMinutes: Int? { guard durationKnown, let endedAt else { return nil }; return max(0, Int((endedAt.timeIntervalSince(startedAt) - pausedSeconds) / 60)) }
        var isPaused: Bool { pausedAt != nil }
        // Shifting the start by the paused time lets the stopwatch run from a plain date.
        var stopwatchStart: Date { startedAt.addingTimeInterval(pausedSeconds) }
        func endPause() {
            guard let pausedAt else { return }
            pausedSeconds += max(0, Date.now.timeIntervalSince(pausedAt))
            self.pausedAt = nil
        }
        var attemptCount: Int { let recorded = recordedAttempts; return totals(recorded).attempts ?? recorded.count }
        var sendCount: Int { let recorded = recordedAttempts; return totals(recorded).sends ?? recorded.filter(\.sent).count }
        var completedClimbs: Int { Set(recordedAttempts.filter(\.sent).compactMap { $0.climb?.id }).count }
    }

    @Model
    final class ClimbEntry {
        @Attribute(.unique) var id: UUID
        var pinnedNoteID: UUID? = nil
        var label: String
        var color: String
        var scaleRaw: String
        var gymID: UUID? = nil
        var gymName: String = ""
        var colorGuide: String = ""
        var customScaleName: String = ""
        var customGradeOrder: [String] = []
        var grade: String
        var styles: [String]
        var priorRaw: String
        var notes: String
        var createdAt: Date
        var session: ClimbingSession?
        var sessions: [ClimbingSession] = []
        var updatedAt: Date = Date.distantPast
        var projectRaw: String = ""
        var historyIncomplete: Bool = false
        var gradeKindRaw: String = "exact"
        var gradeUpper: String = ""
        @Relationship(deleteRule: .cascade, inverse: \ClimbNote.climb) var notebook: [ClimbNote] = []
        @Relationship(deleteRule: .cascade, inverse: \ClimbAttempt.climb) var attempts: [ClimbAttempt]

        @Relationship(deleteRule: .cascade, inverse: \RouteMedia.climb) var media: [RouteMedia] = []

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
            createdAt = .now; updatedAt = .now
            attempts = []
        }

        var scale: GradeScale { GradeScale(rawValue: scaleRaw) ?? .vScale }
        var prior: PriorExperience { PriorExperience(rawValue: priorRaw) ?? .unknown }
        var orderedAttempts: [ClimbAttempt] { attempts.sorted {
            if $0.sessionDay != $1.sessionDay { return $0.sessionDay < $1.sessionDay }
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.id.uuidString < $1.id.uuidString
        } }
        var descriptor: GradeDescriptor { GradeDescriptor(kind: GradeKind(rawValue: gradeKindRaw) ?? .exact, scale: scale, grade: grade, upper: gradeUpper, color: color, gymID: gymID, gymName: gymName, customScale: customScaleName, colorGuide: colorGuide) }
        var flash: FlashAssessment { JournalRules.flash(prior: prior, historyIncomplete: historyIncomplete, outcomes: orderedAttempts.map(\.sent)) }
        var projectStatus: String { projectRaw == "archived" ? "archived" : (isSent || prior == .sent ? "sent" : projectRaw) }
        var sendCount: Int { attempts.filter(\.sent).count }
        var isSent: Bool { sendCount > 0 }
        var isFlash: Bool { flash.state == .confirmed }
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
        var sessionID: UUID? = nil
        var daySnapshot: String = ""
        var gradeSnapshot: String = ""
        var timePrecision: String = "exact"
        var updatedAt: Date = Date.distantPast
        var effectiveSessionID: UUID? { sessionID ?? climb?.session?.id }
        var sessionDay: String { daySnapshot.isEmpty ? (climb?.session?.day ?? SessionDay.key(for: recordedAt)) : daySnapshot }

        init(id: UUID = UUID(), sequence: Int, sent: Bool, recordedAt: Date = .now) {
            self.id = id
            self.sequence = sequence
            self.sent = sent
            self.recordedAt = recordedAt; updatedAt = .now
        }
    }

    @Model
    final class SavedGym {
        @Attribute(.unique) var id: UUID
        var name: String
        var address: String = ""
        var scaleRaw: String
        var customScaleName: String
        var customGrades: [String]
        var isDefault: Bool
        var colorGuide: String = ""
        var createdAt: Date = Date.distantPast
        var updatedAt: Date = Date.distantPast

        init(id: UUID = UUID(), name: String, scale: GradeScale = .vScale,
             customScaleName: String = "", customGrades: [String] = [], isDefault: Bool = false) {
            self.id = id
            self.name = name
            scaleRaw = scale.rawValue
            self.customScaleName = customScaleName
            self.customGrades = customGrades
            self.isDefault = isDefault; createdAt = .now; updatedAt = .now
        }
        var scale: GradeScale { GradeScale(rawValue: scaleRaw) ?? .vScale }
        var menuLabel: String { address.isEmpty ? name : name + " · " + address }
        var scaleLabel: String { scale == .custom ? customScaleName : scale.rawValue }
    }

    @Model
    final class RouteMedia {
        @Attribute(.unique) var id: UUID
        var annotationJSON: String = ""
        var kindRaw: String
        var filename: String
        var contentType: String
        var createdAt: Date = Date.distantPast
        var updatedAt: Date = Date.distantPast
        @Attribute(.externalStorage) var data: Data
        var climb: ClimbEntry?

        init(id: UUID = UUID(), kind: RouteMediaKind, filename: String, contentType: String, data: Data) {
            self.id = id
            kindRaw = kind.rawValue
            self.filename = filename
            self.contentType = contentType
            self.data = data; createdAt = .now; updatedAt = .now
        }
        var kind: RouteMediaKind { RouteMediaKind(rawValue: kindRaw) ?? .photo }
    }

    @Model
    final class HealthWorkoutLink {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var sessionID: UUID
        @Attribute(.unique) var workoutID: UUID
        var sourceName: String
        var sourceBundle: String
        var linkedAt: Date
        init(sessionID: UUID, workoutID: UUID, sourceName: String, sourceBundle: String) {
            id = UUID(); self.sessionID = sessionID; self.workoutID = workoutID
            self.sourceName = sourceName; self.sourceBundle = sourceBundle; linkedAt = .now
        }
    }
    @Model
    final class AggregateEntry {
        @Attribute(.unique) var id: UUID
        var coverage: String
        var attempts: Int?
        var sends: Int?
        var label: String
        var createdAt: Date
        var updatedAt: Date
        var session: ClimbingSession?
        init(id: UUID = UUID(), coverage: String, attempts: Int?, sends: Int?, label: String = "") {
            self.id = id; self.coverage = coverage; self.attempts = attempts; self.sends = sends
            self.label = label; createdAt = .now; updatedAt = .now
        }
        var batch: ActivityBatch { ActivityBatch(coverage: ActivityCoverage(rawValue: coverage) ?? .additional, attempts: attempts, sends: sends) }
    }
    @Model
    final class ClimbNote {
        @Attribute(.unique) var id: UUID
        var text: String
        var createdAt: Date
        var updatedAt: Date
        var sessionID: UUID?
        var climb: ClimbEntry?
        init(id: UUID = UUID(), text: String, sessionID: UUID? = nil) {
            self.id = id; self.text = text; self.sessionID = sessionID; createdAt = .now; updatedAt = .now
        }
    }

}

typealias ClimbingSession = ClimbingSchemaV8.ClimbingSession
typealias ClimbEntry = ClimbingSchemaV8.ClimbEntry
typealias ClimbAttempt = ClimbingSchemaV8.ClimbAttempt
typealias SavedGym = ClimbingSchemaV8.SavedGym
typealias RouteMedia = ClimbingSchemaV8.RouteMedia

typealias HealthWorkoutLink = ClimbingSchemaV8.HealthWorkoutLink
typealias AggregateEntry = ClimbingSchemaV8.AggregateEntry
typealias ClimbNote = ClimbingSchemaV8.ClimbNote

enum ClimbingMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ClimbingSchemaV1.self, ClimbingSchemaV2.self, ClimbingSchemaV3.self, ClimbingSchemaV4.self, ClimbingSchemaV5.self, ClimbingSchemaV6.self, ClimbingSchemaV7.self, ClimbingSchemaV8.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: ClimbingSchemaV1.self, toVersion: ClimbingSchemaV2.self), .lightweight(fromVersion: ClimbingSchemaV2.self, toVersion: ClimbingSchemaV3.self), .custom(fromVersion: ClimbingSchemaV3.self, toVersion: ClimbingSchemaV4.self, willMigrate: nil, didMigrate: { context in
        for climb in try context.fetch(FetchDescriptor<ClimbingSchemaV4.ClimbEntry>()) {
            for attempt in climb.attempts {
                if attempt.sessionID == nil { attempt.sessionID = climb.session?.id }
                if attempt.daySnapshot.isEmpty { attempt.daySnapshot = climb.session?.day ?? SessionDay.key(for: attempt.recordedAt) }
                if attempt.gradeSnapshot.isEmpty { attempt.gradeSnapshot = climb.descriptor.encoded }
            }
        }
        try context.save()
    }), .lightweight(fromVersion: ClimbingSchemaV4.self, toVersion: ClimbingSchemaV5.self), .lightweight(fromVersion: ClimbingSchemaV5.self, toVersion: ClimbingSchemaV6.self), .lightweight(fromVersion: ClimbingSchemaV6.self, toVersion: ClimbingSchemaV7.self), .lightweight(fromVersion: ClimbingSchemaV7.self, toVersion: ClimbingSchemaV8.self)] }
}

@MainActor
enum Persistence {
    static func container(inMemory: Bool = false, accountKey: String? = nil, rootDirectory: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: ClimbingSchemaV8.self)
        let configuration: ModelConfiguration
        if let accountKey, !inMemory {
            guard accountKey.count == 64, accountKey.allSatisfy({ "0123456789abcdef".contains($0) }) else {
                throw BackupError.invalid("The account storage identifier is invalid.")
            }
            let directory = (rootDirectory ?? URL.applicationSupportDirectory).appending(path: "Accounts").appending(path: accountKey)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: schema, url: directory.appending(path: "Climbing.store"), cloudKitDatabase: .none)
        } else if let rootDirectory, !inMemory {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: schema, url: rootDirectory.appending(path: "Guest.store"), cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        let container = try ModelContainer(for: schema, migrationPlan: ClimbingMigrationPlan.self, configurations: [configuration])
        container.mainContext.autosaveEnabled = false
        #if os(iOS)
        if !inMemory {
            // SwiftData owns transactional external blobs; protect their containing directory too.
            let directory = configuration.url.deletingLastPathComponent()
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: configuration.url.path)
        }
        #endif
        return container
    }
}
