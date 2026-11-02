import Charts
import SwiftData
import SwiftUI

/// The Health half of a session log. Read-only; never shared or backed up.
struct SessionHealthStatistics: View {
    let session: ClimbingSession
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var textSize
    @AppStorage("healthEnabled") private var enabled = false
    @Query private var links: [HealthWorkoutLink]
    @Query private var sessions: [ClimbingSession]
    @State private var model = HealthInsightsModel(reader: HealthInsightsReaderFactory.make())
    @State private var refresh = 0
    @State private var request = 0
    @State private var consumedRequest = 0
    @State private var linking = false
    private var workoutID: UUID? { links.first { $0.sessionID == session.id }?.workoutID }
    // Session days only bound what is read; the comparison itself uses exact workout times.
    private var comparisonIDs: [UUID] {
        let day = SessionDay.date(for: session.day) ?? session.startedAt
        let since = SessionDay.key(for: day.addingTimeInterval(-31 * 86_400))
        let recent = Set(sessions.filter { $0.id != session.id && $0.day >= since && $0.day <= session.day }.map(\.id))
        return links.filter { recent.contains($0.sessionID) }.map(\.workoutID)
    }
    private var insight: HealthSessionInsight? { model.sessions.first { $0.id == workoutID } }
    private var others: [HealthSessionInsight] { model.sessions.filter { $0.id != workoutID } }
    private var hasComparison: Bool {
        guard let insight else { return false }
        return [\HealthSessionInsight.effort, \.calories, \.averageHeartRate, \.maximumHeartRate, \.durationMinutes].contains { insight.thirtyDayAverage(of: $0, among: others) != nil }
    }
    private var key: String { "\(enabled)-\(refresh)-\(request)-\(workoutID?.uuidString ?? "")-" + comparisonIDs.map(\.uuidString).sorted().joined(separator: ",") }
    private var message: String? { model.access == .unavailable ? "Apple Health is unavailable on this device." : model.message }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let header = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            header {
                Text("Key statistics").font(.title3.bold()).accessibilityIdentifier("healthInsightsHeading")
                if !textSize.isAccessibilitySize { Spacer(minLength: 8) }
                if hasComparison { Text("vs. 30-day avg").font(.caption).foregroundStyle(ClimbTheme.secondaryText) }
            }
            if workoutID == nil {
                Button("Link Apple Health workout", systemImage: "heart.text.square") { linking = true }
                    .foregroundStyle(ClimbTheme.accent).frame(minHeight: 44).accessibilityIdentifier("linkHealthWorkout")
            } else {
                if model.access != .unavailable && (!enabled || model.access == .needsRequest) {
                    Button("Connect Apple Health", systemImage: "heart") { enabled = true; request += 1 }
                        .foregroundStyle(ClimbTheme.accent).frame(minHeight: 44).disabled(model.loading).accessibilityIdentifier("connectHealthInsights")
                }
                if model.loading { SwiftUI.ProgressView() }
                if let message {
                    Text(message).font(.subheadline).foregroundStyle(ClimbTheme.secondaryText).accessibilityIdentifier("healthInsightsMessage")
                }
                if let insight { HealthStatisticCards(insight: insight, others: others) }
                Button("Change workout") { linking = true }.foregroundStyle(ClimbTheme.accent).frame(minHeight: 44).accessibilityIdentifier("changeHealthWorkout")
            }
        }
        .tint(.primary)
        .sheet(isPresented: $linking) { HealthLinkView(session: session) }
        .task(id: key) {
            guard enabled, let workoutID else { model.clear(); return }
            let shouldRequest = request > consumedRequest
            consumedRequest = request
            await model.load(ids: [workoutID] + comparisonIDs, requestAccess: shouldRequest, samplesFor: workoutID)
        }
        .onChange(of: phase) { _, value in if value == .active && enabled && !model.loading { refresh += 1 } }
        .onDisappear { model.clear() }
    }
}

