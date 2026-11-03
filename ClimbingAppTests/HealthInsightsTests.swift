import XCTest
import SwiftData
@testable import ClimbingApp

final class HealthInsightsMathTests: XCTestCase {
    func testEmptyDurationOnlyAndInvalidInputsHaveNoEstimate() {
        XCTAssertNil(HealthInsights.effort(duration: nil, averageHeartRate: nil, activeCalories: nil))
        XCTAssertNil(HealthInsights.effort(duration: 3600, averageHeartRate: nil, activeCalories: nil))
        for duration in [0, -1, Double.nan, Double.infinity] {
            XCTAssertNil(HealthInsights.effort(duration: duration, averageHeartRate: 140, activeCalories: 400))
        }
        XCTAssertNil(HealthInsights.effort(duration: 3600, averageHeartRate: .nan, activeCalories: -1))
        XCTAssertNil(HealthInsights.effort(duration: 3600, averageHeartRate: 0, activeCalories: .infinity))
    }
    func testPartialInputsAreOmittedRatherThanZeroFilled() {
        XCTAssertEqual(HealthInsights.effort(duration: 3600, averageHeartRate: 120, activeCalories: nil), 5)
        XCTAssertEqual(HealthInsights.effort(duration: 3600, averageHeartRate: nil, activeCalories: 360), 5)
        XCTAssertEqual(HealthInsights.effort(duration: 3600, averageHeartRate: 120, activeCalories: 360), 5)
        XCTAssertEqual(HealthInsights.effort(duration: 3600, averageHeartRate: 144, activeCalories: 432), 5.7)
        XCTAssertEqual(HealthInsights.effort(duration: 3600, averageHeartRate: nil, activeCalories: 0), 0)
    }
    func testExtremeValuesAreBoundedAndRoundingIsOneDecimal() {
        XCTAssertEqual(HealthInsights.effort(duration: .greatestFiniteMagnitude, averageHeartRate: 300, activeCalories: .greatestFiniteMagnitude), 10)
        XCTAssertEqual(HealthInsights.effort(duration: 1, averageHeartRate: 180, activeCalories: 100000), 0.1)
        XCTAssertEqual(HealthInsights.effort(duration: 7200, averageHeartRate: 60, activeCalories: nil), 0)
        XCTAssertEqual(HealthInsights.effort(duration: .leastNonzeroMagnitude, averageHeartRate: nil, activeCalories: 0), 0)
        XCTAssertNil(HealthInsights.heartRate(301))
        XCTAssertNil(HealthInsights.mean([]))
    }
    func testSamplesAreBoundToWorkoutAndStatisticsRemainIndependent() {
        let start = Date(timeIntervalSince1970: 100000)
        let workout = HealthWorkout(id:UUID(),start:start,end:start.addingTimeInterval(3600),duration:3600,sourceName:"Test",sourceBundle:"test",energyKilocalories:nil,meanHeartRate:nil)
        let samples = [(-1.0, 190.0), (100,120), (200,160), (4000,180), (300,Double.nan)].map {
            HealthHeartRateSample(id:UUID(),date:start.addingTimeInterval($0.0),beatsPerMinute:$0.1)
        }
        let insight = HealthSessionInsight(workout:workout,samples:samples)
        XCTAssertEqual(insight.samples.count,2)
        XCTAssertEqual(insight.averageHeartRate,140);XCTAssertEqual(insight.maximumHeartRate,160)
        XCTAssertNil(insight.calories)
    }
    private func insight(daysAgo: Double, calories: Double? = nil, heart: Double? = nil, from now: Date) -> HealthSessionInsight {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        return .init(workout: .init(id: UUID(), start: start, end: start.addingTimeInterval(3600), duration: 3600, sourceName: "Test", sourceBundle: "test", energyKilocalories: calories, meanHeartRate: heart), samples: [])
    }
    func testThirtyDayAverageUsesOnlyEarlierWorkoutsInTheWindowAndSkipsMissingValues() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let current = insight(daysAgo: 0, calories: 500, from: now)
        let others = [insight(daysAgo: 10, calories: 200, from: now), insight(daysAgo: 29, calories: 400, from: now), insight(daysAgo: 5, from: now),
                      insight(daysAgo: 31, calories: 9000, from: now), insight(daysAgo: -3, calories: 9000, from: now), current]
        XCTAssertEqual(current.thirtyDayAverage(of: \.calories, among: others), 300)
        XCTAssertNil(current.thirtyDayAverage(of: \.averageHeartRate, among: others), "No workout has this value, so nothing is compared")
        XCTAssertNil(current.thirtyDayAverage(of: \.calories, among: [current]), "A workout is never compared with itself")
    }
    func testHeartRateSegmentsBreakOnlyAcrossGapsOverTenMinutes() {
        let start = Date(timeIntervalSince1970: 100000)
        let workout = HealthWorkout(id:UUID(),start:start,end:start.addingTimeInterval(7200),duration:7200,sourceName:"Test",sourceBundle:"test",energyKilocalories:nil,meanHeartRate:nil)
        let samples = [0.0, 600, 1201, 1300, 6000].map { HealthHeartRateSample(id:UUID(),date:start.addingTimeInterval($0),beatsPerMinute:120) }
        XCTAssertEqual(HealthSessionInsight(workout:workout,samples:samples).heartRateSegments.map(\.count), [2,2,1])
        XCTAssertTrue(HealthSessionInsight(workout:workout,samples:[]).heartRateSegments.isEmpty)
    }
}

