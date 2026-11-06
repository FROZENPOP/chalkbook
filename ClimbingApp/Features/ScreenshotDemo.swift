#if DEBUG
import SwiftData
import Foundation

/// Realistic sample journal for App Store screenshots. Debug builds only, in the UI-test store.
@MainActor enum ScreenshotDemo {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--screenshot-demo") }

    static var startTab: Int {
        let args = ProcessInfo.processInfo.arguments
        guard enabled, let i = args.firstIndex(of: "--start-tab"), args.indices.contains(i + 1) else { return 0 }
        return Int(args[i + 1]) ?? 0
    }

    static func seed(_ context: ModelContext) throws {
        guard enabled, try context.fetchCount(FetchDescriptor<ClimbingSession>()) == 0 else { return }
        let gyms = [SavedGym(name: "Basalt Bouldering", isDefault: true), SavedGym(name: "Northside Wall")]
        gyms.forEach(context.insert)
        let routes: [(String, String, String, [ClimbStyle])] = [
            ("Pink pinches", "Pink", "V3", [.overhang, .power]), ("Yellow slab", "Yellow", "V2", [.slab, .balance]),
            ("Blue crimp line", "Blue", "V4", [.vertical, .crimps]), ("Green sloper traverse", "Green", "V5", [.slopers]),
            ("Black roof", "Black", "V6", [.overhang, .power]), ("Orange dyno", "Orange", "V4", [.power]),
            ("White arete", "White", "V3", [.balance]), ("Purple compression", "Purple", "V5", [.overhang, .slopers]),
            ("Red crimps", "Red", "V7", [.crimps, .vertical]), ("Teal mantle", "Teal", "V2", [.slab]),
        ]
        var rng = SystemRandomNumberGenerator()
        let day: TimeInterval = 86_400
        var climbs: [String: ClimbEntry] = [:]
        // About three sessions a week for ten weeks, harder sends later on.
        for index in 0..<30 {
            let ago = Double(70 - index * 7 / 3) * day - 18 * 3600
            let gym = gyms[index % 3 == 2 ? 1 : 0]
            let session = ClimbingSession(date: .now.addingTimeInterval(-ago), location: gym.name)
            session.gymID = gym.id; session.isComplete = true
            session.endedAt = session.startedAt.addingTimeInterval(Double(Int.random(in: 75...130, using: &rng)) * 60)
            context.insert(session)
            for (offset, route) in routes.shuffled(using: &rng).prefix(Int.random(in: 4...7, using: &rng)).enumerated() {
                // One entry per route and gym, carried across sessions like a real project.
                let key = gym.name + route.0
                let climb: ClimbEntry
                if let existing = climbs[key] {
                    climb = existing; session.linkedClimbs.append(climb)
                } else {
                    climb = ClimbEntry(label: route.0, color: route.1, grade: route.2, styles: route.3.map(\.rawValue))
                    climb.gymID = gym.id; climb.gymName = gym.name; climb.session = session; climb.createdAt = session.startedAt
                    session.climbs.append(climb); context.insert(climb); climbs[key] = climb
                }
                let level = Int(route.2.dropFirst())!
                let ready = level <= 3 + index / 10
                let tries = climb.isSent ? 1 : Int.random(in: 1...min(4, level - 1), using: &rng)
                if level >= 5 && !ready { climb.projectRaw = "active" }
                for step in 0..<tries {
                    let sequence = (climb.attempts.map(\.sequence).max() ?? -1) + 1
                    let attempt = ClimbAttempt(sequence: sequence, sent: (ready || climb.isSent) && step == tries - 1,
                                               recordedAt: session.startedAt.addingTimeInterval(Double(offset * 10 + step * 3) * 60))
                    attempt.climb = climb; attempt.sessionID = session.id; attempt.daySnapshot = session.day
                    attempt.gradeSnapshot = climb.descriptor.encoded
                    climb.attempts.append(attempt); context.insert(attempt)
                }
            }
        }
        try context.save()
    }
}
#endif
