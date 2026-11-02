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
    var maximumHeartRate: Double? = nil
}

@MainActor
protocol HealthWorkoutReading {
    var available: Bool { get }
    func requestReadAccess() async throws
    func nearby(start: Date, end: Date) async throws -> [HealthWorkout]
    func workout(id: UUID) async throws -> HealthWorkout?
    func readAccessState() async throws -> HealthReadAccessState
    func heartRates(workoutID: UUID) async throws -> [HealthHeartRateSample]
}

extension HealthWorkoutReading {
    func readAccessState() async throws -> HealthReadAccessState { available ? .needsRequest : .unavailable }
    func heartRates(workoutID: UUID) async throws -> [HealthHeartRateSample] { [] }
}

@MainActor
final class AppleHealthWorkouts: HealthWorkoutReading {
    private let store = HKHealthStore()
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    private var readTypes: Set<HKObjectType> { [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)] }
    func requestReadAccess() async throws {
        guard available else { throw BackupError.invalid("Apple Health is unavailable on this device.") }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }
    func readAccessState() async throws -> HealthReadAccessState {
        guard available else { return .unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: status == .unnecessary ? .requested : .needsRequest) }
            }
        }
    }
    func heartRates(workoutID: UUID) async throws -> [HealthHeartRateSample] {
        guard let workout = try await rawWorkouts(HKQuery.predicateForObject(with: workoutID)).first else { return [] }
        // Only samples explicitly associated with this workout. Never query unrelated overlapping samples.
        let samples = try await quantities(type: HKQuantityType(.heartRate), predicate: HKQuery.predicateForObjects(from: workout))
        let unit = HKUnit.count().unitDivided(by: .minute())
        return samples.map { HealthHeartRateSample(id: $0.uuid, date: $0.startDate, beatsPerMinute: $0.quantity.doubleValue(for: unit)) }
    }
    private func quantities(type: HKQuantityType, predicate: NSPredicate) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples as? [HKQuantitySample] ?? []) }
            }
            store.execute(query)
        }
    }
    func nearby(start: Date, end: Date) async throws -> [HealthWorkout] {
        let dates = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-86400), end: end.addingTimeInterval(86400))
        let climbing = HKQuery.predicateForWorkouts(with: .climbing)
        return try await query(NSCompoundPredicate(andPredicateWithSubpredicates: [dates, climbing])).filter { $0.sourceBundle != Bundle.main.bundleIdentifier }
    }
    func workout(id: UUID) async throws -> HealthWorkout? { try await query(HKQuery.predicateForObject(with: id)).first }
    private func query(_ predicate: NSPredicate) async throws -> [HealthWorkout] {
        try await rawWorkouts(predicate).map { workout in
            let heart = workout.statistics(for: HKQuantityType(.heartRate))
            let unit = HKUnit.count().unitDivided(by: .minute())
            return HealthWorkout(id: workout.uuid, start: workout.startDate, end: workout.endDate, duration: workout.duration,
                sourceName: workout.sourceRevision.source.name, sourceBundle: workout.sourceRevision.source.bundleIdentifier,
                energyKilocalories: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                meanHeartRate: heart?.averageQuantity()?.doubleValue(for: unit), maximumHeartRate: heart?.maximumQuantity()?.doubleValue(for: unit))
        }
    }
    private func rawWorkouts(_ predicate: NSPredicate) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples as? [HKWorkout] ?? []) }
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