@MainActor final class HealthInsightsReaderTests: XCTestCase {
    func testNotDeterminedNeverRequestsOrQueriesWithoutExplicitAction() async {
        let reader = InsightsTestReader(), model = HealthInsightsModel(reader:reader)
        await model.load(ids:[reader.id],requestAccess:false)
        XCTAssertEqual(model.access,.needsRequest);XCTAssertEqual(reader.requests,0);XCTAssertEqual(reader.queries,0)
        XCTAssertTrue(model.sessions.isEmpty)
        await model.load(ids:[reader.id],requestAccess:true)
        XCTAssertEqual(reader.requests,1)
        XCTAssertEqual(model.sessions.count,1)
    }
    func testDeniedReadIsIndistinguishableFromNoAccessibleData() async {
        let reader = InsightsTestReader();reader.state = .requested;reader.denied = true
        let model = HealthInsightsModel(reader:reader)
        await model.load(ids:[reader.id],requestAccess:false)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.message?.contains("No accessible data found") == true)
        XCTAssertFalse(model.message?.contains("Permission denied") == true)
    }
    func testUnavailableDoesNotRequestOrQuery() async {
        let reader = InsightsTestReader();reader.available=false
        let model=HealthInsightsModel(reader:reader)
        await model.load(ids:[reader.id],requestAccess:true)
        XCTAssertEqual(model.access,.unavailable);XCTAssertEqual(reader.requests,0);XCTAssertEqual(reader.queries,0)
        XCTAssertTrue(model.sessions.isEmpty)
    }
    func testPartialFailureKeepsWorkoutMetricsAndRefreshDoesNotDuplicate() async {
        let reader = InsightsTestReader();reader.state = .requested;reader.failSamples = true
        let model=HealthInsightsModel(reader:reader)
        await model.load(ids:[reader.id,reader.id],requestAccess:false)
        XCTAssertEqual(model.sessions.count,1);XCTAssertEqual(model.sessions.first?.calories,432)
        XCTAssertNotNil(model.message)
        reader.failSamples=false
        await model.load(ids:[reader.id],requestAccess:false)
        XCTAssertEqual(model.sessions.count,1);XCTAssertNil(model.message)
        reader.denied=true
        await model.load(ids:[reader.id],requestAccess:false)
        XCTAssertTrue(model.sessions.isEmpty)
    }
    func testRequestErrorDoesNotClaimAccessAndCanRetry() async {
        let reader = InsightsTestReader();reader.failRequest=true
        let model=HealthInsightsModel(reader:reader)
        await model.load(ids:[reader.id],requestAccess:true)
        XCTAssertNotNil(model.message);XCTAssertTrue(model.sessions.isEmpty)
        reader.failRequest=false
        await model.load(ids:[reader.id],requestAccess:true)
        XCTAssertEqual(model.sessions.count,1)
        model.clear();XCTAssertTrue(model.sessions.isEmpty)
    }
    func testClearingDuringReadPreventsLateDataFromReappearing() async {
        let reader=InsightsTestReader();reader.state = .requested;reader.delay=true
        let model=HealthInsightsModel(reader:reader)
        let task=Task { await model.load(ids:[reader.id],requestAccess:false) }
        while reader.pending == nil { await Task.yield() }
        model.clear();reader.pending?.resume();reader.pending=nil
        await task.value
        XCTAssertTrue(model.sessions.isEmpty);XCTAssertFalse(model.loading)
    }
    func testComparisonWorkoutsSkipTheHeartRateRead() async {
        let reader = InsightsTestReader();reader.state = .requested
        let model=HealthInsightsModel(reader:reader), other=UUID()
        await model.load(ids:[reader.id,other],requestAccess:false,samplesFor:reader.id)
        XCTAssertEqual(model.sessions.count,2);XCTAssertEqual(reader.sampleReads,[reader.id])
    }
    func testHealthMetricsAndLinksNeverEnterSocialSnapshotOrBackup() async throws {
        let container=try Persistence.container(inMemory:true)
        let session=ClimbingSession(location:"Journal",notes:"Private");session.endedAt=session.startedAt.addingTimeInterval(3600);session.isComplete=true
        container.mainContext.insert(session)
        let reader=InsightsTestReader();reader.state = .requested
        container.mainContext.insert(HealthWorkoutLink(sessionID:session.id,workoutID:reader.id,sourceName:"PRIVATE_HEALTH_SOURCE",sourceBundle:"private.health.source"))
        try container.mainContext.save()
        let before=SharedSession(session:session,owner:UUID()).rpcValues
        let model=HealthInsightsModel(reader:reader)
        await model.load(ids:[reader.id],requestAccess:false)
        XCTAssertNotNil(model.sessions.first?.effort)
        let after=SharedSession(session:session,owner:UUID()).rpcValues
        XCTAssertEqual(Set(after.keys),["source_session_id","visibility","caption","session_day","attempts","sends","duration_minutes","completeness"])
        let beforeData=try JSONSerialization.data(withJSONObject:before,options:.sortedKeys)
        let afterData=try JSONSerialization.data(withJSONObject:after,options:.sortedKeys)
        XCTAssertEqual(beforeData,afterData)
        let backup=String(decoding:try JSONEncoder().encode(ClimbingBackup(sessions:[session],defaultScale:.vScale)),as:UTF8.self)
        let social=String(decoding:afterData,as:UTF8.self)
        for forbidden in [reader.id.uuidString,"PRIVATE_HEALTH_SOURCE","private.health.source","heartRate","energyKilocalories","effort","restingHeartRate","hrvMilliseconds"] {
            XCTAssertFalse(backup.contains(forbidden),forbidden);XCTAssertFalse(social.contains(forbidden),forbidden)
        }
    }
}