private struct HealthStatisticCards: View {
    let insight: HealthSessionInsight
    let others: [HealthSessionInsight]
    @Environment(\.dynamicTypeSize) private var textSize
    private func card(_ title: String, _ metric: KeyPath<HealthSessionInsight, Double?>, unit: String, decimals: Int = 0, caption: String? = nil, id: String) -> some View {
        HealthStatisticCard(title: title, value: insight[keyPath: metric], unit: unit, decimals: decimals, caption: caption, average: insight.thirtyDayAverage(of: metric, among: others))
            .accessibilityIdentifier(id)
    }
    var body: some View {
        VStack(spacing: 12) {
            card("Effort", \.effort, unit: "/ 10", decimals: 1, caption: "App estimate", id: "healthEffortCard")
            // Not a lazy grid: it clips its cards when the text size changes while they're on screen.
            let row = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            row {
                card("Calories", \.calories, unit: "kcal", id: "healthCaloriesCard")
                card("Avg heart rate", \.averageHeartRate, unit: "bpm", id: "healthAverageHeartRateCard")
            }.fixedSize(horizontal: false, vertical: true)
            row {
                card("Max heart rate", \.maximumHeartRate, unit: "bpm", id: "healthMaximumHeartRateCard")
                card("Duration", \.durationMinutes, unit: "min", id: "healthDurationCard")
            }.fixedSize(horizontal: false, vertical: true)
            if !insight.samples.isEmpty { HeartRateChart(insight: insight) }
        }
    }
}

private struct HealthStatisticCard: View {
    let title: String
    let value: Double?
    let unit: String
    let decimals: Int
    let caption: String?
    let average: Double?
    private func format(_ number: Double) -> String { number.formatted(.number.precision(.fractionLength(decimals))) }
    /// The difference as shown, so a card never claims a change its rounded numbers don't show.
    private var difference: Double? {
        guard let value, let average else { return nil }
        let scale = pow(10, Double(decimals))
        return (value * scale).rounded() / scale - (average * scale).rounded() / scale
    }
    private var spokenValue: String {
        guard let value else { return "No data" }
        var words = "\(format(value)) \(unit)"
        if let caption { words += ", \(caption)" }
        if let difference {
            words += difference == 0 ? ", same as your 30-day average" : ", \(format(abs(difference))) \(difference > 0 ? "above" : "below") your 30-day average"
        }
        return words
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map(format) ?? "—").font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
                if value != nil { Text(unit).font(.caption).foregroundStyle(ClimbTheme.secondaryText) }
            }
            if value != nil, let caption { Text(caption).font(.caption).foregroundStyle(ClimbTheme.secondaryText) }
            if let difference {
                HStack(spacing: 4) {
                    if difference != 0 { Image(systemName: difference > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.caption2) }
                    Text(difference == 0 ? "Same" : format(abs(difference))).font(.caption.weight(.semibold)).monospacedDigit()
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.primary.opacity(0.08), in: Capsule())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spokenValue)
    }
}

private struct HeartRateChart: View {
    let insight: HealthSessionInsight
    private var floor: Double { (insight.samples.map(\.beatsPerMinute).min() ?? 0) - 10 }
    private var ceiling: Double { (insight.samples.map(\.beatsPerMinute).max() ?? 0) + 10 }
    private var fill: LinearGradient { LinearGradient(colors: [ClimbTheme.accent.opacity(0.35), ClimbTheme.accent.opacity(0)], startPoint: .top, endPoint: .bottom) }
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Heart rate").font(.headline)
                Chart {
                    ForEach(Array(insight.heartRateSegments.enumerated()), id: \.offset) { index, segment in
                        ForEach(segment) { sample in
                            AreaMark(x: .value("Time", sample.date), yStart: .value("Floor", floor), yEnd: .value("Heart rate", sample.beatsPerMinute), series: .value("Segment", index))
                                .foregroundStyle(fill).interpolationMethod(.monotone)
                            LineMark(x: .value("Time", sample.date), y: .value("Heart rate", sample.beatsPerMinute), series: .value("Segment", index))
                                .foregroundStyle(ClimbTheme.accent).interpolationMethod(.monotone)
                            // A lone reading has no line to sit on.
                            if segment.count == 1 { PointMark(x: .value("Time", sample.date), y: .value("Heart rate", sample.beatsPerMinute)).foregroundStyle(ClimbTheme.accent) }
                        }
                    }
                }
                .chartYScale(domain: floor...ceiling)
                .chartXScale(domain: insight.workout.start...insight.workout.end)
                .chartXAxis(.hidden)
                .frame(height: 140)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Heart rate over time")
                .accessibilityValue("\(insight.samples.count) readings, from \(Int(floor + 10)) to \(Int(ceiling - 10)) beats per minute.")
                .accessibilityIdentifier("healthHeartRateChart")
                HStack {
                    Text(insight.workout.start, format: .dateTime.hour().minute())
                    Spacer()
                    Text(insight.workout.end, format: .dateTime.hour().minute())
                }.font(.caption).foregroundStyle(ClimbTheme.secondaryText)
            }
        }
    }
}
