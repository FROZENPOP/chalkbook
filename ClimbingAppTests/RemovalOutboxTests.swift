import Foundation
import SwiftData
import XCTest
@testable import ClimbingApp

private struct OutboxAccountVault: AccountVault {
    let value: ClimberAccount
    func load() throws -> ClimberAccount? { value }
    func save(_ account: ClimberAccount) throws {}
    func clear() throws {}
}

private final class OutboxURLProtocol: URLProtocol {
    static let lock = NSLock()
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            Self.lock.lock(); let handler = Self.handler; Self.lock.unlock()
            let (code, data) = try handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor final class RemovalOutboxTests: XCTestCase {
    private let owner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let account = ClimberAccount(provider: .google, subject: "outbox-test-account", name: "Test", email: nil)
    private var directories: [URL] = []
    private func queue(bound: Bool = true) throws -> RemovalOutbox {
        let dir = URL.temporaryDirectory.appending(path: "OutboxTests-\(UUID().uuidString)")
        directories.append(dir)
        let outbox = RemovalOutbox(accountKey: account.storageKey, directory: dir)
        if bound { try outbox.bind(owner: owner, accountKey: account.storageKey) }
        return outbox
    }
    override func tearDown() {
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }
    private func auth(_ value: ClimberAccount? = nil) -> AccountSession {
        AccountSession(vault: OutboxAccountVault(value: value ?? account), googleSignOut: {})
    }
    private func store(_ outbox: RemovalOutbox, handler: @escaping (URLRequest) throws -> (Int, Data)) -> SocialStore {
        OutboxURLProtocol.lock.lock(); OutboxURLProtocol.handler = handler; OutboxURLProtocol.lock.unlock()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OutboxURLProtocol.self]
        return SocialStore(configuration: .init(projectURL: URL(string: "https://test.invalid")!, publishableKey: "test"),
            network: URLSession(configuration: config), accountKey: account.storageKey, removals: outbox, identityToken: { _ in "test-token" })
    }
    private func token() -> Data {
        Data("{\"access_token\":\"test-token\",\"expires_in\":3600,\"user\":{\"id\":\"\(owner)\"}}".utf8)
    }
    func testEnqueueOfflineFailureAndLocalSessionDeleteSucceedsImmediately() async throws {
        let queue = try queue(), auth = auth()
        let social = store(queue) { _ in throw URLError(.notConnectedToInternet) }
        let container = try Persistence.container(inMemory: true)
        let local = ClimbingStore(context: container.mainContext)
        let session = ClimbingSession(); container.mainContext.insert(session); try container.mainContext.save()
        let id = session.id
        XCTAssertTrue(social.deleteSession(session, store: local, auth: auth))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ClimbingSession>()), 0)
        XCTAssertEqual(queue.entries.first?.contentID, id)
        await social.retryRemovals(auth, force: true)
        XCTAssertFalse(queue.entries.isEmpty); XCTAssertNotNil(queue.lastError)
        XCTAssertGreaterThan(queue.entries[0].attemptCount, 0)
    }
    func testUnshareIsDurableWithoutWaitingForNetwork() async throws {
        let queue = try queue(), social = store(try self.queue()) { _ in throw URLError(.timedOut) }
        // Use a separate queue for the actual service to ensure no shared singleton state.
        XCTAssertTrue(queue.entries.isEmpty)
        let removed = await social.removeShare(auth(), sessionID: UUID())
        XCTAssertTrue(removed); XCTAssertEqual(social.removals.entries.count, 1)
    }
    func testPersistenceAcrossRecreationAndCoalescing() throws {
        let outbox = try queue(), id = UUID()
        try outbox.enqueue(contentID: id, kind: .sessionSnapshot)
        try outbox.enqueue(contentID: id, kind: .sessionSnapshot)
        let reopened = RemovalOutbox(accountKey: account.storageKey, directory: directories.last!)
        XCTAssertEqual(reopened.entries, outbox.entries); XCTAssertEqual(reopened.entries.count, 1)
        XCTAssertEqual(reopened.ownerID, owner)
    }
    func testSuccessAndAlreadyRemovedClearDurably() async throws {
        for missing in [false, true] {
            let outbox = try queue(); try outbox.enqueue(contentID: UUID(), kind: .sessionSnapshot)
            await outbox.retry(owner: owner, accountKey: account.storageKey) { _ in
                if missing { throw RemovalHTTPError(status: 404, missingContent: true) }
            }
            XCTAssertTrue(outbox.entries.isEmpty)
            XCTAssertTrue(RemovalOutbox(accountKey: account.storageKey, directory: directories.last!).entries.isEmpty)
        }
    }
    func testHTTPNotFoundContentVersusMissingRPCAndIdempotentNoContent() async throws {
        for (status, body, clears) in [(204, "", true), (404, "{\"code\":\"PGRST116\"}", true), (404, "{\"code\":\"PGRST202\"}", false), (500, "{}", false)] {
            let queue = try queue(), token = token(), auth = auth()
            let social = store(queue) { request in request.url!.path.hasPrefix("/auth/") ? (200, token) : (status, Data(body.utf8)) }
            try await social.authorize(auth)
            try queue.enqueue(contentID: UUID(), kind: .sessionSnapshot)
            await social.retryRemovals(auth, force: true)
            XCTAssertEqual(queue.entries.isEmpty, clears, "HTTP \(status): \(body)")
        }
    }
    func testPermissionErrorsPauseAutomaticRetriesAndManualRetryCanClear() async throws {
        for code in [401, 403] {
            let outbox = try queue(); try outbox.enqueue(contentID: UUID(), kind: .sessionSnapshot)
            let now = Date(); var calls = 0
            await outbox.retry(owner: owner, accountKey: account.storageKey, now: now) { _ in calls += 1; throw RemovalHTTPError(status: code) }
            XCTAssertEqual(calls, 1); XCTAssertTrue(outbox.entries[0].needsAuthorization)
            XCTAssertGreaterThanOrEqual(outbox.entries[0].nextAttemptAt, now.addingTimeInterval(3600))
            await outbox.retry(owner: owner, accountKey: account.storageKey, now: now.addingTimeInterval(86400)) { _ in calls += 1 }
            XCTAssertEqual(calls, 1); XCTAssertNotNil(outbox.lastError)
            await outbox.retry(owner: owner, accountKey: account.storageKey, force: true) { _ in calls += 1 }
            XCTAssertEqual(calls, 2); XCTAssertTrue(outbox.entries.isEmpty)
        }
    }
    func testNetworkBackoffSurvivesReopenAndBoundsAttemptsPerTrigger() async throws {
        let outbox = try queue(); for _ in 0..<25 { try outbox.enqueue(contentID: UUID(), kind: .sessionSnapshot) }
        let now = Date(); var calls = 0
        await outbox.retry(owner: owner, accountKey: account.storageKey, now: now) { _ in calls += 1; throw URLError(.timedOut) }
        XCTAssertEqual(calls, 1); XCTAssertEqual(outbox.entries[0].attemptCount, 1)
        let reopened = RemovalOutbox(accountKey: account.storageKey, directory: directories.last!)
        XCTAssertEqual(reopened.entries[0].nextAttemptAt, outbox.entries[0].nextAttemptAt)
        // Other queued work is bounded too, even when an outage affects many removals.
        await reopened.retry(owner: owner, accountKey: account.storageKey, force: true) { _ in calls += 1 }
        XCTAssertEqual(calls, 11); XCTAssertEqual(reopened.entries.count, 15)
    }
    func testOtherOwnerOtherAccountAndGuestNeverExecute() async throws {
        let outbox = try queue(); try outbox.enqueue(contentID: UUID(), kind: .sessionSnapshot)
        var calls = 0
        for (id, key) in [(Optional(UUID()), Optional(account.storageKey)), (Optional(owner), Optional(String(repeating: "b", count: 64))), (nil, nil)] {
            await outbox.retry(owner: id, accountKey: key, force: true) { _ in calls += 1 }
        }
        XCTAssertEqual(calls, 0); XCTAssertEqual(outbox.entries.count, 1)
        let social = store(outbox) { _ in XCTFail("Must not contact server for another account/guest"); throw URLError(.cancelled) }
        await social.retryRemovals(auth(ClimberAccount(provider: .google, subject: "other", name: "Other", email: nil)), force: true)
        await social.retryRemovals(AccountSession(vault: GuestAccountVault()), force: true)
        XCTAssertEqual(outbox.entries.count, 1)
    }
    func testUnresolvedUpgradeIntentBindsOnlyAfterVerifiedSameAccount() async throws {
        let outbox = try queue(bound: false); let source = UUID()
        try outbox.enqueue(contentID: source, kind: .sessionSnapshot)
        XCTAssertNil(outbox.entries[0].ownerID)
        XCTAssertThrowsError(try outbox.bind(owner: owner, accountKey: "another-account"))
        try outbox.bind(owner: owner, accountKey: account.storageKey)
        XCTAssertEqual(outbox.entries[0].ownerID, owner); XCTAssertEqual(outbox.entries[0].contentID, source)
        XCTAssertThrowsError(try outbox.bind(owner: UUID(), accountKey: account.storageKey))
    }
    func testFeedReloadAndProfileRemovalDoNotResurrectPendingContent() async throws {
        let outbox = try queue(), session = ClimbingSession()
        let entry = SharedSession(session: session, owner: owner)
        let feed = FriendsFeed(isHidden: { outbox.hides($0) })
        let reader = OutboxFeedReader(entry: entry)
        await feed.refresh(reader); XCTAssertEqual(feed.entries.count, 1)
        try outbox.enqueue(contentID: session.id, kind: .sessionSnapshot)
        XCTAssertTrue(feed.entries.isEmpty)
        await feed.refresh(reader); XCTAssertTrue(feed.entries.isEmpty)
        try outbox.enqueue(contentID: owner, kind: .socialProfile)
        XCTAssertTrue(outbox.removingProfile)
        await outbox.retry(owner: owner, accountKey: account.storageKey) { _ in }
        XCTAssertTrue(outbox.entries.isEmpty)
    }
    func testLaunchForegroundRetryAndSuccessfulNetworkCallTriggerDrain() async throws {
        let outbox = try queue(), auth = auth(), token = token()
        let social = store(outbox) { request in request.url!.path.hasPrefix("/auth/") ? (200, token) : (204, Data()) }
        // AppRoot uses this same entry point on launch/foreground; no Friends tab is required.
        try outbox.enqueue(contentID: UUID(), kind: .sessionSnapshot)
        await social.retryRemovals(auth)
        XCTAssertTrue(outbox.entries.isEmpty)
        // A successful authenticated call schedules another bounded drain.
        try outbox.enqueue(contentID: UUID(), kind: .sessionSnapshot)
        _ = try await social.request("/rest/v1/example")
        for _ in 0..<1000 { if outbox.entries.isEmpty { break }; await Task.yield() }
        XCTAssertTrue(outbox.entries.isEmpty)
    }
    func testAccountChangeDuringAwaitCannotSendAnotherRemoval() async throws {
        let outbox = try queue(), auth = auth(), token = token()
        let social = store(outbox) { request in request.url!.path.hasPrefix("/auth/") ? (200, token) : (204, Data()) }
        try await social.authorize(auth)
        try outbox.enqueue(contentID: UUID(), kind: .sessionSnapshot)
        auth.signOut()
        await social.retryRemovals(auth, force: true)
        XCTAssertEqual(outbox.entries.count, 1)
        do { _ = try await social.request("/rest/v1/example"); XCTFail("Stale token must not run") } catch {}
    }
    func testCorruptOrUnwritableQueuePreservesLocalSessionAndFile() throws {
        let outbox = try queue(), directory = directories.last!
        let file = directory.appending(path: account.storageKey).appending(path: "removals.json")
        let damaged = Data("invalid-json".utf8); try damaged.write(to: file)
        let broken = RemovalOutbox(accountKey: account.storageKey, directory: directory)
        let social = store(broken) { _ in throw URLError(.notConnectedToInternet) }
        let container = try Persistence.container(inMemory: true), session = ClimbingSession()
        container.mainContext.insert(session); try container.mainContext.save()
        XCTAssertFalse(social.deleteSession(session, store: ClimbingStore(context: container.mainContext), auth: auth()))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ClimbingSession>()), 1)
        XCTAssertEqual(try Data(contentsOf: file), damaged); XCTAssertNotNil(broken.storageError)
        XCTAssertNotNil(outbox.ownerID)
    }
    func testRetryReopensAnUnreadableQueueEvenWithoutInMemoryEntries() async throws {
        let outbox = try queue(), directory = directories.last!, auth = auth()
        try outbox.enqueue(contentID: UUID(), kind: .sessionSnapshot)
        let file = directory.appending(path: account.storageKey).appending(path: "removals.json")
        let valid = try Data(contentsOf: file)
        try Data("broken".utf8).write(to: file)
        let reopened = RemovalOutbox(accountKey: account.storageKey, directory: directory)
        XCTAssertTrue(reopened.entries.isEmpty); XCTAssertNotNil(reopened.storageError)
        try valid.write(to: file)
        let token = token()
        let social = store(reopened) { request in request.url!.path.hasPrefix("/auth/") ? (200, token) : (204, Data()) }
        await social.retryRemovals(auth, force: true)
        XCTAssertNil(reopened.storageError); XCTAssertTrue(reopened.entries.isEmpty)
    }
    func testProfileDeletionQueuesOfflineAndClearsCascadedRemovalsAfterSuccess() async throws {
        let outbox = try queue(), auth = auth()
        let social = store(outbox) { _ in throw URLError(.notConnectedToInternet) }
        try outbox.enqueue(contentID: UUID(), kind: .sessionSnapshot)
        let queued = await social.deleteProfile(auth)
        XCTAssertTrue(queued); XCTAssertTrue(outbox.removingProfile); XCTAssertNil(social.me)
        await outbox.retry(owner: owner, accountKey: account.storageKey, force: true) { removal in
            if removal.kind == .sessionSnapshot { throw URLError(.notConnectedToInternet) }
        }
        XCTAssertTrue(outbox.removingProfile)
        // A later successful profile cascade removes all superseded intents for this owner.
        await outbox.retry(owner: owner, accountKey: account.storageKey, force: true) { _ in }
        XCTAssertTrue(outbox.entries.isEmpty)
    }
    func testManualRetryRefreshesAuthorizationAndOnlySendsSourceIdentifier() async throws {
        let outbox = try queue(), auth = auth(), token = token(), source = UUID()
        var tokenCalls = 0
        let social = store(outbox) { request in
            if request.url!.path.hasPrefix("/auth/") { tokenCalls += 1; return (200, token) }
            if request.url!.path.hasSuffix("remove_shared_session") {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
                // URLSession may present the request body as a stream; the allowlist is also checked below.
            }
            return (204, Data())
        }
        try await social.authorize(auth)
        try outbox.enqueue(contentID: source, kind: .sessionSnapshot)
        await social.retryRemovals(auth, force: true)
        XCTAssertGreaterThanOrEqual(tokenCalls, 2)
        XCTAssertTrue(outbox.entries.isEmpty)
        let encoded = try Data(contentsOf: directories.last!.appending(path: account.storageKey).appending(path: "removals.json"))
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("test-token")); XCTAssertFalse(text.contains("outbox-test-account"))
    }

    func testInFlightSocialSaveFinishesBeforeQueuedRemovalRuns() async throws {
        let outbox = try queue(), auth = auth(), token = token()
        let social = store(outbox) { request in request.url!.path.hasPrefix("/auth/") ? (200, token) : (204, Data()) }
        let saved = await social.perform(auth) {
            try outbox.enqueue(contentID: UUID(), kind: .sessionSnapshot)
            await social.retryRemovals(auth, force: true)
            XCTAssertEqual(outbox.entries[0].attemptCount, 0, "Removal cannot race an in-flight save")
        }
        XCTAssertTrue(saved)
        for _ in 0..<1000 { if outbox.entries.isEmpty { break }; await Task.yield() }
        XCTAssertTrue(outbox.entries.isEmpty, "Finishing the save schedules the deferred drain")
    }
    func testExponentialBackoffIsCapped() async throws {
        let outbox = try queue(); try outbox.enqueue(contentID: UUID(), kind: .sessionSnapshot)
        let now = Date()
        for attempt in 1...14 {
            await outbox.retry(owner: owner, accountKey: account.storageKey, force: true, now: now) { _ in throw URLError(.timedOut) }
            let delay = outbox.entries[0].nextAttemptAt.timeIntervalSince(now)
            XCTAssertEqual(delay, min(21600, 30 * pow(2, Double(min(attempt - 1, 10)))), accuracy: 0.01)
        }
        XCTAssertFalse(outbox.hasDue(now: now.addingTimeInterval(1)))
    }
    func testUnwritableQueueDoesNotAllowLocalDelete() throws {
        let directory = URL.temporaryDirectory.appending(path: "OutboxBlocked-\(UUID().uuidString)")
        directories.append(directory); try Data("file blocks directory creation".utf8).write(to: directory)
        let outbox = RemovalOutbox(accountKey: account.storageKey, directory: directory)
        let social = store(outbox) { _ in throw URLError(.notConnectedToInternet) }
        let container = try Persistence.container(inMemory: true), session = ClimbingSession()
        container.mainContext.insert(session); try container.mainContext.save()
        XCTAssertFalse(social.deleteSession(session, store: ClimbingStore(context: container.mainContext), auth: auth()))
        XCTAssertNotNil(outbox.storageError)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ClimbingSession>()), 1)
    }

    func testOldInFlightStoreCannotOverwriteNewAccountRootRemovals() async throws {
        let old = try queue(), first = UUID(), second = UUID()
        try old.enqueue(contentID: first, kind: .sessionSnapshot)
        var waiting: CheckedContinuation<Void, Never>?
        let pending = Task { await old.retry(owner: owner, accountKey: account.storageKey) { _ in
            await withCheckedContinuation { waiting = $0 }
        } }
        while waiting == nil { await Task.yield() }
        let replacement = RemovalOutbox(accountKey: account.storageKey, directory: directories.last!)
        try replacement.enqueue(contentID: second, kind: .sessionSnapshot)
        waiting?.resume(); await pending.value
        let reopened = RemovalOutbox(accountKey: account.storageKey, directory: directories.last!)
        XCTAssertEqual(reopened.entries.map(\.contentID), [second])
        XCTAssertEqual(old.entries.map(\.contentID), [second])
    }
    func testLateFailureCannotResurrectAnEntryConfirmedByReplacementStore() async throws {
        let old = try queue(); try old.enqueue(contentID: UUID(), kind: .sessionSnapshot)
        var waiting: CheckedContinuation<Void, Never>?
        let pending = Task { await old.retry(owner: owner, accountKey: account.storageKey) { _ in
            await withCheckedContinuation { waiting = $0 }; throw URLError(.timedOut)
        } }
        while waiting == nil { await Task.yield() }
        let replacement = RemovalOutbox(accountKey: account.storageKey, directory: directories.last!)
        await replacement.retry(owner: owner, accountKey: account.storageKey, force: true) { _ in }
        waiting?.resume(); await pending.value
        XCTAssertTrue(RemovalOutbox(accountKey: account.storageKey, directory: directories.last!).entries.isEmpty)
    }

    func testConcurrentRetryIsIgnoredAndEmptyQueueDoesNoWork() async throws {
        let outbox = try queue(); var calls = 0
        await outbox.retry(owner: owner, accountKey: account.storageKey) { _ in calls += 1 }
        XCTAssertEqual(calls, 0)
        try outbox.enqueue(contentID: UUID(), kind: .sessionSnapshot)
        var waiting: CheckedContinuation<Void, Never>?
        let task = Task { await outbox.retry(owner: owner, accountKey: account.storageKey) { _ in
            calls += 1; await withCheckedContinuation { waiting = $0 }
        } }
        while waiting == nil { await Task.yield() }
        await outbox.retry(owner: owner, accountKey: account.storageKey, force: true) { _ in calls += 1 }
        XCTAssertEqual(calls, 1); waiting?.resume(); await task.value
        XCTAssertTrue(outbox.entries.isEmpty)
    }
}

@MainActor private struct OutboxFeedReader: FriendsFeedReading {
    let entry: SharedSession
    func page(after: FriendsFeedCursor?, limit: Int) async throws -> FriendsFeedPage { .init(entries: [entry]) }
}
