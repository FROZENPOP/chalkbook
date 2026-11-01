import Charts
import SwiftData
import SwiftUI

struct ProgressHealthSection: View {
    let sessionIDs: Set<UUID>
    @Query private var links: [HealthWorkoutLink]
    @AppStorage("healthInsightsEnabled") private var showInsights = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Health insights (optional)", isOn: $showInsights).accessibilityIdentifier("showHealthInsights")
            if showInsights {
                Text("Linked climbing workouts for this journal range. Weeks use workout start dates.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                HealthInsightsPanel(workoutIDs: links.filter { sessionIDs.contains($0.sessionID) }.map(\.workoutID), weekly: true)
            }
        }.tint(.primary)
    }
}

struct SessionHealthSection: View {
    let workoutID: UUID
    @AppStorage("healthInsightsEnabled") private var showInsights = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showInsights { HealthInsightsPanel(workoutIDs: [workoutID], weekly: false) }
            else {
                Button("View Health insights", systemImage: "heart.text.square") { showInsights = true }
                    .frame(minHeight: 44).accessibilityIdentifier("viewSessionHealthInsights")
            }
        }.tint(.primary)
    }
}

struct HealthInsightsPanel: View {
    let workoutIDs: [UUID]
    let weekly: Bool
    @Environment(\.scenePhase) private var phase
    @AppStorage("healthEnabled") private var enabled = false
    @State private var model = HealthInsightsModel(reader: HealthInsightsReaderFactory.make())
    @State private var refresh = 0
    @State private var request = 0
    @State private var consumedRequest = 0
    private var key: String { "\(enabled)-\(refresh)-\(request)-" + workoutIDs.map(\.uuidString).sorted().joined(separator: ",") }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Health").font(.title2.bold()).accessibilityIdentifier("healthInsightsHeading")
            Text("Private, read-only insights. Effort is an app estimate, not WHOOP strain or a medical metric. Health values are never shared or backed up.").font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
            if model.access == .unavailable { Text("Apple Health is unavailable on this device.").foregroundStyle(ClimbTheme.secondaryText) }
            if model.loading { SwiftUI.ProgressView("Reading accessible Health data…") }
            if let message = model.message { Text(message).font(.subheadline).accessibilityIdentifier("healthInsightsMessage") }
            if !enabled || model.access != .requested {
                Text(weekly ? "Connect to review access to climbing workouts, heart rate, active energy, resting heart rate, and HRV. Recovery readings are optional; each measurement may be unavailable." : "Connect to review read access to climbing workouts, heart rate, and active energy. Each measurement may be unavailable.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
            }
            Button("Connect Health / review read access", systemImage: "heart") { enabled = true; request += 1 }
                .frame(minHeight: 44).disabled(model.loading || model.access == .unavailable).accessibilityIdentifier("connectHealthInsights")
            if enabled {
                Button("Refresh Health insights", systemImage: "arrow.clockwise") { refresh += 1 }
                    .frame(minHeight: 44).disabled(model.loading).accessibilityIdentifier("refreshHealthInsights")
            }
            if model.unavailableWorkouts > 0 {
                Text("\(model.unavailableWorkouts) linked workouts are unavailable or inaccessible. Their values are excluded; journal entries are unchanged.").font(.caption)
            }
            if weekly {
                weeklyCards
                recoveryCard
            } else if let session = model.sessions.first { HealthSessionCards(insight: session) }
            else if !model.loading {
                Text("No data. Connect or refresh to read this linked workout. Missing measurements are never replaced with zero.").foregroundStyle(ClimbTheme.secondaryText)
            }
            DisclosureGroup("How the effort estimate works") {
                Text("0–10 estimate: 10 × √(D × I), rounded to one decimal. D is duration divided by 120 minutes, capped at 1. I averages available inputs: (average bpm − 60) ÷ 120, clamped to 0–1, and active kcal per minute ÷ 12, capped at 1. At least one intensity input and a positive duration are required. These fixed reference values are a journal heuristic, not personal heart-rate zones. Different available inputs affect comparability.")
                    .font(.caption)
            }.frame(minHeight: 44)
        }
        .tint(.primary)
        .task(id: key) {
            guard enabled else { model.clear(); return }
            let shouldRequest = request > consumedRequest
            consumedRequest = request
            await model.load(ids: workoutIDs, requestAccess: shouldRequest, includeRecovery: weekly)
        }
        .onChange(of: phase) { _, value in if value == .active && enabled && !model.loading { refresh += 1 } }
        .onDisappear { model.clear() }
    }
    private var weeklyCards: some View {
        let weeks = HealthInsightWeek.grouped(model.sessions)
        return VStack(alignment: .leading, spacing: 16) {
            if weeks.isEmpty { Text("No weekly Health data yet.").foregroundStyle(ClimbTheme.secondaryText) }
            HealthTrendCard(title: "Active calories", unit: "kcal", points: weeks.compactMap { week in week.calories.map { HealthTrendPoint(date: week.start, value: $0) } })
            HealthTrendCard(title: "Average effort estimate", unit: "/ 10", points: weeks.compactMap { week in week.effort.map { HealthTrendPoint(date: week.start, value: $0) } })
            HealthTrendCard(title: "Average session heart rate", unit: "bpm", points: weeks.compactMap { week in week.heartRate.map { HealthTrendPoint(date: week.start, value: $0) } })
            ForEach(weeks) { week in
                VStack(alignment: .leading, spacing: 6) {
                    Text(week.start, format: .dateTime.month().day()).font(.headline)
                    Text("Active calories: \(metric(week.calories)) kcal · \(week.calorieCount)/\(week.sessions.count) accessible workouts")
                    Text("Effort estimate: \(metric(week.effort, decimals: 1))/10 · \(week.effortCount)/\(week.sessions.count) accessible workouts")
                    Text("Average heart rate: \(metric(week.heartRate)) bpm · \(week.heartRateCount)/\(week.sessions.count) accessible workouts")
                }.font(.caption).accessibilityElement(children: .combine)
            }
            Text("Only accessible linked workouts contribute. Missing weeks/metrics stay unknown. Heart rate and effort are equal-weight averages of available session values, not time-weighted averages. Partial calories are recorded totals, not complete weekly expenditure.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
        }
    }
    private var recoveryCard: some View {
        HealthInsightCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recovery context").font(.headline)
                if model.recovery.hasData {
                    if let resting = model.recovery.restingHeartRate { recoveryReading("Resting heart rate", reading: resting, unit: "bpm") }
                    else { Text("Resting heart rate: No data") }
                    if let hrv = model.recovery.hrvMilliseconds { recoveryReading("HRV (SDNN)", reading: hrv, unit: "ms") }
                    else { Text("HRV: No data") }
                    Text("Latest accessible readings from the last 7 days. No recovery/readiness score is inferred from isolated readings or an unknown personal baseline.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                } else {
                    Text("Not available").font(.title2.bold())
                    Text("No accessible resting heart rate or HRV found. These optional readings depend on your device, source app, and read access. No recovery score is invented.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                }
            }
        }.accessibilityIdentifier("healthRecoveryContext")
    }
    private func recoveryReading(_ label: String, reading: HealthQuantityReading, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline)
            Text("\(metric(reading.value, decimals: 1)) \(unit)").font(.title.bold()).monospacedDigit()
            Text("\(reading.source) · \(reading.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
        }
    }
}