@MainActor private final class InsightsTestReader: HealthWorkoutReading {
    var available=true
    var state=HealthReadAccessState.needsRequest
    var denied=false, failSamples=false, failRequest=false, delay=false
    var requests=0, queries=0
    var sampleReads:[UUID]=[]
    let id=UUID()
    var pending: CheckedContinuation<Void,Never>?
    func requestReadAccess() async throws {
        requests += 1
        if failRequest { throw BackupError.invalid("Test request error") }
        state = .requested
    }
    func readAccessState() async throws -> HealthReadAccessState { state }
    func nearby(start:Date,end:Date) async throws -> [HealthWorkout] { [] }
    func workout(id:UUID) async throws -> HealthWorkout? {
        queries += 1
        if delay { await withCheckedContinuation { pending=$0 } }
        guard !denied else { return nil }
        return HealthWorkout(id:id,start:.now.addingTimeInterval(-3600),end:.now,duration:3600,sourceName:"PRIVATE_HEALTH_SOURCE",sourceBundle:"private.health.source",energyKilocalories:432,meanHeartRate:144,maximumHeartRate:176)
    }
    func heartRates(workoutID:UUID) async throws -> [HealthHeartRateSample] {
        sampleReads.append(workoutID)
        if failSamples { throw BackupError.invalid("Test samples error") }; return []
    }
}
