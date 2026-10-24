import Foundation
import HealthKit

struct HealthWorkout: Identifiable, Equatable {
    let id: UUID
    let start: Date
    let end: Date
    let duration: TimeInterval
    let sourceName: String
    let sourceBundle: String
    let energyKilocalories: Double?
    let meanHeartRate: Double?
}

@MainActor
protocol HealthWorkoutReading {
    var available: Bool { get }
    func requestReadAccess() async throws
    func nearby(start: Date, end: Date) async throws -> [HealthWorkout]
    func workout(id: UUID) async throws -> HealthWorkout?
}

@MainActor
final class AppleHealthWorkouts: HealthWorkoutReading {
    private let store = HKHealthStore()
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    func requestReadAccess() async throws {
        guard available else { throw BackupError.invalid("Apple Health is unavailable on this device.") }
        let types: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)]
        try await store.requestAuthorization(toShare: [], read: types)
    }
    func nearby(start: Date, end: Date) async throws -> [HealthWorkout] {
        let dates = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-86400), end: end.addingTimeInterval(86400))
        let climbing = HKQuery.predicateForWorkouts(with: .climbing)
        return try await query(NSCompoundPredicate(andPredicateWithSubpredicates: [dates, climbing])).filter { $0.sourceBundle != Bundle.main.bundleIdentifier }
    }
    func workout(id: UUID) async throws -> HealthWorkout? { try await query(HKQuery.predicateForObject(with: id)).first }
    private func query(_ predicate: NSPredicate) async throws -> [HealthWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let workouts = (samples as? [HKWorkout] ?? []).map { workout in
                    HealthWorkout(id: workout.uuid, start: workout.startDate, end: workout.endDate, duration: workout.duration,
                        sourceName: workout.sourceRevision.source.name, sourceBundle: workout.sourceRevision.source.bundleIdentifier,
                        energyKilocalories: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                        meanHeartRate: workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }
}

enum HealthLinkRules {
    static func canLink(workoutID: UUID, to sessionID: UUID, existing: [(session: UUID, workout: UUID)]) -> Bool {
        !existing.contains { $0.workout == workoutID && $0.session != sessionID }
    }
    static func deduplicated(_ workouts: [HealthWorkout]) -> [HealthWorkout] {
        var seen = Set<UUID>(); return workouts.filter { seen.insert($0.id).inserted }
    }
    static func overlap(_ workout: HealthWorkout, start: Date, end: Date) -> TimeInterval {
        max(0, min(workout.end,end).timeIntervalSince(max(workout.start,start)))
    }
    static func hasSimilarCandidate(_ workout: HealthWorkout, among candidates: [HealthWorkout]) -> Bool {
        candidates.contains { $0.id != workout.id && ($0.sourceBundle == workout.sourceBundle || overlap($0,start:workout.start,end:workout.end) > 0) && abs($0.start.timeIntervalSince(workout.start)) < 600 }
    }
}
