import Foundation
import Observation

@MainActor @Observable
final class HealthInsightsModel {
    private let reader: any HealthWorkoutReading
    private var generation = 0
    private(set) var loading = false
    private(set) var sessions: [HealthSessionInsight] = []
    private(set) var message: String?
    private(set) var access = HealthReadAccessState.needsRequest

    init(reader: any HealthWorkoutReading) { self.reader = reader; access = reader.available ? .needsRequest : .unavailable }
    func clear() {
        generation += 1; loading = false; sessions = []; message = nil
    }
    /// Comparison workouts need only their summaries, so `samplesFor` limits the costly heart-rate read to one workout.
    func load(ids: [UUID], requestAccess: Bool, samplesFor: UUID? = nil) async {
        clear(); let revision = generation; loading = true
        defer { if generation == revision { loading = false } }
        do {
            guard reader.available else { access = .unavailable; message = "Apple Health is unavailable on this device."; return }
            if requestAccess { try await reader.requestReadAccess() }
            try Task.checkCancellation()
            let state = try await reader.readAccessState()
            guard generation == revision else { return }
            access = state
            guard state == .requested else {
                if state == .unavailable { message = "Apple Health is unavailable on this device." }
                return
            }
            var loaded: [HealthSessionInsight] = [], partial = false
            for id in Set(ids) {
                try Task.checkCancellation()
                do {
                    guard let workout = try await reader.workout(id: id), workout.id == id else { continue }
                    guard generation == revision, !Task.isCancelled else { return }
                    var samples: [HealthHeartRateSample] = []
                    if samplesFor == nil || samplesFor == id {
                        do { samples = try await reader.heartRates(workoutID: id) } catch is CancellationError { throw CancellationError() }
                        catch { partial = true }
                    }
                    loaded.append(HealthSessionInsight(workout: workout, samples: samples))
                } catch is CancellationError { throw CancellationError() }
                catch { partial = true }
            }
            guard generation == revision, !Task.isCancelled else { return }
            try Task.checkCancellation()
            guard generation == revision else { return }
            sessions = loaded.sorted { $0.workout.start < $1.workout.start }
            if partial { message = "Some Health data couldn’t load." }
            else if !loaded.contains(where: { samplesFor == nil || $0.id == samplesFor }) { message = "No accessible data found." }
        } catch is CancellationError { }
        catch {
            guard generation == revision else { return }
            message = "Couldn’t read Apple Health."
        }
    }
}
