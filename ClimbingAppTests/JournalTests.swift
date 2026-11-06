import XCTest
import SwiftData
@testable import ClimbingApp

final class JournalRulesTests: XCTestCase {
    func testWholeSessionReplacesInsteadOfAdding() {
        let total = JournalRules.totals(detailedAttempts: 5, detailedSends: 2, batches: [.init(coverage: .wholeSession, attempts: 12, sends: 4)])
        XCTAssertEqual(total.attempts, 12); XCTAssertEqual(total.sends, 4); XCTAssertTrue(total.conflicts.isEmpty)
        let additional = JournalRules.totals(detailedAttempts: 5, detailedSends: 2, batches: [.init(coverage: .additional, attempts: 7, sends: 2)])
        XCTAssertEqual(additional.attempts, 12); XCTAssertEqual(additional.sends, 4)
    }
    func testHugeTotalsAreRejectedWithoutOverflowing() {
        let total = JournalRules.totals(detailedAttempts: 3, detailedSends: 1, batches: [.init(coverage: .additional, attempts: .max, sends: nil), .init(coverage: .additional, attempts: .max, sends: nil)])
        XCTAssertNil(total.attempts); XCTAssertFalse(total.conflicts.isEmpty)
    }
    func testSendsOnlyDoNotInventAttempts() {
        let total = JournalRules.totals(detailedAttempts: 0, detailedSends: 0, batches: [.init(coverage: .wholeSession, attempts: nil, sends: 4)])
        XCTAssertNil(total.attempts); XCTAssertEqual(total.sends, 4)
        let additional = JournalRules.totals(detailedAttempts: 5, detailedSends: 1, batches: [.init(coverage: .additional, attempts: nil, sends: 4)])
        XCTAssertNil(additional.attempts); XCTAssertEqual(additional.sends, 5)
    }
    func testConflictingTotalsAndDuplicateCoverageAreRejected() {
        XCTAssertFalse(JournalRules.totals(detailedAttempts: 5, detailedSends: 2, batches: [.init(coverage: .wholeSession, attempts: 4, sends: nil)]).conflicts.isEmpty)
        XCTAssertFalse(JournalRules.totals(detailedAttempts: 0, detailedSends: 0, batches: [.init(coverage: .additional, attempts: 2, sends: 4)]).conflicts.isEmpty)
        XCTAssertFalse(JournalRules.totals(detailedAttempts: 0, detailedSends: 0, batches: [.init(coverage: .wholeSession, attempts: 8), .init(coverage: .wholeSession, attempts: 8)]).conflicts.isEmpty)
    }
    func testUnknownHistoryIsNotEvidenceAndEarlierFailurePreventsFlash() {
        XCTAssertEqual(JournalRules.flash(prior: .unknown, historyIncomplete: false, outcomes: [true]).state, .unknown)
        XCTAssertEqual(JournalRules.flash(prior: .newClimb, historyIncomplete: false, outcomes: [true,true]).state, .confirmed)
        XCTAssertEqual(JournalRules.flash(prior: .newClimb, historyIncomplete: false, outcomes: [false,true]).state, .notFlash)
        XCTAssertEqual(JournalRules.flash(prior: .newClimb, historyIncomplete: true, outcomes: [true]).state, .unknown)
        XCTAssertEqual(JournalRules.flash(prior: .sent, historyIncomplete: false, outcomes: [true]).state, .notFlash)
    }
}

