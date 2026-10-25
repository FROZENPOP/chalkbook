import XCTest
import SwiftData
@testable import ClimbingApp

@MainActor final class ProjectNotebookUpgradeTests:XCTestCase {
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
