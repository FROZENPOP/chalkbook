import Foundation

enum GradeScale: String, CaseIterable, Codable, Identifiable {
    case vScale = "V scale"
    case font = "Fontainebleau"
    case custom = "Custom scale"

    var id: String { rawValue }
    var grades: [String] {
        switch self {
        case .vScale: ["VB"] + (0...17).map { "V\($0)" }
        case .custom: []
        case .font: ["3", "4", "4+", "5", "5+", "6A", "6A+", "6B", "6B+", "6C", "6C+",
                     "7A", "7A+", "7B", "7B+", "7C", "7C+", "8A", "8A+", "8B", "8B+", "8C", "8C+", "9A"]
        }
    }
    func rank(of grade: String) -> Int? { grades.firstIndex(of: grade) }
}

enum PriorExperience: String, CaseIterable, Codable, Identifiable {
    case unknown = "Not sure"
    case newClimb = "Never tried"
    case attempted = "Tried before"
    case sent = "Sent before"
    var id: String { rawValue }
}

enum ClimbStyle: String, CaseIterable, Identifiable {
    case slab = "Slab", vertical = "Vertical", overhang = "Overhang"
    case crimps = "Crimps", slopers = "Slopers", power = "Power", balance = "Balance"
    var id: String { rawValue }
}

enum SessionDay {
    static func key(for date: Date, in timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func date(for key: String, in timeZone: TimeZone = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        guard let date = calendar.date(from: components), Self.key(for: date, in: timeZone) == key else { return nil }
        return date
    }

    static func label(for key: String) -> String {
        guard let date = date(for: key) else { return key }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