@MainActor
final class JournalPersistenceTests: XCTestCase {
    private func setup() throws -> (ClimbingStore, ClimbingSession, ClimbEntry) {
        let container = try Persistence.container(inMemory: true)
        let store = ClimbingStore(context: container.mainContext)
        let session = try XCTUnwrap(store.start(date: .now, location: "Gym", notes: ""))
        let climb = ClimbEntry(grade: "V3", prior: .newClimb)
        XCTAssertTrue(store.save { store.context.insert(climb); session.climbs.append(climb); climb.projectRaw = "active" })
        return (store,session,climb)
    }
    func testSameProjectAcrossSessionsAndDeletePreservesNotebook() throws {
        let (store,first,climb) = try setup()
        store.record(sent: false, on: climb)
        store.finish(first)
        let second = try XCTUnwrap(store.start(date: .now, location: "Gym", notes: ""))
        XCTAssertTrue(store.select(climb, in: second))
        store.record(sent: true, on: climb, in: second)
        XCTAssertEqual(first.attemptCount,1); XCTAssertEqual(first.sendCount,0)
        XCTAssertEqual(second.attemptCount,1); XCTAssertEqual(second.sendCount,1)
        XCTAssertEqual(climb.flash.state,.notFlash)
        XCTAssertEqual(climb.projectStatus,"sent")
        let note = ClimbNote(text: "Left heel")
        XCTAssertTrue(store.save { store.context.insert(note); climb.notebook.append(note) })
        XCTAssertTrue(store.delete(first))
        XCTAssertEqual(climb.attempts.count,1)
        XCTAssertEqual(climb.notebook.first?.text,"Left heel")
        XCTAssertEqual(climb.flash.state,.unknown)
        XCTAssertTrue(store.setProject(climb,status:""))
        XCTAssertEqual(climb.attempts.count,1)
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<ClimbEntry>()),1)
    }
    func testAggregateConflictRollsBackAndCanBeCorrected() throws {
        let (store,session,climb) = try setup()
        for _ in 0..<5 { store.record(sent: false, on: climb) }
        XCTAssertFalse(store.saveAggregate(nil, session: session, coverage: .wholeSession, attempts: 4, sends: nil, label: ""))
        XCTAssertTrue(session.aggregates.isEmpty)
        XCTAssertTrue(store.saveAggregate(nil, session: session, coverage: .wholeSession, attempts: 12, sends: 4, label: "Evening"))
        XCTAssertEqual(session.attemptCount,12)
        XCTAssertEqual(session.recordedAttempts.count,5)
        XCTAssertEqual(session.completedClimbs,0)
        XCTAssertEqual(session.sendCount,4)
    }
    func testDeletingFailureDoesNotCreateFlashAndCorrectionRecalculates() throws {
        let (store,session,climb) = try setup()
        store.record(sent:false,on:climb); store.record(sent:true,on:climb)
        let failure = try XCTUnwrap(climb.orderedAttempts.first)
        XCTAssertTrue(store.removeAttempt(failure))
        XCTAssertFalse(climb.isFlash)
        let send = try XCTUnwrap(climb.attempts.first)
        XCTAssertTrue(store.updateAttempt(send,sent:false,day:session.day,sequence:2,precision:"unknown"))
        XCTAssertEqual(session.sendCount,0)
    }
    func testGradeSnapshotSurvivesClimbGradeCorrection() throws {
        let (store,_,climb) = try setup()
        store.record(sent:true,on:climb)
        XCTAssertTrue(store.save { climb.grade = "V6" })
        let snapshot = try JSONDecoder().decode(GradeDescriptor.self,from: Data(climb.attempts[0].gradeSnapshot.utf8))
        XCTAssertEqual(snapshot.grade,"V3")
    }
    func testBackdatedFailureRecalculatesAcrossSessions() throws {
        let (store,first,climb) = try setup()
        store.record(sent:true,on:climb); store.finish(first)
        let second = try XCTUnwrap(store.start(date:.now,location:"",notes:""))
        XCTAssertTrue(store.select(climb,in:second)); store.record(sent:false,on:climb,in:second)
        let failure = try XCTUnwrap(climb.attempts.first { !$0.sent })
        XCTAssertTrue(store.updateAttempt(failure,sent:false,day:"2020-01-01",sequence:2,precision:"day"))
        XCTAssertEqual(climb.flash.state,.notFlash)
    }
    func testBackupRestoresIndependentProjectsNotebookAndRecapsTwice() throws {
        let (store,first,climb) = try setup()
        store.record(sent:false,on:climb); store.finish(first)
        let second = try XCTUnwrap(store.start(date:.now,location:"",notes:""))
        XCTAssertTrue(store.select(climb,in:second)); store.record(sent:true,on:climb,in:second)
        let orphan = ClimbEntry(label:"Untried project")
        let note = ClimbNote(text:"Try toe hook")
        XCTAssertTrue(store.save { orphan.projectRaw = "active"; store.context.insert(orphan); store.context.insert(note); orphan.notebook.append(note) })
        XCTAssertTrue(store.saveAggregate(nil,session:second,coverage:.additional,attempts:3,sends:1,label:"Remembered"))
        let backup = try ClimbingBackup.decode(ClimbingBackup(sessions:[first,second],defaultScale:.vScale,climbs:[climb,orphan]).encoded())
        XCTAssertTrue(store.restore(backup),store.errorMessage ?? "")
        XCTAssertTrue(store.restore(backup),store.errorMessage ?? "")
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<ClimbEntry>()),2)
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<ClimbNote>()),1)
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<AggregateEntry>()),1)
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<ClimbAttempt>()),2)
    }
    func testV2DiskMigrationRetainsIDsPhotosAndUnknownPriorHistory() throws {
        let root = FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let url = root.appending(path:"journal.store"), climbID = UUID(), sessionID = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema:ClimbingSchemaV2.self)
            let container = try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,url:url,cloudKitDatabase:.none)])
            let session = ClimbingSchemaV2.ClimbingSession(id:sessionID,location:"Legacy gym")
            let climb = ClimbingSchemaV2.ClimbEntry(id:climbID,grade:"V4")
            let attempt = ClimbingSchemaV2.ClimbAttempt(sequence:1,sent:true)
            let photo = ClimbingSchemaV2.RouteMedia(kind:.photo,filename:"test.png",contentType:"public.png",data:Data([1,2,3]))
            container.mainContext.insert(session);container.mainContext.insert(climb);container.mainContext.insert(attempt);container.mainContext.insert(photo)
            session.climbs.append(climb);climb.attempts.append(attempt);climb.media.append(photo)
            try container.mainContext.save()
        }
        let schema = Schema(versionedSchema:ClimbingSchemaV7.self)
        let container = try ModelContainer(for:schema,migrationPlan:ClimbingMigrationPlan.self,configurations:[ModelConfiguration(schema:schema,url:url,cloudKitDatabase:.none)])
        let climb = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<ClimbEntry>()).first)
        XCTAssertEqual(climb.id,climbID); XCTAssertEqual(climb.session?.id,sessionID)
        XCTAssertEqual(climb.media.first?.data,Data([1,2,3])); XCTAssertEqual(climb.flash.state,.unknown)
        XCTAssertEqual(climb.session?.attemptCount,1)
    }
}

