import Foundation

struct HealthHeartRateSample: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let beatsPerMinute: Double
}

/// Request status describes whether a permission sheet is needed, never whether read access was granted.
enum HealthReadAccessState: Equatable { case unavailable, needsRequest, requested }

enum HealthInsights {
    static func nonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }; return value
    }
    static func heartRate(_ value: Double?) -> Double? {
        guard let value = nonnegative(value), value > 0, value <= 300 else { return nil }; return value
    }
    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        // Divide before summing to avoid overflow when several finite values are very large.
        return values.reduce(0) { $0 + $1 / Double(values.count) }
    }
    /// Experimental, nonmedical effort estimate, not WHOOP strain or an individualized HR-zone model.
    /// D = min(duration / 7200 seconds, 1). H = clamp((average bpm - 60) / 120, 0...1).
    /// E = clamp(kcal / duration minutes / 12, 0...1). I = mean of available H/E.
    /// Score = round(10 * sqrt(D * I), to 1 decimal), on 0...10. Duration alone yields nil.
    /// Missing H/E is omitted, never treated as zero. Different input coverage affects comparability.
    static func effort(duration: TimeInterval?, averageHeartRate: Double?, activeCalories: Double?) -> Double? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        var intensities: [Double] = []
        if let heart = heartRate(averageHeartRate) { intensities.append(min(1, max(0, (heart - 60) / 120))) }
        if let calories = nonnegative(activeCalories) { intensities.append(min(1, calories / (duration / 60) / 12)) }
        guard let intensity = mean(intensities) else { return nil }
        return (100 * sqrt(min(1, duration / 7200) * intensity)).rounded() / 10
    }
}

struct HealthSessionInsight: Identifiable {
    let workout: HealthWorkout
    let samples: [HealthHeartRateSample]
    var id: UUID { workout.id }
    init(workout: HealthWorkout, samples: [HealthHeartRateSample]) {
        self.workout = workout
        self.samples = samples.filter {
            $0.date >= workout.start && $0.date <= workout.end && HealthInsights.heartRate($0.beatsPerMinute) != nil
        }.sorted { $0.date < $1.date }
    }
    var calories: Double? { HealthInsights.nonnegative(workout.energyKilocalories) }
    var averageHeartRate: Double? { HealthInsights.heartRate(workout.meanHeartRate) ?? HealthInsights.mean(samples.map(\.beatsPerMinute)) }
    var maximumHeartRate: Double? { HealthInsights.heartRate(workout.maximumHeartRate) ?? samples.map(\.beatsPerMinute).max() }
    var effort: Double? { HealthInsights.effort(duration: workout.duration, averageHeartRate: averageHeartRate, activeCalories: calories) }
    var durationMinutes: Double? { HealthInsights.nonnegative(workout.duration / 60) }
    /// Mean of a metric across other workouts in the 30 days before this one; nil when none has it.
    func thirtyDayAverage(of metric: KeyPath<Self, Double?>, among others: [Self]) -> Double? {
        let since = workout.start.addingTimeInterval(-30 * 86_400)
        return HealthInsights.mean(others.filter { $0.id != id && $0.workout.start >= since && $0.workout.start < workout.start }.compactMap { $0[keyPath: metric] })
    }
    /// Runs of samples with no gap over 10 minutes, so the chart never draws across missing data.
    var heartRateSegments: [[HealthHeartRateSample]] {
        samples.reduce(into: []) { segments, sample in
            if let last = segments.last?.last, sample.date.timeIntervalSince(last.date) <= 600 { segments[segments.count - 1].append(sample) }
            else { segments.append([sample]) }
        }
    }
}
