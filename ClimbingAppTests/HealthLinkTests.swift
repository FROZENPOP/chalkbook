import XCTest
@testable import ClimbingApp

final class HealthLinkRulesTests: XCTestCase {
    private func workout(id: UUID = UUID(), energy: Double? = nil, heart: Double? = nil) -> HealthWorkout {
        HealthWorkout(id:id,start:Date(timeIntervalSince1970:1000),end:Date(timeIntervalSince1970:4600),duration:3600,sourceName:"Fixture",sourceBundle:"test.fixture",energyKilocalories:energy,meanHeartRate:heart)
    }
    func testRefreshDeduplicatesByWorkoutIdentityAndDoesNotMergeSimilarRecords() {
        let first = workout(), second = workout()
        let results = HealthLinkRules.deduplicated([first,first,second])
        XCTAssertEqual(results.count,2)
        XCTAssertTrue(HealthLinkRules.hasSimilarCandidate(first,among:results))
    }
    func testWorkoutCannotBeAttachedToTwoSessionsButRefreshSameLinkIsAllowed() {
        let session = UUID(), other = UUID(), id = UUID()
        XCTAssertTrue(HealthLinkRules.canLink(workoutID:id,to:session,existing:[(session,id)]))
        XCTAssertFalse(HealthLinkRules.canLink(workoutID:id,to:other,existing:[(session,id)]))
    }
    func testPartialMeasurementsStayIndependentAndAbsentIsNotZero() {
        let energyOnly = workout(energy:210)
        XCTAssertEqual(energyOnly.energyKilocalories,210); XCTAssertNil(energyOnly.meanHeartRate)
        let heartOnly = workout(heart:130)
        XCTAssertNil(heartOnly.energyKilocalories); XCTAssertEqual(heartOnly.meanHeartRate,130)
    }
    func testOverlapIsSuggestionOnly() {
        XCTAssertEqual(HealthLinkRules.overlap(workout(),start:Date(timeIntervalSince1970:2000),end:Date(timeIntervalSince1970:3000)),1000)
        XCTAssertEqual(HealthLinkRules.overlap(workout(),start:Date(timeIntervalSince1970:5000),end:Date(timeIntervalSince1970:6000)),0)
    }
}

@MainActor
final class HealthReaderSubstituteTests: XCTestCase {
    func testDelayedAndUnavailableDataCanBeRetriedWithoutInventingMeasurements() async throws {
        let reader = TestHealthReader()
        try await reader.requestReadAccess()
        let empty = try await reader.nearby(start:.now,end:.now)
        XCTAssertTrue(empty.isEmpty)
        let id = UUID()
        reader.workouts = [HealthWorkout(id:id,start:.now,end:.now,duration:10,sourceName:"Fixture",sourceBundle:"fixture",energyKilocalories:nil,meanHeartRate:nil)]
        let found = try await reader.workout(id:id)
        XCTAssertNil(found?.meanHeartRate)
        reader.workouts = []
        let missing = try await reader.workout(id:id)
        XCTAssertNil(missing)
    }
}

@MainActor
private final class TestHealthReader: HealthWorkoutReading {
    var available = true
    var workouts: [HealthWorkout] = []
    func requestReadAccess() async throws {}
    func nearby(start:Date,end:Date) async throws -> [HealthWorkout] { workouts }
    func workout(id:UUID) async throws -> HealthWorkout? { workouts.first { $0.id == id } }
}