struct HealthSessionCards: View {
    let insight: HealthSessionInsight
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(insight.workout.sourceName) · \(insight.workout.start.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
            HealthInsightCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Climb effort estimate").font(.headline)
                    ZStack {
                        Circle().stroke(.primary.opacity(0.12), lineWidth: 12)
                        if let score = insight.effort {
                            Circle().trim(from: 0, to: score / 10).stroke(.primary, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                        }
                        Text(metric(insight.effort, decimals: 1)).font(.system(.title, design: .rounded, weight: .bold)).minimumScaleFactor(0.5).lineLimit(1)
                    }.frame(width: 140, height: 140).padding(8)
                        .accessibilityElement(children: .ignore).accessibilityLabel("Climb effort estimate").accessibilityValue(insight.effort.map { "\(metric($0, decimals: 1)) out of 10" } ?? "No data")
                    Text("App estimate · 0–10").font(.subheadline.bold())
                    Text(insight.effort == nil ? "Needs positive duration and accessible average heart rate or active energy." : "Inputs: \(insight.inputs). Missing inputs are omitted.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                }
            }.accessibilityIdentifier("healthEffortCard")
            HealthInsightCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active calories").font(.headline)
                    Text(metric(insight.calories)).font(.largeTitle.bold()).monospacedDigit()
                    Text("kcal · workout-associated active energy").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                }
            }.accessibilityIdentifier("healthCaloriesCard")
            HealthInsightCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Heart rate").font(.headline)
                    Text("Average: \(metric(insight.averageHeartRate)) bpm").font(.title2.bold()).monospacedDigit()
                    Text("Maximum: \(metric(insight.maximumHeartRate)) bpm").font(.headline)
                    Text(insight.averageFromSamples ? "Average of recorded sample values, not a time-weighted mean." : "Workout-associated statistics; missing values show No data.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                    if insight.maximumFromSamples { Text("Maximum of recorded samples; gaps may contain higher values.").font(.caption).foregroundStyle(ClimbTheme.secondaryText) }
                    if !insight.samples.isEmpty {
                        Chart(insight.samples) { sample in
                            PointMark(x: .value("Time", sample.date), y: .value("Heart rate (bpm)", sample.beatsPerMinute)).foregroundStyle(Color.primary)
                        }.frame(height: 160).accessibilityElement(children: .ignore).accessibilityLabel("Recorded heart rate over time")
                        .accessibilityValue("\(insight.samples.count) samples. Average \(metric(insight.averageHeartRate)) beats per minute.")
                        Text("\(insight.samples.count) recorded samples. Dots show measurements; gaps are not filled. Only this workout’s associated samples are used.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                    } else { Text("No accessible heart-rate samples. Summary statistics may still be available.").font(.caption).foregroundStyle(ClimbTheme.secondaryText) }
                }
            }.accessibilityIdentifier("healthHeartRateCard")
        }
    }
}

private struct HealthInsightCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.12)))
    }
}
private struct HealthTrendPoint: Identifiable { let date: Date; let value: Double; var id: Date { date } }
private struct HealthTrendCard: View {
    let title: String
    let unit: String
    let points: [HealthTrendPoint]
    var body: some View {
        HealthInsightCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                if points.isEmpty { Text("No data").font(.title.bold()) }
                else {
                    Text("\(metric(points.last?.value, decimals: 1)) \(unit)").font(.title.bold()).monospacedDigit()
                    Text("Latest week with data").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                    Chart(points) { point in
                        BarMark(x: .value("Week", point.date, unit: .weekOfYear), y: .value(unit, point.value)).foregroundStyle(Color.primary).cornerRadius(4)
                    }.frame(height: 140).accessibilityElement(children: .ignore).accessibilityLabel("Weekly \(title.lowercased())")
                    .accessibilityValue(points.map { "\($0.date.formatted(date: .abbreviated, time: .omitted)): \(metric($0.value, decimals: 1)) \(unit)" }.joined(separator: "; "))
                }
            }
        }
    }
}
private func metric(_ value: Double?, decimals: Int = 0) -> String {
    value.map { $0.formatted(.number.precision(.fractionLength(decimals))) } ?? "No data"
}
