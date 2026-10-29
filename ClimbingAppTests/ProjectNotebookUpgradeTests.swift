import XCTest
import SwiftData
@testable import ClimbingApp

@MainActor final class ProjectNotebookUpgradeTests:XCTestCase {
    func testEmptyProjectsOffersCreationEvenWithOrdinaryClimbs() {
        XCTAssertEqual(ProjectListState(climbs: [], filter: "active").emptyAction, .addProject)
        let ordinary = ClimbEntry(prior: .sent)
        XCTAssertEqual(ProjectListState(climbs: [ordinary], filter: "sent").emptyAction, .addProject)
        XCTAssertTrue(ProjectListState(climbs: [ordinary], filter: "all").projects.isEmpty)
    }

    func testEmptyFilterOffersAllAndRetainsSavedProjects() {
        let active = ClimbEntry(), archived = ClimbEntry(), ordinary = ClimbEntry()
        active.projectRaw = "active"; archived.projectRaw = "archived"
        let climbs = [active, archived, ordinary]
        XCTAssertEqual(ProjectListState(climbs: climbs, filter: "sent").emptyAction, .showAll)
        let all = ProjectListState(climbs: climbs, filter: "all")
        XCTAssertNil(all.emptyAction)
        XCTAssertEqual(Set(all.projects.map(\.id)), Set([active.id, archived.id]))
        XCTAssertEqual(active.projectRaw, "active"); XCTAssertEqual(archived.projectRaw, "archived")
    }

    func testHistoricallySentProjectUsesEffectiveStatusForEmptyState() {
        let sent = ClimbEntry(prior: .sent); sent.projectRaw = "active"
        XCTAssertEqual(ProjectListState(climbs: [sent], filter: "active").emptyAction, .showAll)
        let matching = ProjectListState(climbs: [sent], filter: "sent")
        XCTAssertNil(matching.emptyAction)
        XCTAssertEqual(matching.projects.map(\.id), [sent.id])
    }

    func testV5DiskMigrationPreservesPhotoAndNotebookWithEmptyNewFields() throws {
        let root=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let url=root.appending(path:"journal.store"),id=UUID()
        try autoreleasepool {
            let schema=Schema(versionedSchema:ClimbingSchemaV5.self)
            let container=try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,url:url,cloudKitDatabase:.none)])
            let climb=ClimbingSchemaV5.ClimbEntry(id:id)
            climb.notebook=[ClimbingSchemaV5.ClimbNote(text:"Saved next move")]
            climb.media=[ClimbingSchemaV5.RouteMedia(kind:.photo,filename:"kept.png",contentType:"public.png",data:Data([1,2,3]))]
            container.mainContext.insert(climb);try container.mainContext.save()
        }
        let schema=Schema(versionedSchema:ClimbingSchemaV6.self)
        let container=try ModelContainer(for:schema,migrationPlan:ClimbingMigrationPlan.self,configurations:[ModelConfiguration(schema:schema,url:url,cloudKitDatabase:.none)])
        let climb=try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<ClimbEntry>()).first)
        XCTAssertEqual(climb.id,id);XCTAssertEqual(climb.notebook.first?.text,"Saved next move")
        XCTAssertNil(climb.pinnedNoteID);XCTAssertEqual(climb.media.first?.annotationJSON,"")
        XCTAssertEqual(climb.media.first?.data,Data([1,2,3]))
    }

    func testPinAndMarkupSurviveBackupRestoreWithoutChangingOriginalPhoto() throws {
        let container=try Persistence.container(inMemory:true),store=ClimbingStore(context:container.mainContext)
        let climb=ClimbEntry();let note=ClimbNote(text:"Left foot high")
        let bundle=Bundle(for:Self.self)
        let fixture=try XCTUnwrap(bundle.url(forResource:"route-photo",withExtension:"png") ?? bundle.url(forResource:"route-photo",withExtension:"png",subdirectory:"Fixtures"))
        let original=try Data(contentsOf:fixture)
        let media=RouteMedia(kind:.photo,filename:"route.png",contentType:"public.png",data:original)
        media.annotationJSON=try RouteAnnotations.encode([RouteStroke(color:"orange",points:[RoutePoint(x:0.25,y:0.5),RoutePoint(x:0.75,y:0.7)])])
        climb.notebook=[note];climb.pinnedNoteID=note.id;climb.media=[media]
        container.mainContext.insert(climb);try container.mainContext.save()
        let backup=try ClimbingBackup(sessions:[],defaultScale:.vScale,climbs:[climb]).validated()
        XCTAssertEqual(backup.version,4)
        XCTAssertTrue(store.restore(backup))
        let restored=try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<ClimbEntry>()).first)
        XCTAssertEqual(restored.pinnedNote?.text,"Left foot high")
        XCTAssertEqual(restored.media.first?.data,original)
        XCTAssertEqual(try RouteAnnotations.decode(restored.media.first!.annotationJSON).count,1)
    }

    func testMarkupValidationRejectsBadCoordinatesAndOversizedPayloads() throws {
        XCTAssertThrowsError(try RouteAnnotations.encode([RouteStroke(color:"orange",points:[RoutePoint(x:2,y:0)])]))
        XCTAssertThrowsError(try RouteAnnotations.decode(String(repeating:"a",count:500001)))
        XCTAssertEqual(try RouteAnnotations.decode(""),[])
    }
}
