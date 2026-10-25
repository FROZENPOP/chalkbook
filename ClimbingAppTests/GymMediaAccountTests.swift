import Foundation
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import ClimbingApp

@MainActor
final class GymMediaAccountTests: XCTestCase {
    private func store() throws -> ClimbingStore {
        let container = try Persistence.container(inMemory: true)
        return ClimbingStore(context: container.mainContext)
    }

    func testGymDefaultsAndDuplicateNames() throws {
        let store = try store()
        let first = try XCTUnwrap(store.saveGym(existing: nil, name: "  Circuit Works ", scale: .custom, customName: "Colors", grades: ["Green", "Blue"], isDefault: false))
        XCTAssertTrue(first.isDefault)
        XCTAssertEqual(try store.defaultGym()?.id, first.id)
        XCTAssertNil(store.saveGym(existing: nil, name: "circuit works", scale: .vScale, customName: "", grades: [], isDefault: false))
        let second = try XCTUnwrap(store.saveGym(existing: nil, name: "Other gym", scale: .font, customName: "", grades: [], isDefault: true))
        XCTAssertFalse(first.isDefault)
        XCTAssertTrue(second.isDefault)
        XCTAssertEqual(try store.defaultGym()?.id, second.id)
        _ = store.saveGym(existing: second, name: second.name, scale: .font, customName: "", grades: [], isDefault: false)
        XCTAssertTrue(first.isDefault)
        XCTAssertFalse(second.isDefault)
    }

    func testCustomGradeNamesStayFreeTextAndOrderedChoicesAreDeduplicated() {
        XCTAssertEqual(GymGrades.orderedLabels(from: " Green, Blue, green\nRed, ,Black "), ["Green", "Blue", "Red", "Black"])
        XCTAssertTrue(GymGrades.valid(grade: "Circuit 3+", scale: .custom, customName: "My gym"))
        XCTAssertFalse(GymGrades.valid(grade: "   ", scale: .custom, customName: "Colors"))
        XCTAssertFalse(GymGrades.valid(grade: "Blue", scale: .custom, customName: ""))
        XCTAssertFalse(GymGrades.valid(grade: "Blue", scale: .vScale, customName: "Colors"))
    }

    func testCustomProgressKeepsGymsSeparateAndDoesNotInventVConversion() {
        let first = UUID(), second = UUID()
        let summary = ProgressSummary(climbs: [
            ClimbSnapshot(scale: .custom, grade: "Red", attempts: 2, sends: 1, gymID: first, gymName: "Gym A", customScaleName: "Colors", customOrder: ["Blue", "Red"]),
            ClimbSnapshot(scale: .custom, grade: "Blue", attempts: 1, sends: 0, gymID: first, gymName: "Gym A", customScaleName: "Colors", customOrder: ["Blue", "Red"]),
            ClimbSnapshot(scale: .custom, grade: "Red", attempts: 1, sends: 1, gymID: second, gymName: "Gym B", customScaleName: "Colors")
        ])
        XCTAssertEqual(summary.customScales.count, 2)
        XCTAssertEqual(summary.customScales.first { $0.title.hasPrefix("Gym A") }?.grades.map(\.grade), ["Blue", "Red"])
        XCTAssertEqual(summary.completed, 2)
        XCTAssertNil(summary.highestSend(in: .vScale))
        XCTAssertNil(summary.highestSend(in: .custom))
    }

    func testRemovingGymPreservesHistoricalLabelsAndChangesDefault() throws {
        let store = try store()
        let gym = try XCTUnwrap(store.saveGym(existing: nil, name: "First gym", scale: .custom, customName: "Colors", grades: [], isDefault: true))
        let other = try XCTUnwrap(store.saveGym(existing: nil, name: "Second gym", scale: .vScale, customName: "", grades: [], isDefault: false))
        let session = try XCTUnwrap(store.start(date: .now, location: "", notes: "", gym: gym))
        let climb = ClimbEntry(scale: .custom, grade: "Blue")
        XCTAssertTrue(store.save {
            climb.gymID = gym.id; climb.gymName = gym.name; climb.customScaleName = "Colors"
            store.context.insert(climb); session.climbs.append(climb)
        })
        XCTAssertTrue(store.deleteGym(gym))
        XCTAssertNil(session.gymID)
        XCTAssertNil(climb.gymID)
        XCTAssertEqual(session.location, "First gym")
        XCTAssertEqual(climb.gymName, "First gym")
        XCTAssertEqual(climb.grade, "Blue")
        XCTAssertEqual(try store.defaultGym()?.id, other.id)
    }

