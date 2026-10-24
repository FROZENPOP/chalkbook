import Foundation
import CryptoKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ClimbingBackup: Codable {
    static let maximumBytes = 150_000_000
    var version = 2
    var exportedAt = Date.now
    var defaultScale: GradeScale
    var sessions: [SessionRecord]
    var gyms: [GymRecord]? = nil

    struct GymRecord: Codable {
        var id: UUID
        var name: String
        var scale: GradeScale
        var customScaleName: String
        var customGrades: [String]
        var isDefault: Bool
    }

    struct MediaRecord: Codable {
        var id: UUID
        var kind: RouteMediaKind
        var filename: String
        var contentType: String
        var data: Data
        var checksum: String
    }

    struct SessionRecord: Codable {
        var id: UUID
        var day: String
        var timeZoneID: String
        var location: String
        var notes: String
        var startedAt: Date
        var endedAt: Date?
        var isComplete: Bool
        var climbs: [ClimbRecord]
        var gymID: UUID? = nil
    }

    struct ClimbRecord: Codable {
        var id: UUID
        var label: String
        var color: String
        var scale: GradeScale
        var grade: String
        var styles: [String]
        var prior: PriorExperience
        var notes: String
        var createdAt: Date
        var attempts: [AttemptRecord]
        var gymID: UUID? = nil
        var gymName: String? = nil
        var customScaleName: String? = nil
        var customGradeOrder: [String]? = nil
        var media: [MediaRecord]? = nil
    }

    struct AttemptRecord: Codable {
        var id: UUID
        var sequence: Int
        var sent: Bool
        var recordedAt: Date
    }

    var climbCount: Int { sessions.reduce(0) { $0 + $1.climbs.count } }

    @MainActor
    init(sessions: [ClimbingSession], defaultScale: GradeScale, gyms: [SavedGym] = []) {
        self.defaultScale = defaultScale
        self.gyms = gyms.map { GymRecord(id: $0.id, name: $0.name, scale: $0.scale, customScaleName: $0.customScaleName, customGrades: $0.customGrades, isDefault: $0.isDefault) }
        self.sessions = sessions.map { session in
            SessionRecord(id: session.id, day: session.day, timeZoneID: session.timeZoneID,
                          location: session.location, notes: session.notes, startedAt: session.startedAt,
                          endedAt: session.endedAt, isComplete: session.isComplete, climbs: session.orderedClimbs.map { climb in
                ClimbRecord(id: climb.id, label: climb.label, color: climb.color, scale: climb.scale,
                            grade: climb.grade, styles: climb.styles, prior: climb.prior, notes: climb.notes,
                            createdAt: climb.createdAt, attempts: climb.orderedAttempts.map {
                    AttemptRecord(id: $0.id, sequence: $0.sequence, sent: $0.sent, recordedAt: $0.recordedAt)
                }, gymID: climb.gymID, gymName: climb.gymName, customScaleName: climb.customScaleName,
                            customGradeOrder: climb.customGradeOrder, media: climb.media.map {
                    MediaRecord(id: $0.id, kind: $0.kind, filename: $0.filename, contentType: $0.contentType,
                                data: $0.data, checksum: Self.checksum($0.data))
                })
            }, gymID: session.gymID)
        }
    }

    func validated() throws -> Self {
        guard version == 1 || version == 2 else { throw BackupError.invalid("This backup version is not supported.") }
        guard sessions.filter({ !$0.isComplete }).count <= 1 else {
            throw BackupError.invalid("A backup can contain only one active session.")
        }
        var ids = Set<UUID>()
        func register(_ id: UUID) throws {
            guard ids.insert(id).inserted else { throw BackupError.invalid("The backup contains duplicate IDs.") }
        }
        let gyms = gyms ?? []
        guard gyms.filter(\.isDefault).count <= 1 else { throw BackupError.invalid("Only one gym can be the default.") }
        for gym in gyms {
            try register(gym.id)
            guard !gym.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  gym.scale != .custom || !gym.customScaleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  gym.customGrades == GymGrades.orderedLabels(from: gym.customGrades.joined(separator: "\n")) else {
                throw BackupError.invalid("The backup contains an invalid gym or grade order.")
            }
        }
        let gymIDs = Set(gyms.map(\.id))
        for session in sessions {
            if let gymID = session.gymID, !gymIDs.contains(gymID) { throw BackupError.invalid("A session refers to a missing gym.") }
            try register(session.id)
            guard SessionDay.date(for: session.day) != nil, TimeZone(identifier: session.timeZoneID) != nil,
                  session.isComplete == (session.endedAt != nil),
                  session.endedAt.map({ $0 >= session.startedAt }) ?? true else {
                throw BackupError.invalid("The backup contains an invalid session date or status.")
            }
            for climb in session.climbs {
                try register(climb.id)
                guard GymGrades.valid(grade: climb.grade, scale: climb.scale, customName: climb.customScaleName ?? ""),
                      climb.styles.allSatisfy({ value in ClimbStyle.allCases.contains { $0.rawValue == value } }) else {
                    throw BackupError.invalid("The backup contains an invalid grade or style.")
                }
                if let gymID = climb.gymID, !gymIDs.contains(gymID) { throw BackupError.invalid("A climb refers to a missing gym.") }
                let media = climb.media ?? []
                guard media.count <= RouteMediaDraft.maximumItems else { throw BackupError.invalid("A climb has too many attachments.") }
                for item in media {
                    try register(item.id)
                    try RouteMediaDraft(id: item.id, kind: item.kind, filename: item.filename, contentType: item.contentType, data: item.data).validate()
                    guard Self.checksum(item.data) == item.checksum else { throw BackupError.invalid("A route attachment is damaged.") }
                }
                let sequences = climb.attempts.map(\.sequence).sorted()
                guard sequences == Array(1..<(sequences.count + 1)) else {
                    throw BackupError.invalid("Attempt order is invalid.")
                }
                for attempt in climb.attempts { try register(attempt.id) }
            }
        }
        return self
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(validated())
        guard data.count <= Self.maximumBytes else { throw BackupError.invalid("This log exceeds the 150 MB JSON backup limit. Keep a separate copy of large route videos.") }
        return data
    }

    static func checksum(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= Self.maximumBytes else { throw BackupError.invalid("Choose a backup smaller than 150 MB.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: data).validated()
    }
}

enum BackupError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { message } else { nil } }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

extension ClimbingStore {
    @discardableResult
    func restore(_ backup: ClimbingBackup) -> Bool {
        let success = save {
            let validated = try backup.validated()
            let oldSessions = try context.fetch(FetchDescriptor<ClimbingSession>())
            let oldClimbs = try context.fetch(FetchDescriptor<ClimbEntry>())
            let oldAttempts = try context.fetch(FetchDescriptor<ClimbAttempt>())
            let oldGyms = try context.fetch(FetchDescriptor<SavedGym>())
            let oldMedia = try context.fetch(FetchDescriptor<RouteMedia>())
            let sessionsByID = Dictionary(uniqueKeysWithValues: oldSessions.map { ($0.id, $0) })
            let climbsByID = Dictionary(uniqueKeysWithValues: oldClimbs.map { ($0.id, $0) })
            let gymsByID = Dictionary(uniqueKeysWithValues: oldGyms.map { ($0.id, $0) })
            let mediaByID = Dictionary(uniqueKeysWithValues: oldMedia.map { ($0.id, $0) })
            let attemptsByID = Dictionary(uniqueKeysWithValues: oldAttempts.map { ($0.id, $0) })
            let sessionIDs = Set(validated.sessions.map(\.id))
            let climbIDs = Set(validated.sessions.flatMap(\.climbs).map(\.id))
            let attemptIDs = Set(validated.sessions.flatMap(\.climbs).flatMap(\.attempts).map(\.id))
            let gymIDs = Set((validated.gyms ?? []).map(\.id))
            let mediaIDs = Set(validated.sessions.flatMap(\.climbs).flatMap { $0.media ?? [] }.map(\.id))
            for record in validated.gyms ?? [] {
                let gym = gymsByID[record.id] ?? SavedGym(id: record.id, name: record.name)
                if gymsByID[record.id] == nil { context.insert(gym) }
                gym.name = record.name; gym.scaleRaw = record.scale.rawValue
                gym.customScaleName = record.customScaleName; gym.customGrades = record.customGrades
                gym.isDefault = record.isDefault
            }
            // Reuse matching identities to avoid unique-ID conflicts during replacement.
            // Apply the entire replacement in a single save, after full validation.
            for record in validated.sessions {
                let session = sessionsByID[record.id] ?? ClimbingSession(id: record.id)
                if sessionsByID[record.id] == nil { context.insert(session) }
                session.gymID = record.gymID
                session.location = record.location
                session.notes = record.notes
                session.day = record.day
                session.timeZoneID = record.timeZoneID
                session.startedAt = record.startedAt
                session.endedAt = record.endedAt
                session.isComplete = record.isComplete
                var climbs: [ClimbEntry] = []
                for item in record.climbs {
                    let climb = climbsByID[item.id] ?? ClimbEntry(id: item.id)
                    if climbsByID[item.id] == nil { context.insert(climb) }
                    climb.gymID = item.gymID; climb.gymName = item.gymName ?? ""
                    climb.customScaleName = item.customScaleName ?? ""; climb.customGradeOrder = item.customGradeOrder ?? []
                    climb.media = (item.media ?? []).map { record in
                        let media = mediaByID[record.id] ?? RouteMedia(id: record.id, kind: record.kind, filename: record.filename, contentType: record.contentType, data: record.data)
                        if mediaByID[record.id] == nil { context.insert(media) }
                        media.kindRaw = record.kind.rawValue; media.filename = record.filename
                        media.contentType = record.contentType; media.data = record.data
                        return media
                    }
                    climb.label = item.label
                    climb.color = item.color
                    climb.scaleRaw = item.scale.rawValue
                    climb.grade = item.grade
                    climb.styles = item.styles
                    climb.priorRaw = item.prior.rawValue
                    climb.notes = item.notes
                    climb.createdAt = item.createdAt
                    var attempts: [ClimbAttempt] = []
                    for entry in item.attempts {
                        let attempt = attemptsByID[entry.id] ?? ClimbAttempt(id: entry.id, sequence: entry.sequence, sent: entry.sent)
                        if attemptsByID[entry.id] == nil { context.insert(attempt) }
                        attempt.sequence = entry.sequence
                        attempt.sent = entry.sent
                        attempt.recordedAt = entry.recordedAt
                        attempts.append(attempt)
                    }
                    climb.attempts = attempts
                    climbs.append(climb)
                }
                session.climbs = climbs
            }
            for media in oldMedia where !mediaIDs.contains(media.id) { context.delete(media) }
            for gym in oldGyms where !gymIDs.contains(gym.id) { context.delete(gym) }
            for attempt in oldAttempts where !attemptIDs.contains(attempt.id) { context.delete(attempt) }
            for climb in oldClimbs where !climbIDs.contains(climb.id) { context.delete(climb) }
            for session in oldSessions where !sessionIDs.contains(session.id) { context.delete(session) }
        }
        if success { dataRevision += 1 }
        return success
    }
}
