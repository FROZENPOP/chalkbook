import Foundation

@MainActor enum HealthInsightsReaderFactory {
    static func make() -> any HealthWorkoutReading {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing") {
            return HealthInsightsFixtureReader(populated: arguments.contains("--health-insights-fixture"), empty: arguments.contains("--health-insights-empty"))
        }
        #endif
        return AppleHealthWorkouts()
    }
}

#if DEBUG
/// Isolated UI-test data, reachable only with --ui-testing. Never used for real accounts or Health reads.
@MainActor final class HealthInsightsFixtureReader: HealthWorkoutReading {
    static let workoutID = UUID(uuidString: "C7C3FA62-91FC-46AF-A0C6-65E4B3777901")!
    var available: Bool { populated }
    let populated: Bool
    let empty: Bool
    init(populated: Bool, empty: Bool = false) { self.populated = populated; self.empty = empty }
    func requestReadAccess() async throws {}
    func readAccessState(includeRecovery: Bool) async throws -> HealthReadAccessState { populated ? .requested : .unavailable }
    func nearby(start: Date, end: Date) async throws -> [HealthWorkout] { [] }
    func workout(id: UUID) async throws -> HealthWorkout? {
        guard populated, !empty, id == Self.workoutID else { return nil }
        let start = Date.now.addingTimeInterval(-7200)
        return HealthWorkout(id: id, start: start, end: start.addingTimeInterval(3600), duration: 3600, sourceName: "UI test watch", sourceBundle: "test.health", energyKilocalories: 432, meanHeartRate: 144, maximumHeartRate: 176)
    }
    func heartRates(workoutID: UUID) async throws -> [HealthHeartRateSample] {
        let start = Date.now.addingTimeInterval(-7200)
        return (0..<8).map { HealthHeartRateSample(id: UUID(), date: start.addingTimeInterval(Double($0) * 400 + 10), beatsPerMinute: Double(110 + $0 * 8)) }
    }
    func recoveryContext() async throws -> HealthRecoveryContext {
        if empty { return .init() }
        return .init(restingHeartRate: .init(value: 58, date: .now, source: "UI test watch"), hrvMilliseconds: .init(value: 54, date: .now, source: "UI test watch"))
    }
}
#endif