    func testBackupIncludesGymsCustomScalesAndMediaAndRestoresTwice() throws {
        let store = try store()
        let gym = try XCTUnwrap(store.saveGym(existing: nil, name: "Gym", scale: .custom, customName: "Colors", grades: ["Blue", "Red"], isDefault: true))
        let session = try XCTUnwrap(store.start(date: .now, location: "", notes: "", gym: gym))
        let climb = ClimbEntry(scale: .custom, grade: "Blue")
        let bytes = Data([1, 2, 3, 4])
        let media = RouteMedia(kind: .photo, filename: "route.png", contentType: UTType.png.identifier, data: bytes)
        XCTAssertTrue(store.save {
            climb.gymID = gym.id; climb.gymName = gym.name; climb.customScaleName = "Colors"; climb.customGradeOrder = gym.customGrades
            store.context.insert(climb); session.climbs.append(climb)
            store.context.insert(media); climb.media.append(media)
        })
        let backup = try ClimbingBackup.decode(ClimbingBackup(sessions: [session], defaultScale: .vScale, gyms: [gym]).encoded())
        XCTAssertEqual(backup.version, 3)
        XCTAssertTrue(store.restore(backup), store.errorMessage ?? "Restore failed")
        XCTAssertTrue(store.restore(backup), store.errorMessage ?? "Second restore failed")
        let restored = try XCTUnwrap(store.context.fetch(FetchDescriptor<ClimbEntry>()).first)
        XCTAssertEqual(restored.grade, "Blue")
        XCTAssertEqual(restored.customScaleName, "Colors")
        XCTAssertEqual(restored.media.first?.data, bytes)
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<RouteMedia>()), 1)
        XCTAssertEqual(try store.defaultGym()?.name, "Gym")
        XCTAssertTrue(store.deleteAll())
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<SavedGym>()), 0)
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<RouteMedia>()), 0)
    }

    func testRejectsCorruptMediaAndMissingGymWithoutReplacingLog() throws {
        let store = try store()
        let gym = try XCTUnwrap(store.saveGym(existing: nil, name: "Keep me", scale: .vScale, customName: "", grades: [], isDefault: true))
        let session = try XCTUnwrap(store.start(date: .now, location: "", notes: "", gym: gym))
        var backup = ClimbingBackup(sessions: [session], defaultScale: .vScale, gyms: [gym])
        backup.gyms = []
        XCTAssertFalse(store.restore(backup))
        XCTAssertEqual(session.location, "Keep me")
        XCTAssertThrowsError(try RouteMediaDraft(kind: .video, filename: "bad.txt", contentType: UTType.plainText.identifier, data: Data([0])).validate())
        XCTAssertThrowsError(try RouteMediaDraft(kind: .photo, filename: "empty.png", contentType: UTType.png.identifier, data: Data()).validate())
    }

    func testVersionOneJSONBackupStillImports() throws {
        let store = try store()
        let session = try XCTUnwrap(store.start(date: .now, location: "Legacy", notes: ""))
        let data = try ClimbingBackup(sessions: [session], defaultScale: .vScale).encoded()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["version"] = 1; json.removeValue(forKey: "gyms")
        let backup = try ClimbingBackup.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(backup.gyms)
        XCTAssertTrue(store.restore(backup))
        XCTAssertEqual(try store.context.fetch(FetchDescriptor<ClimbingSession>()).first?.location, "Legacy")
    }

    func testVersionOneDatabaseMigratesWithoutLosingClimbs() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "migration.store")
        try autoreleasepool {
            let schema = Schema(versionedSchema: ClimbingSchemaV1.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let session = ClimbingSchemaV1.ClimbingSession(location: "Legacy gym")
            let climb = ClimbingSchemaV1.ClimbEntry(grade: "V4")
            let attempt = ClimbingSchemaV1.ClimbAttempt(sequence: 1, sent: true)
            old.mainContext.insert(session); old.mainContext.insert(climb); old.mainContext.insert(attempt)
            session.climbs.append(climb); climb.attempts.append(attempt)
            try old.mainContext.save()
        }
        let schema = Schema(versionedSchema: ClimbingSchemaV5.self)
        let updated = try ModelContainer(for: schema, migrationPlan: ClimbingMigrationPlan.self,
                                         configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let session = try XCTUnwrap(updated.mainContext.fetch(FetchDescriptor<ClimbingSession>()).first)
        XCTAssertEqual(session.location, "Legacy gym")
        XCTAssertEqual(session.climbs.first?.grade, "V4")
        XCTAssertEqual(session.sendCount, 1)
        XCTAssertTrue(session.climbs[0].media.isEmpty)
        XCTAssertNil(session.gymID)
    }

    func testAccountStorageKeysSeparateProvidersAndAvoidRawIdentityInPaths() {
        let apple = ClimberAccount(provider: .apple, subject: "same-id", name: "Person", email: nil)
        let google = ClimberAccount(provider: .google, subject: "same-id", name: "Person", email: nil)
        XCTAssertNotEqual(apple.storageKey, google.storageKey)
        XCTAssertEqual(apple.storageKey.count, 64)
        XCTAssertFalse(apple.storageKey.contains("same-id"))
    }

    func testSignOutClearsSavedAccountAndDoesNotPretendToSucceedOnVaultFailure() {
        let vault = TestAccountVault()
        vault.account = ClimberAccount(provider: .apple, subject: "test", name: "Climber", email: nil)
        let auth = AccountSession(vault: vault, googleSignOut: {})
        XCTAssertNotNil(auth.account)
        vault.failClear = true
        auth.signOut()
        XCTAssertNotNil(auth.account)
        XCTAssertNotNil(auth.errorMessage)
        vault.failClear = false
        auth.signOut()
        XCTAssertNil(auth.account)
        XCTAssertNil(vault.account)
        XCTAssertNil(auth.errorMessage)
    }
}

