import Foundation

struct DifficultyDistribution: Identifiable {
    var id: String
    var label: String
    var attempts: Int
    var sends: Int
}
struct JournalStatistics {
    let sessions: [ClimbingSession]
    var attempts: [ClimbAttempt] { sessions.flatMap(\.recordedAttempts) }
    var distinctClimbsSent: Int { Set(attempts.filter(\.sent).compactMap { $0.climb?.id }).count }
    var distinctClimbsAttempted: Int { Set(attempts.compactMap { $0.climb?.id }).count }
    var knownAttempts: Int? { let totals = sessions.map { $0.totals.attempts }; return totals.contains(where: { $0 == nil }) ? nil : totals.compactMap { $0 }.reduce(0,+) }
    var knownSends: Int? { let totals = sessions.map { $0.totals.sends }; return totals.contains(where: { $0 == nil }) ? nil : totals.compactMap { $0 }.reduce(0,+) }
    var recordedMinutes: Int { sessions.compactMap(\.durationMinutes).reduce(0,+) }
    var durationCount: Int { sessions.filter { $0.durationMinutes != nil }.count }
    var recalledSessions: Int { sessions.filter { !$0.aggregates.isEmpty }.count }
    var flashAssessments: [FlashAssessment] {
        var seen = Set<UUID>()
        let climbs = attempts.filter(\.sent).compactMap(\.climb).filter { seen.insert($0.id).inserted }
        return climbs.map(\.flash)
    }
    var confirmedFlashes: Int { flashAssessments.filter { $0.state == .confirmed }.count }
    var knownFlashDenominator: Int { flashAssessments.filter { $0.state != .unknown }.count }
    var unknownFlashCount: Int { flashAssessments.filter { $0.state == .unknown }.count }
    func distributions(in scale: GradeScale) -> [DifficultyDistribution] {
        var groups: [String: DifficultyDistribution] = [:]
        for attempt in attempts {
            let descriptor = attempt.gradeSnapshot.data(using: .utf8).flatMap { try? JSONDecoder().decode(GradeDescriptor.self, from: $0) } ?? attempt.climb?.descriptor
            guard let descriptor, descriptor.scale == scale else { continue }
            let colorBased = descriptor.kind == .color || descriptor.kind == .colorRange || scale == .custom
            let context = colorBased ? [descriptor.gymID?.uuidString ?? descriptor.gymName, descriptor.customScale].joined(separator:"|") : scale.rawValue
            let key = context + "|" + descriptor.kind.rawValue + "|" + descriptor.label
            let label = colorBased ? [descriptor.gymName,descriptor.customScale,descriptor.label].filter { !$0.isEmpty }.joined(separator:" · ") : descriptor.label
            var entry = groups[key] ?? DifficultyDistribution(id:key,label:label,attempts:0,sends:0)
            entry.attempts += 1; if attempt.sent { entry.sends += 1 }; groups[key] = entry
        }
        return groups.values.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
}
