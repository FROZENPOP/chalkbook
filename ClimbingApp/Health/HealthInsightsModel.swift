import Foundation
import Observation

@MainActor @Observable
final class HealthInsightsModel {
    private let reader: any HealthWorkoutReading
    private var generation = 0
    private(set) var loading = false
    private(set) var sessions: [HealthSessionInsight] = []
    private(set) var recovery = HealthRecoveryContext()
    private(set) var message: String?
    private(set) var access = HealthReadAccessState.needsRequest
    private(set) var unavailableWorkouts = 0

    init(reader: any HealthWorkoutReading) { self.reader = reader; access = reader.available ? .needsRequest : .unavailable }
    func clear() {
        generation += 1; loading = false; sessions = []; recovery = .init(); message = nil; unavailableWorkouts = 0
    }
    func load(ids: [UUID], requestAccess: Bool, includeRecovery: Bool) async {
        clear(); let revision = generation; loading = true
        defer { if generation == revision { loading = false } }
        do {
            guard reader.available else { access = .unavailable; message = "Apple Health is unavailable on this device."; return }
            if requestAccess { try await reader.requestReadAccess(includeRecovery: includeRecovery) }
            try Task.checkCancellation()
            let state = try await reader.readAccessState(includeRecovery: includeRecovery)
            guard generation == revision else { return }
            access = state
            guard state == .requested else {
                message = state == .unavailable ? "Apple Health is unavailable on this device." : "Choose Connect Health to review read access. Nothing is requested automatically."
                return
            }
            var loaded: [HealthSessionInsight] = [], missing = 0, partial = false
            for id in Set(ids) {
                try Task.checkCancellation()
                do {
                    guard let workout = try await reader.workout(id: id), workout.id == id else { missing += 1; continue }
                    guard generation == revision, !Task.isCancelled else { return }
                    var samples: [HealthHeartRateSample] = []
                    do { samples = try await reader.heartRates(workoutID: id) } catch is CancellationError { throw CancellationError() }
                    catch { partial = true }
                    loaded.append(HealthSessionInsight(workout: workout, samples: samples))
                } catch is CancellationError { throw CancellationError() }
                catch { missing += 1; partial = true }
            }
            guard generation == revision, !Task.isCancelled else { return }
            var context = HealthRecoveryContext()
            if includeRecovery {
                do { context = try await reader.recoveryContext().sanitized } catch is CancellationError { throw CancellationError() }
                catch { partial = true }
            }
            try Task.checkCancellation()
            guard generation == revision else { return }
            sessions = loaded.sorted { $0.workout.start < $1.workout.start }; recovery = context; unavailableWorkouts = missing
            if partial { message = "Some Health data couldn’t refresh. Available measurements are shown; retry when the device is unlocked." }
            else if loaded.isEmpty { message = ids.isEmpty ? "No linked workouts in this journal range. Link a workout from a session to see its insights." : "No accessible data found. Read access decisions are private to Apple Health; data may also be missing or delayed." }
        } catch is CancellationError { }
        catch {
            guard generation == revision else { return }
            message = "Couldn’t read accessible Health data. Retry when the device is unlocked, or review access in Apple Health."
        }
    }
}