private final class TestAccountVault: AccountVault {
    var account: ClimberAccount?
    var failClear = false
    func load() throws -> ClimberAccount? { account }
    func save(_ account: ClimberAccount) throws { self.account = account }
    func clear() throws {
        if failClear { throw AccountError.keychain(-1) }
        account = nil
    }
}

@MainActor
final class AccountDataIsolationTests: XCTestCase {
    func testAccountsAndGuestKeepSeparateLogsOnDisk() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let apple = ClimberAccount(provider: .apple, subject: "test-person", name: "A", email: nil)
        let google = ClimberAccount(provider: .google, subject: "test-person", name: "A", email: nil)
        let first = try Persistence.container(accountKey: apple.storageKey, rootDirectory: root)
        let firstStore = ClimbingStore(context: first.mainContext)
        XCTAssertNotNil(firstStore.start(date: .now, location: "Private gym", notes: ""))
        let second = try Persistence.container(accountKey: google.storageKey, rootDirectory: root)
        XCTAssertEqual(try second.mainContext.fetchCount(FetchDescriptor<ClimbingSession>()), 0)
        let guest = try Persistence.container(rootDirectory: root)
        XCTAssertEqual(try guest.mainContext.fetchCount(FetchDescriptor<ClimbingSession>()), 0)
        let reopened = try Persistence.container(accountKey: apple.storageKey, rootDirectory: root)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<ClimbingSession>()).first?.location, "Private gym")
    }

    func testAccountStorageRejectsInvalidPathComponents() throws {
        XCTAssertThrowsError(try Persistence.container(accountKey: "../other-data"))
    }
}