@MainActor
final class JournalInvariantTests: XCTestCase {
    func testSameColorResetIsIndependentAndDistinctSendsAreNotSessionRows() throws {
        let container = try Persistence.container(inMemory:true)
        let store = ClimbingStore(context:container.mainContext)
        let first = try XCTUnwrap(store.start(date:.now,location:"Gym",notes:""))
        let climb = ClimbEntry(color:"Blue",grade:"V3")
        let reset = ClimbEntry(color:"Blue",grade:"V3")
        XCTAssertTrue(store.save { store.context.insert(climb); store.context.insert(reset); first.climbs.append(contentsOf:[climb,reset]) })
        store.record(sent:true,on:climb);store.record(sent:true,on:reset);store.finish(first)
        let second = try XCTUnwrap(store.start(date:.now,location:"Gym",notes:""))
        XCTAssertTrue(store.select(climb,in:second));store.record(sent:true,on:climb,in:second)
        let stats = JournalStatistics(sessions:[first,second])
        XCTAssertNotEqual(climb.id,reset.id)
        XCTAssertEqual(stats.distinctClimbsSent,2);XCTAssertEqual(stats.knownSends,3)
        XCTAssertEqual(stats.unknownFlashCount,2);XCTAssertEqual(stats.knownFlashDenominator,0)
    }
    func testWholeTotalsRejectLaterDetailedEvidenceUntilExplicitlyCorrected() throws {
        let container = try Persistence.container(inMemory:true)
        let store = ClimbingStore(context:container.mainContext)
        let session = try XCTUnwrap(store.start(date:.now,location:"",notes:""))
        let climb = ClimbEntry()
        XCTAssertTrue(store.save { store.context.insert(climb);session.climbs.append(climb) })
        XCTAssertTrue(store.saveAggregate(nil,session:session,coverage:.wholeSession,attempts:1,sends:0,label:""))
        store.record(sent:false,on:climb);store.record(sent:true,on:climb)
        XCTAssertEqual(climb.attempts.count,1);XCTAssertNotNil(store.errorMessage)
        let batch = try XCTUnwrap(session.aggregates.first)
        XCTAssertTrue(store.saveAggregate(batch,session:session,coverage:.wholeSession,attempts:2,sends:1,label:"Corrected"))
        store.record(sent:true,on:climb)
        XCTAssertEqual(climb.attempts.count,2);XCTAssertEqual(session.sendCount,1)
    }
    func testHealthLinkIsOmittedFromBackupAndSessionDeletionRemovesOnlyItsLink() throws {
        let container = try Persistence.container(inMemory:true)
        let store = ClimbingStore(context:container.mainContext)
        let session = try XCTUnwrap(store.start(date:.now,location:"",notes:""))
        let workoutID = UUID()
        XCTAssertTrue(store.save { store.context.insert(HealthWorkoutLink(sessionID:session.id,workoutID:workoutID,sourceName:"Fixture",sourceBundle:"fixture")) })
        let data = try ClimbingBackup(sessions:[session],defaultScale:.vScale).encoded()
        XCTAssertFalse(String(decoding:data,as:UTF8.self).contains(workoutID.uuidString))
        XCTAssertTrue(store.delete(session))
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<HealthWorkoutLink>()),0)
    }
}
