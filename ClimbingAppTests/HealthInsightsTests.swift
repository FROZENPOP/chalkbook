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
        XCTAssertTrue(insight.averageFromSamples);XCTAssertTrue(insight.maximumFromSamples);XCTAssertNil(insight.calories)
    }
    func testWeeklyAggregationKeepsMissingDataAndCoverageHonest() {
        var calendar = Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
        let start = Date(timeIntervalSince1970: 1700000000)
        func insight(_ calories:Double?, _ heart:Double?) -> HealthSessionInsight {
            .init(workout:.init(id:UUID(),start:start,end:start.addingTimeInterval(3600),duration:3600,sourceName:"Test",sourceBundle:"test",energyKilocalories:calories,meanHeartRate:heart),samples:[])
        }
        let weeks = HealthInsightWeek.grouped([insight(nil,nil),insight(200,120),insight(300,160)],calendar:calendar)
        XCTAssertEqual(weeks.count,1);XCTAssertEqual(weeks[0].sessions.count,3)
        XCTAssertEqual(weeks[0].calories,500);XCTAssertEqual(weeks[0].calorieCount,2)
        XCTAssertEqual(weeks[0].heartRate,140);XCTAssertEqual(weeks[0].heartRateCount,2)
        XCTAssertNil(HealthInsightWeek.grouped([insight(nil,nil)],calendar:calendar).first?.effort)
        XCTAssertNil(HealthInsightWeek.grouped([insight(nil,nil)],calendar:calendar).first?.calories)
        XCTAssertTrue(HealthInsightWeek.grouped([]).isEmpty)
    }
    func testRecoveryContextRejectsInvalidReadingsAndNeverCreatesAScore() {
        let invalid = HealthRecoveryContext(restingHeartRate:.init(value:0,date:.now,source:"Test"),hrvMilliseconds:.init(value:.nan,date:.now,source:"Test"))
        XCTAssertFalse(invalid.sanitized.hasData)
        let partial = HealthRecoveryContext(restingHeartRate:nil,hrvMilliseconds:.init(value:42,date:.now,source:"Test"))
        XCTAssertTrue(partial.sanitized.hasData);XCTAssertNil(partial.sanitized.restingHeartRate)
    }
}

