import Foundation
import SwiftData
import UIKit
import XCTest
@testable import ClimbingApp

private struct FixedVault: AccountVault {
    let value: ClimberAccount?
    func load() throws -> ClimberAccount? { value }
    func save(_ account: ClimberAccount) throws {}
    func clear() throws {}
}

private final class ShareURLProtocol: URLProtocol {
    static let lock = NSLock()
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var calls: [(path: String, query: String, values: [String: Any])] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; body.append(buffer, count: n) }
        }
        do {
            let values = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
            Self.lock.lock(); Self.calls.append((request.url!.path, request.url!.query ?? "", values)); let handler = Self.handler; Self.lock.unlock()
            let (code, data) = try handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor final class ShareSyncTests: XCTestCase {
    private let apple = ClimberAccount(provider: .apple, subject: "share-sync-subject", name: "Ada", email: nil)
    // A distinct service keeps these tests away from every real Friends session.
    private let sessions = FriendsSessionVault(service: "com.frozenpop.ClimbingApp.tests.\(UUID().uuidString)")
    private let owner = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
    private var calls: [(path: String, query: String, values: [String: Any])] { ShareURLProtocol.lock.withLock { ShareURLProtocol.calls } }
    private var saves: [[String: Any]] { calls.filter { $0.path == "/rest/v1/rpc/save_shared_session_with_photos" }.map(\.values) }
    override func tearDown() { sessions.clear(); super.tearDown() }

    /// A signed-in Friends store whose server holds `row`, or no row, for any session.
    private func makeSocial(row: SharedSession? = nil, configured: Bool = true) throws -> (SocialStore, AccountSession) {
        sessions.save("refresh-1", for: apple.storageKey)
        let rows = try JSONEncoder().encode(row.map { [$0] } ?? [])
        ShareURLProtocol.lock.withLock {
            ShareURLProtocol.calls = []
            ShareURLProtocol.handler = { request in
                switch request.url!.path {
                case "/auth/v1/token": (200, Data("{\"access_token\":\"access\",\"refresh_token\":\"refresh-2\",\"expires_in\":3600,\"user\":{\"id\":\"00000000-0000-0000-0000-000000000009\"}}".utf8))
                case "/rest/v1/shared_sessions": (200, rows)
                case "/rest/v1/rpc/remove_shared_session": (500, Data()) // Keeps the removal queued so the test can see it.
                case "/rest/v1/rpc/save_shared_session_with_photos": (200, Data("null".utf8))
                default: (200, Data("[]".utf8))
                }
            }
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ShareURLProtocol.self]
        let store = SocialStore(configuration: configured ? .init(projectURL: URL(string: "https://test.invalid")!, publishableKey: "test") : nil,
                                network: URLSession(configuration: config), accountKey: apple.storageKey,
                                removals: RemovalOutbox(accountKey: apple.storageKey, directory: URL.temporaryDirectory.appending(path: "ShareSync-\(UUID().uuidString)")),
                                sessions: sessions, identityToken: { _ in "unused" })
        return (store, AccountSession(vault: FixedVault(value: apple), googleSignOut: {}, friendsSessions: sessions))
    }

    private func jpeg(width: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: 80), format: format).image { context in
            UIColor.lightGray.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: 80))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
    }

    // Stores keep their containers, and the sessions in them, alive until the test ends.
    private var stores: [ClimbingStore] = []
    private func makeStore() throws -> ClimbingStore {
        let container = try Persistence.container(inMemory: true)
        stores.append(ClimbingStore(context: container.mainContext))
        return stores[stores.count - 1]
    }

    /// A finished 90-minute session with one sent climb per photo, in climb order, and a video first on climb 1.
    private func makeSession(_ visibility: EntryVisibility?, photos: [Data]) throws -> (ClimbingStore, ClimbingSession) {
        let store = try makeStore()
        let session = try XCTUnwrap(store.createRecap(date: .now.addingTimeInterval(-7200), gym: nil, location: "Share gym", notes: "Private notes", minutes: 90))
        session.visibility = visibility
        for (index, data) in photos.enumerated() {
            let climb = ClimbEntry(label: "Climb \(index + 1)"); climb.createdAt = .now.addingTimeInterval(Double(index))
            store.context.insert(climb); session.climbs.append(climb)
            if index == 0 { climb.media.append(RouteMedia(kind: .video, filename: "v.mov", contentType: "public.movie", data: Data([0, 1]))) }
            climb.media.append(RouteMedia(kind: .photo, filename: "\(index).jpg", contentType: "public.jpeg", data: data))
            let attempt = ClimbAttempt(sequence: 1, sent: true); attempt.sessionID = session.id; climb.attempts.append(attempt)
        }
        try store.context.save()
        return (store, session)
    }

    private func widths(_ values: [String: Any]) throws -> [Int] {
        try XCTUnwrap(values["photos"] as? [[String: Any]]).map { photo in
            let data = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(photo["original_base64"] as? String)))
            return try XCTUnwrap(UIImage(data: data)?.cgImage?.width)
        }
    }

    func testV7StoreOpensAsV8WithEverythingKept() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionID = UUID(), climbID = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema: ClimbingSchemaV7.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: root.appending(path: "Guest.store"), cloudKitDatabase: .none)])
            let session = ClimbingSchemaV7.ClimbingSession(id: sessionID, location: "V7 gym"); session.isComplete = true
            let climb = ClimbingSchemaV7.ClimbEntry(id: climbID, grade: "V5")
            let attempt = ClimbingSchemaV7.ClimbAttempt(sequence: 1, sent: true)
            let photo = ClimbingSchemaV7.RouteMedia(kind: .photo, filename: "p.jpg", contentType: "public.jpeg", data: Data([1, 2, 3]))
            let video = ClimbingSchemaV7.RouteMedia(kind: .video, filename: "v.mov", contentType: "public.movie", data: Data([4, 5]))
            old.mainContext.insert(session); old.mainContext.insert(climb); old.mainContext.insert(attempt)
            old.mainContext.insert(photo); old.mainContext.insert(video)
            session.climbs.append(climb); climb.attempts.append(attempt); climb.media = [photo, video]
            try old.mainContext.save()
        }
        let container = try Persistence.container(rootDirectory: root), context = container.mainContext
        let sessions = try context.fetch(FetchDescriptor<ClimbingSession>())
        XCTAssertEqual(sessions.map(\.id), [sessionID])
        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.location, "V7 gym"); XCTAssertTrue(session.isComplete); XCTAssertEqual(session.sendCount, 1)
        XCTAssertEqual(session.climbs.map(\.id), [climbID])
        XCTAssertEqual(Set(session.climbs[0].media.map(\.data)), [Data([1, 2, 3]), Data([4, 5])])
        XCTAssertEqual(Set(session.climbs[0].media.map(\.kind)), [.photo, .video])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RouteMedia>()), 2)
        XCTAssertNil(session.shareVisibility); XCTAssertNil(session.visibility); XCTAssertEqual(session.shareCaption, "")
        XCTAssertTrue(session.shareAttempts && session.shareSends && session.shareDuration && session.sharePhotos)
    }

    func testBackupKeepsShareSettingsAndOldBackupsGetDefaults() throws {
        let (_, session) = try makeSession(.public, photos: [])
        session.shareCaption = "Good day"; session.shareAttempts = false; session.shareSends = false
        session.shareDuration = false; session.sharePhotos = false
        let data = try ClimbingBackup(sessions: [session], defaultScale: .vScale).encoded()

        let restored = try makeStore()
        XCTAssertTrue(restored.restore(try ClimbingBackup.decode(data)), restored.errorMessage ?? "")
        let copy = try XCTUnwrap(restored.context.fetch(FetchDescriptor<ClimbingSession>()).first)
        XCTAssertEqual(copy.visibility, .public); XCTAssertEqual(copy.shareCaption, "Good day")
        XCTAssertFalse(copy.shareAttempts || copy.shareSends || copy.shareDuration || copy.sharePhotos)

        // The same backup as an older app wrote it: no share keys at all.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var journal = try XCTUnwrap(json["journal"] as? [String: Any])
        journal["sessions"] = try XCTUnwrap(journal["sessions"] as? [[String: Any]]).map { $0.filter { !$0.key.hasPrefix("share") } }
        json["journal"] = journal
        let old = try JSONSerialization.data(withJSONObject: json)
        XCTAssertFalse(String(decoding: old, as: UTF8.self).contains("share"))
        let older = try makeStore()
        XCTAssertTrue(older.restore(try ClimbingBackup.decode(old)), older.errorMessage ?? "")
        let plain = try XCTUnwrap(older.context.fetch(FetchDescriptor<ClimbingSession>()).first)
        XCTAssertNil(plain.shareVisibility); XCTAssertEqual(plain.shareCaption, "")
        XCTAssertTrue(plain.shareAttempts && plain.shareSends && plain.shareDuration && plain.sharePhotos)
    }

    func testStartAndRecapStoreTheChosenVisibility() throws {
        let store = try makeStore()
        let live = try XCTUnwrap(store.start(date: .now, location: "Gym", notes: "", visibility: .friends))
        XCTAssertEqual(live.shareVisibility, "friends")
        store.finish(live)
        XCTAssertEqual(try XCTUnwrap(store.start(date: .now, location: "Gym", notes: "")).visibility, .private)
        XCTAssertEqual(store.createRecap(date: .now, gym: nil, location: "Gym", notes: "", minutes: 60, visibility: .public)?.visibility, .public)
        XCTAssertEqual(store.createRecap(date: .now, gym: nil, location: "Gym", notes: "", minutes: 60)?.visibility, .private)
    }

    func testSyncMakesNoCallWhenThereIsNothingToSync() async throws {
        let (_, finished) = try makeSession(.friends, photos: [])
        let (_, chosenNothing) = try makeSession(nil, photos: [])
        let liveStore = try makeStore()
        let live = try XCTUnwrap(liveStore.start(date: .now, location: "Live", notes: "", visibility: .friends))
        let (unconfigured, _) = try makeSocial(configured: false)
        let (signedIn, auth) = try makeSocial()
        let signedOut = AccountSession(vault: FixedVault(value: nil), googleSignOut: {}, friendsSessions: sessions)
        for (store, account, session) in [(signedIn, signedOut, finished), (unconfigured, auth, finished), (signedIn, auth, live), (signedIn, auth, chosenNothing)] {
            let synced = await store.syncShare(account, session: session)
            XCTAssertTrue(synced)
        }
        XCTAssertTrue(calls.isEmpty)
    }

    func testFriendsPostSendsTheChosenFieldsAndFirstThreePhotosInClimbOrder() async throws {
        let (_, session) = try makeSession(.friends, photos: [jpeg(width: 120), jpeg(width: 130), jpeg(width: 140), jpeg(width: 150)])
        session.shareCaption = "Fun"; session.shareSends = false
        let (social, auth) = try makeSocial()
        let synced = await social.syncShare(auth, session: session)
        XCTAssertTrue(synced, social.errorMessage ?? "")
        XCTAssertEqual(saves.count, 1)
        let body = try XCTUnwrap(saves.first)
        XCTAssertEqual(body["visibility"] as? String, "friends"); XCTAssertEqual(body["caption"] as? String, "Fun")
        XCTAssertEqual(body["source_session_id"] as? String, session.id.uuidString)
        XCTAssertEqual(body["attempts"] as? Int, 4); XCTAssertTrue(body["sends"] is NSNull); XCTAssertEqual(body["duration_minutes"] as? Int, 90)
        XCTAssertEqual(try widths(body), [120, 130, 140])
        XCTAssertNil(social.photoNotice)
    }

    func testPublicPostUpdatesTheExistingServerRow() async throws {
        let (_, session) = try makeSession(.public, photos: [jpeg(width: 120)])
        session.shareDuration = false
        var row = SharedSession(session: session, owner: owner); row.visibility = .friends; row.caption = "Old"; row.sends = nil
        let (social, auth) = try makeSocial(row: row)
        let synced = await social.syncShare(auth, session: session)
        XCTAssertTrue(synced, social.errorMessage ?? "")
        XCTAssertEqual(calls.filter { $0.query.contains("source_session_id=eq.\(session.id.uuidString)") }.count, 1)
        XCTAssertEqual(saves.count, 1)
        let body = try XCTUnwrap(saves.first)
        XCTAssertEqual(body["visibility"] as? String, "public"); XCTAssertEqual(body["caption"] as? String, "")
        XCTAssertTrue(body["duration_minutes"] is NSNull); XCTAssertEqual(body["sends"] as? Int, 1, "values come from the journal, not the old row")
        XCTAssertEqual(try widths(body), [120])
    }

    func testPhotosOffSendsAnEmptyPhotoList() async throws {
        let (_, session) = try makeSession(.friends, photos: [jpeg(width: 120)])
        session.sharePhotos = false
        let (social, auth) = try makeSocial()
        let synced = await social.syncShare(auth, session: session)
        XCTAssertTrue(synced, social.errorMessage ?? "")
        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual((saves.first?["photos"] as? [Any])?.count, 0)
    }

    func testUnpreparablePhotoIsSkippedAndNamed() async throws {
        let (_, session) = try makeSession(.friends, photos: [jpeg(width: 120), Data([1, 2, 3]), jpeg(width: 140)])
        let (social, auth) = try makeSocial()
        let synced = await social.syncShare(auth, session: session)
        XCTAssertTrue(synced, social.errorMessage ?? "")
        XCTAssertEqual(try widths(try XCTUnwrap(saves.first)), [120, 140])
        XCTAssertTrue(social.photoNotice?.contains("Climb 2") == true, social.photoNotice ?? "no notice")
    }

    func testPrivateRemovesOnlyAPostThatExists() async throws {
        let (_, shared) = try makeSession(.private, photos: [])
        let (social, auth) = try makeSocial(row: SharedSession(session: shared, owner: owner))
        let removed = await social.syncShare(auth, session: shared)
        XCTAssertTrue(removed, social.errorMessage ?? "")
        XCTAssertTrue(social.removals.contains(sessionID: shared.id))
        XCTAssertTrue(saves.isEmpty)

        let (_, never) = try makeSession(.private, photos: [])
        let (fresh, freshAuth) = try makeSocial()
        let synced = await fresh.syncShare(freshAuth, session: never)
        XCTAssertTrue(synced, fresh.errorMessage ?? "")
        XCTAssertTrue(fresh.removals.entries.isEmpty)
        XCTAssertFalse(calls.contains { $0.path.hasPrefix("/rest/v1/rpc/") && $0.values["source_id"] as? String == never.id.uuidString })
    }

    func testAdoptFillsSettingsFromTheServerOnlyWhenNoneAreChosen() async throws {
        let (_, session) = try makeSession(nil, photos: [jpeg(width: 120)])
        var row = SharedSession(session: session, owner: owner)
        row.visibility = .public; row.caption = "From server"; row.sends = nil; row.route_photo_count = 0
        let (social, auth) = try makeSocial(row: row)
        await social.adoptShare(auth, session: session)
        XCTAssertEqual(session.visibility, .public); XCTAssertEqual(session.shareCaption, "From server")
        XCTAssertTrue(session.shareAttempts); XCTAssertFalse(session.shareSends); XCTAssertTrue(session.shareDuration); XCTAssertFalse(session.sharePhotos)

        session.visibility = .friends
        let before = calls.count
        await social.adoptShare(auth, session: session)
        XCTAssertEqual(session.visibility, .friends); XCTAssertEqual(calls.count, before)

        let (_, unshared) = try makeSession(nil, photos: [])
        let (empty, emptyAuth) = try makeSocial()
        await empty.adoptShare(emptyAuth, session: unshared)
        XCTAssertEqual(unshared.visibility, .private); XCTAssertEqual(unshared.shareCaption, "")
    }
}
