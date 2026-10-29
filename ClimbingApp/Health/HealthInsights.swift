import Foundation

struct HealthHeartRateSample: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let beatsPerMinute: Double
}

struct HealthQuantityReading: Equatable {
    let value: Double
    let date: Date
    let source: String
}

struct HealthRecoveryContext: Equatable {
    var restingHeartRate: HealthQuantityReading?
    var hrvMilliseconds: HealthQuantityReading?
    var hasData: Bool { restingHeartRate != nil || hrvMilliseconds != nil }
    var sanitized: Self {
        Self(restingHeartRate: restingHeartRate.flatMap { HealthInsights.heartRate($0.value) == nil ? nil : $0 },
             hrvMilliseconds: hrvMilliseconds.flatMap { HealthInsights.nonnegative($0.value).map { $0 > 0 } == true ? $0 : nil })
    }
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
    var maximumFromSamples: Bool { HealthInsights.heartRate(workout.maximumHeartRate) == nil && !samples.isEmpty }
    var averageFromSamples: Bool { HealthInsights.heartRate(workout.meanHeartRate) == nil && !samples.isEmpty }
    var effort: Double? { HealthInsights.effort(duration: workout.duration, averageHeartRate: averageHeartRate, activeCalories: calories) }
    var inputs: String {
        var labels = ["duration"]
        if averageHeartRate != nil { labels.append("average heart rate") }
        if calories != nil { labels.append("active energy") }
        return labels.joined(separator: " + ")
    }
}

struct HealthInsightWeek: Identifiable {
    let start: Date
    let sessions: [HealthSessionInsight]
    var id: Date { start }
    var calorieCount: Int { sessions.compactMap(\.calories).count }
    var effortCount: Int { sessions.compactMap(\.effort).count }
    var heartRateCount: Int { sessions.compactMap(\.averageHeartRate).count }
    var calories: Double? {
        let values = sessions.compactMap(\.calories)
        guard !values.isEmpty else { return nil }
        let sum = values.reduce(0,+); return sum.isFinite ? sum : nil
    }
    var effort: Double? { HealthInsights.mean(sessions.compactMap(\.effort)) }
    var heartRate: Double? { HealthInsights.mean(sessions.compactMap(\.averageHeartRate)) }
    static func grouped(_ sessions: [HealthSessionInsight], calendar: Calendar = .current) -> [Self] {
        let groups = Dictionary(grouping: sessions) { calendar.dateInterval(of: .weekOfYear, for: $0.workout.start)?.start ?? $0.workout.start }
        return groups.map { Self(start: $0.key, sessions: $0.value) }.sorted { $0.start < $1.start }
    }
}