@MainActor final class HealthInsightsReaderTests: XCTestCase {
    func testNotDeterminedNeverRequestsOrQueriesWithoutExplicitAction() async {
        let reader = InsightsTestReader(), model = HealthInsightsModel(reader:reader)
        await model.load(ids:[reader.id],requestAccess:false,includeRecovery:true)
        XCTAssertEqual(model.access,.needsRequest);XCTAssertEqual(reader.requests,0);XCTAssertEqual(reader.queries,0)
        XCTAssertTrue(model.sessions.isEmpty)
        await model.load(ids:[reader.id],requestAccess:true,includeRecovery:true)
        XCTAssertEqual(reader.requests,1);XCTAssertTrue(reader.requestedRecovery)
        XCTAssertEqual(model.sessions.count,1)
    }
    func testDeniedReadIsIndistinguishableFromNoAccessibleData() async {
        let reader = InsightsTestReader();reader.state = .requested;reader.denied = true
        let model = HealthInsightsModel(reader:reader)
        await model.load(ids:[reader.id],requestAccess:false,includeRecovery:true)
        XCTAssertTrue(model.sessions.isEmpty);XCTAssertFalse(model.recovery.hasData)
        XCTAssertTrue(model.message?.contains("No accessible data found") == true)
        XCTAssertFalse(model.message?.contains("Permission denied") == true)
    }
    func testUnavailableDoesNotRequestOrQuery() async {
        let reader = InsightsTestReader();reader.available=false
        let model=HealthInsightsModel(reader:reader)
        await model.load(ids:[reader.id],requestAccess:true,includeRecovery:true)
        XCTAssertEqual(model.access,.unavailable);XCTAssertEqual(reader.requests,0);XCTAssertEqual(reader.queries,0)
        XCTAssertTrue(model.sessions.isEmpty)
    }
    func testPartialFailureKeepsWorkoutMetricsAndRefreshDoesNotDuplicate() async {
        let reader = InsightsTestReader();reader.state = .requested;reader.failSamples = true
        let model=HealthInsightsModel(reader:reader)
        await model.load(ids:[reader.id,reader.id],requestAccess:false,includeRecovery:true)
        XCTAssertEqual(model.sessions.count,1);XCTAssertEqual(model.sessions.first?.calories,432)
        XCTAssertNotNil(model.message)
        reader.failSamples=false
        await model.load(ids:[reader.id],requestAccess:false,includeRecovery:true)
        XCTAssertEqual(model.sessions.count,1);XCTAssertNil(model.message)
        reader.denied=true
        await model.load(ids:[reader.id],requestAccess:false,includeRecovery:true)
        XCTAssertTrue(model.sessions.isEmpty);XCTAssertFalse(model.recovery.hasData)
    }
    func testRequestErrorDoesNotClaimAccessAndCanRetry() async {
        let reader = InsightsTestReader();reader.failRequest=true
        let model=HealthInsightsModel(reader:reader)
        await model.load(ids:[reader.id],requestAccess:true,includeRecovery:false)
        XCTAssertNotNil(model.message);XCTAssertTrue(model.sessions.isEmpty)
        reader.failRequest=false
        await model.load(ids:[reader.id],requestAccess:true,includeRecovery:false)
        XCTAssertEqual(model.sessions.count,1);XCTAssertFalse(reader.requestedRecovery)
        model.clear();XCTAssertTrue(model.sessions.isEmpty);XCTAssertFalse(model.recovery.hasData)
    }
    func testClearingDuringReadPreventsLateDataFromReappearing() async {
        let reader=InsightsTestReader();reader.state = .requested;reader.delay=true
        let model=HealthInsightsModel(reader:reader)
        let task=Task { await model.load(ids:[reader.id],requestAccess:false,includeRecovery:true) }
        while reader.pending == nil { await Task.yield() }
        model.clear();reader.pending?.resume();reader.pending=nil
        await task.value
        XCTAssertTrue(model.sessions.isEmpty);XCTAssertFalse(model.recovery.hasData);XCTAssertFalse(model.loading)
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
        await model.load(ids:[reader.id],requestAccess:false,includeRecovery:true)
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
    var requestedRecovery=false
    let id=UUID()
    var pending: CheckedContinuation<Void,Never>?
    func requestReadAccess() async throws { try await requestReadAccess(includeRecovery:false) }
    func requestReadAccess(includeRecovery:Bool) async throws {
        requests += 1;requestedRecovery=includeRecovery
        if failRequest { throw BackupError.invalid("Test request error") }
        state = .requested
    }
    func readAccessState(includeRecovery:Bool) async throws -> HealthReadAccessState { state }
    func nearby(start:Date,end:Date) async throws -> [HealthWorkout] { [] }
    func workout(id:UUID) async throws -> HealthWorkout? {
        queries += 1
        if delay { await withCheckedContinuation { pending=$0 } }
        guard !denied else { return nil }
        return HealthWorkout(id:id,start:.now.addingTimeInterval(-3600),end:.now,duration:3600,sourceName:"PRIVATE_HEALTH_SOURCE",sourceBundle:"private.health.source",energyKilocalories:432,meanHeartRate:144,maximumHeartRate:176)
    }
    func heartRates(workoutID:UUID) async throws -> [HealthHeartRateSample] {
        if failSamples { throw BackupError.invalid("Test samples error") }; return []
    }
    func recoveryContext() async throws -> HealthRecoveryContext {
        denied ? .init() : .init(restingHeartRate:.init(value:58,date:.now,source:"PRIVATE_HEALTH_SOURCE"),hrvMilliseconds:nil)
    }
}
