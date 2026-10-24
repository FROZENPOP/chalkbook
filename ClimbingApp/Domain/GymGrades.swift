import Foundation

enum GymGrades {
    static func orderedLabels(from text: String) -> [String] {
        var seen = Set<String>()
        return text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    static func valid(grade: String, scale: GradeScale, customName: String) -> Bool {
        let grade = grade.trimmingCharacters(in: .whitespacesAndNewlines)
        if grade == "Ungraded" { return true }
        if scale == .custom {
            return !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !grade.isEmpty && grade.count <= 80
        }
        return scale.grades.contains(grade)
    }
}
