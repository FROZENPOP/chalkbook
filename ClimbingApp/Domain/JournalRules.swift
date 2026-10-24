import Foundation

enum GradeKind: String, Codable, CaseIterable, Identifiable {
    case exact, range, color, colorRange, unknown
    var id: String { rawValue }
    var title: String {
        switch self { case .exact: "Exact grade"; case .range: "Grade range"; case .color: "Gym color"; case .colorRange: "Color and range"; case .unknown: "Unknown" }
    }
}
struct GradeDescriptor: Codable, Equatable {
    var kind: GradeKind
    var scale: GradeScale
    var grade: String
    var upper: String
    var color: String
    var gymID: UUID?
    var gymName: String
    var customScale: String
    var colorGuide: String? = nil
    var label: String {
        switch kind {
        case .unknown: return "Unknown grade"
        case .color: return color.isEmpty ? "Unknown color" : color
        case .range: return "\(grade)–\(upper)"
        case .colorRange: return "\(color) · \(grade)–\(upper)"
        case .exact: return grade
        }
    }
    var encoded: String { (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
}
enum FlashState: String { case confirmed, notFlash, unknown }
struct FlashAssessment { let state: FlashState; let reason: String }
enum ActivityCoverage: String, Codable, CaseIterable, Identifiable {
    case additional, wholeSession
    var id: String { rawValue }
    var title: String { self == .additional ? "Additional unlogged activity" : "Whole-session totals" }
}
struct ActivityBatch { var coverage: ActivityCoverage; var attempts: Int?; var sends: Int? }
struct ActivityTotals {
    var attempts: Int?
    var sends: Int?
    var conflicts: [String]
    var hasRecalledActivity: Bool
    var label: String { hasRecalledActivity ? "Recorded and recalled activity" : "Recorded activity only; unlogged activity unknown" }
}
enum JournalRules {
    static func flash(prior: PriorExperience, historyIncomplete: Bool, outcomes: [Bool]) -> FlashAssessment {
        guard let firstSend = outcomes.firstIndex(of: true) else { return FlashAssessment(state: .unknown, reason: "No recorded send") }
        if firstSend > 0 || prior == .attempted || prior == .sent { return FlashAssessment(state: .notFlash, reason: "Earlier attempts or completion are known") }
        guard prior == .newClimb, !historyIncomplete else { return FlashAssessment(state: .unknown, reason: historyIncomplete ? "Earlier records were removed; history is incomplete" : "Prior history is unknown") }
        return FlashAssessment(state: .confirmed, reason: "Declared never tried; first lifetime recorded attempt was a send")
    }
    static func totals(detailedAttempts: Int, detailedSends: Int, batches: [ActivityBatch]) -> ActivityTotals {
        var conflicts: [String] = []
        let additional = batches.filter { $0.coverage == .additional }
        let whole = batches.filter { $0.coverage == .wholeSession }
        for b in batches {
            if b.attempts == nil && b.sends == nil { conflicts.append("Enter at least one remembered total.") }
            if (b.attempts ?? 0) < 0 || (b.sends ?? 0) < 0 { conflicts.append("Totals cannot be negative.") }
            if let a = b.attempts, let s = b.sends, s > a { conflicts.append("Sends cannot exceed attempts in the same activity.") }
        }
        let knownA = detailedAttempts + additional.compactMap(\.attempts).reduce(0,+)
        let knownS = detailedSends + additional.compactMap(\.sends).reduce(0,+)
        let wholeA = whole.compactMap(\.attempts), wholeS = whole.compactMap(\.sends)
        if wholeA.count > 1 || wholeS.count > 1 { conflicts.append("Only one whole-session total per metric is allowed.") }
        if let a = wholeA.first, a < knownA { conflicts.append("Whole-session attempts are below recorded and additional evidence (\(knownA)).") }
        if let s = wholeS.first, s < knownS { conflicts.append("Whole-session sends are below recorded and additional evidence (\(knownS)).") }
        let attempts: Int? = wholeA.first ?? (additional.contains { $0.attempts == nil } || whole.contains { $0.attempts == nil && $0.sends != nil } ? nil : knownA)
        let sends: Int? = wholeS.first ?? (additional.contains { $0.sends == nil } || whole.contains { $0.sends == nil && $0.attempts != nil } ? nil : knownS)
        if let attempts, let sends, sends > attempts { conflicts.append("Session sends exceed known attempts. Correct the totals or leave attempts unknown.") }
        return ActivityTotals(attempts: attempts, sends: sends, conflicts: conflicts, hasRecalledActivity: !batches.isEmpty)
    }
}
