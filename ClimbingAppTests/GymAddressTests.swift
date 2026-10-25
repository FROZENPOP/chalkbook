import SwiftData
import XCTest
@testable import ClimbingApp

@MainActor
final class GymAddressTests: XCTestCase {
    func testBranchesKeepSeparateIdentitiesAndAddressesSurviveBackupRestore() throws {
        let container = try Persistence.container(inMemory:true)
        let store = ClimbingStore(context:container.mainContext)
        let first = try XCTUnwrap(store.saveGym(existing:nil,name:"Bouldering Gym",scale:.vScale,customName:"",grades:[],isDefault:true,address:"10 First Street"))
        let second = try XCTUnwrap(store.saveGym(existing:nil,name:"Bouldering Gym",scale:.vScale,customName:"",grades:[],isDefault:false,address:"20 Second Street"))
        XCTAssertNotEqual(first.id,second.id)
        XCTAssertNil(store.saveGym(existing:nil,name:"bouldering gym",scale:.vScale,customName:"",grades:[],isDefault:false,address:"10 first street"))
        let backup = try ClimbingBackup.decode(ClimbingBackup(sessions:[],defaultScale:.vScale,gyms:[first,second]).encoded())
        XCTAssertTrue(store.restore(backup),store.errorMessage ?? "")
        XCTAssertTrue(store.restore(backup),store.errorMessage ?? "")
        let restored = try store.context.fetch(FetchDescriptor<SavedGym>())
        XCTAssertEqual(restored.count,2)
        XCTAssertEqual(Set(restored.map(\.address)),Set(["10 First Street","20 Second Street"]))
    }

    func testV4MigrationPreservesExistingGymAndDefaultsAddressToEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let url = directory.appending(path:"test.store"), id = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema:ClimbingSchemaV4.self)
            let old = try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,url:url,cloudKitDatabase:.none)])
            let gym = ClimbingSchemaV4.SavedGym(id:id,name:"Saved before search",scale:.custom,customScaleName:"Colors",customGrades:["Blue"],isDefault:true)
            old.mainContext.insert(gym);try old.mainContext.save()
        }
        let schema = Schema(versionedSchema:ClimbingSchemaV5.self)
        let migrated = try ModelContainer(for:schema,migrationPlan:ClimbingMigrationPlan.self,configurations:[ModelConfiguration(schema:schema,url:url,cloudKitDatabase:.none)])
        let gym = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<SavedGym>()).first)
        XCTAssertEqual(gym.id,id);XCTAssertEqual(gym.address,"");XCTAssertEqual(gym.customGrades,["Blue"]);XCTAssertTrue(gym.isDefault)
    }
}
