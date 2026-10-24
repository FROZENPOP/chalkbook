import Foundation

struct ClimbSnapshot {
    let scale: GradeScale
    let grade: String
    let attempts: Int
    let sends: Int
    var gymID: UUID? = nil
    var gymName = ""
    var customScaleName = ""
    var customOrder: [String] = []
}

struct GradeProgress: Identifiable {
    let grade: String
    let attempted: Int
    let completed: Int
    var id: String { grade }
    var rate: Double { attempted == 0 ? 0 : Double(completed) / Double(attempted) }
}

struct CustomScaleProgress: Identifiable {
    let id: String
    let title: String
    let grades: [GradeProgress]
}

struct ProgressSummary {
    let climbs: [ClimbSnapshot]
    var attempts: Int { climbs.reduce(0) { $0 + $1.attempts } }
    var sends: Int { climbs.reduce(0) { $0 + $1.sends } }
    var completed: Int { climbs.filter { $0.sends > 0 }.count }
    var attempted: Int { climbs.filter { $0.attempts > 0 }.count }
    var completionRate: Double? { attempted == 0 ? nil : Double(completed) / Double(attempted) }

    func highestSend(in scale: GradeScale) -> String? {
        climbs.filter { $0.scale == scale && $0.sends > 0 && scale.rank(of: $0.grade) != nil }
            .max { (scale.rank(of: $0.grade) ?? -1) < (scale.rank(of: $1.grade) ?? -1) }?.grade
    }

    var customScales: [CustomScaleProgress] {
        let custom = climbs.filter { $0.scale == .custom && $0.attempts > 0 }
        let groups = Dictionary(grouping: custom) { "\($0.gymID?.uuidString ?? $0.gymName)|\($0.customScaleName)" }
        return groups.keys.sorted().map { key in
            let matching = groups[key]!
            let first = matching[0]
            let order = matching.first { !$0.customOrder.isEmpty }?.customOrder ?? []
            let byGrade = Dictionary(grouping: matching, by: \.grade)
            let labels = byGrade.keys.sorted {
                let left = order.firstIndex(of: $0), right = order.firstIndex(of: $1)
                if let left, let right { return left < right }
                if left != nil { return true }
                if right != nil { return false }
                return $0.localizedStandardCompare($1) == .orderedAscending
            }
            return CustomScaleProgress(id: key, title: [first.gymName, first.customScaleName].filter { !$0.isEmpty }.joined(separator: " · "), grades: labels.map { grade in
                let entries = byGrade[grade]!
                return GradeProgress(grade: grade, attempted: entries.count, completed: entries.filter { $0.sends > 0 }.count)
            })
        }
    }

    func grades(in scale: GradeScale) -> [GradeProgress] {
        scale.grades.compactMap { grade in
            let matching = climbs.filter { $0.scale == scale && $0.grade == grade && $0.attempts > 0 }
            guard !matching.isEmpty else { return nil }
            return GradeProgress(grade: grade, attempted: matching.count, completed: matching.filter { $0.sends > 0 }.count)
        }
    }
}

extension ClimbEntry {
    var snapshot: ClimbSnapshot { ClimbSnapshot(scale: scale, grade: grade, attempts: attempts.count, sends: sendCount, gymID: gymID, gymName: gymName, customScaleName: customScaleName, customOrder: customGradeOrder) }
}
