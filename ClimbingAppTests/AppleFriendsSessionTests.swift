import Foundation
import XCTest
@testable import ClimbingApp

private struct FixedVault: AccountVault {
    let value: ClimberAccount
    func load() throws -> ClimberAccount? { value }
    func save(_ account: ClimberAccount) throws {}
    func clear() throws {}
}

private final class TokenURLProtocol: URLProtocol {
    static let lock = NSLock()
    static var handler: ((URLRequest, [String: Any]) throws -> (Int, Data))?
    nonisolated(unsafe) static var calls: [(grant: String, values: [String: Any])] = []
    nonisolated(unsafe) static var paths: [String] = []
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
            Self.lock.lock(); let handler = Self.handler; Self.lock.unlock()
            let values = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
            let (code, data) = try handler!(request, values)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor final class AppleFriendsSessionTests: XCTestCase {
    private let apple = ClimberAccount(provider: .apple, subject: "apple-test-subject", name: "Ada", email: "ada@example.com")
    // A distinct service keeps these tests away from every real Friends session.
    private let sessions = FriendsSessionVault(service: "com.frozenpop.ClimbingApp.tests.\(UUID().uuidString)")
    private var calls: [(grant: String, values: [String: Any])] { TokenURLProtocol.lock.withLock { TokenURLProtocol.calls } }
    override func tearDown() { sessions.clear(); super.tearDown() }

    private func auth(_ account: ClimberAccount) -> AccountSession {
        AccountSession(vault: FixedVault(value: account), googleSignOut: {}, friendsSessions: sessions)
    }
    private func store(_ account: ClimberAccount, identityToken: ((AccountSession) async throws -> String)? = nil, failing: String? = nil,
                       respond: @escaping @Sendable (String) throws -> (Int, Data)) -> SocialStore {
        TokenURLProtocol.lock.lock()
        TokenURLProtocol.calls = []
        TokenURLProtocol.paths = []
        TokenURLProtocol.handler = { request, values in
            let grant = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "grant_type" }?.value ?? ""
            TokenURLProtocol.lock.withLock { TokenURLProtocol.calls.append((grant, values)); TokenURLProtocol.paths.append(request.url!.path) }
            if let failing, request.url!.path.contains(failing) { return (500, Data()) }
            return try respond(grant)
        }
        TokenURLProtocol.lock.unlock()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [TokenURLProtocol.self]
        let dir = URL.temporaryDirectory.appending(path: "AppleFriends-\(UUID().uuidString)")
        return SocialStore(configuration: .init(projectURL: URL(string: "https://test.invalid")!, publishableKey: "test"),
                           network: URLSession(configuration: config), accountKey: account.storageKey,
                           removals: RemovalOutbox(accountKey: account.storageKey, directory: dir), sessions: sessions,
                           identityToken: identityToken ?? { try await $0.identityTokenForFriends() })
    }
    nonisolated private func token(_ refresh: String) -> (Int, Data) {
        (200, Data("{\"access_token\":\"access\",\"refresh_token\":\"\(refresh)\",\"expires_in\":3600,\"user\":{\"id\":\"00000000-0000-0000-0000-000000000009\"}}".utf8))
    }

    func testAppleAccountWithoutSessionAsksAppleToConfirmWithoutCallingServer() async {
        let auth = auth(apple), social = store(apple) { _ in self.token("unused") }
        let ok = await social.perform(auth) {}
        XCTAssertFalse(ok); XCTAssertTrue(social.needsAppleSignIn)
        XCTAssertEqual(social.errorMessage, SocialError.appleSignIn.localizedDescription)
        XCTAssertTrue(calls.isEmpty)
    }

    func testAppleConfirmationExchangesAppleTokenKeepsProfileAndSavesSession() async {
        let auth = auth(apple), social = store(apple) { _ in self.token("refresh-1") }
        auth.completeApple(subject: apple.subject, name: nil, email: nil, identityToken: "apple-jwt")
        XCTAssertEqual(auth.account?.name, "Ada"); XCTAssertEqual(auth.account?.email, "ada@example.com")
        let ok = await social.perform(auth) {}
        XCTAssertTrue(ok); XCTAssertFalse(social.needsAppleSignIn)
        XCTAssertEqual(calls.map(\.grant), ["id_token"])
        XCTAssertEqual(calls.first?.values["provider"] as? String, "apple")
        XCTAssertEqual(calls.first?.values["id_token"] as? String, "apple-jwt")
        XCTAssertEqual(sessions.load(apple.storageKey), "refresh-1")
        // The Apple token is single use.
        let again = try? await auth.identityTokenForFriends()
        XCTAssertNil(again)
    }

    func testRelaunchReconnectsWithSavedSessionAndStoresTheRotatedOne() async {
        sessions.save("refresh-1", for: apple.storageKey)
        let auth = auth(apple), social = store(apple) { _ in self.token("refresh-2") }
        let ok = await social.perform(auth) {}
        XCTAssertTrue(ok)
        XCTAssertEqual(calls.map(\.grant), ["refresh_token"])
        XCTAssertEqual(calls.first?.values["refresh_token"] as? String, "refresh-1")
        XCTAssertEqual(sessions.load(apple.storageKey), "refresh-2")
    }

    func testRevokedSessionFallsBackToSignInToken() async {
        let google = ClimberAccount(provider: .google, subject: "google-test", name: "G", email: nil)
        sessions.save("revoked", for: google.storageKey)
        let auth = auth(google)
        let social = store(google, identityToken: { _ in "google-jwt" }) { grant in grant == "refresh_token" ? (400, Data("{}".utf8)) : self.token("fresh") }
        let ok = await social.perform(auth) {}
        XCTAssertTrue(ok)
        XCTAssertEqual(calls.map(\.grant), ["refresh_token", "id_token"])
        XCTAssertEqual(calls.last?.values["provider"] as? String, "google")
        XCTAssertEqual(sessions.load(google.storageKey), "fresh")
    }

    func testOfflineKeepsSavedSession() async {
        sessions.save("refresh-1", for: apple.storageKey)
        let auth = auth(apple), social = store(apple) { _ in throw URLError(.notConnectedToInternet) }
        let ok = await social.perform(auth) {}
        XCTAssertFalse(ok); XCTAssertFalse(social.needsAppleSignIn)
        XCTAssertEqual(sessions.load(apple.storageKey), "refresh-1")
    }

    func testSignOutForgetsFriendsSessions() {
        sessions.save("refresh-1", for: apple.storageKey)
        let auth = auth(apple)
        auth.completeApple(subject: apple.subject, name: nil, email: nil, identityToken: "apple-jwt")
        auth.signOut()
        XCTAssertNil(sessions.load(apple.storageKey))
    }

    func testAppleIDConfirmedThisRunSurvivesAStaleRevokedState() async {
        let auth = auth(apple)
        auth.appleCredentialRevoked()
        XCTAssertNil(auth.account, "A saved Apple ID that Apple revoked signs out")
        auth.completeApple(subject: apple.subject, name: nil, email: nil, identityToken: "apple-jwt")
        auth.appleCredentialRevoked()
        await auth.verifyExistingSession()
        XCTAssertEqual(auth.account?.subject, apple.subject)
    }

    func testOnlyANewSignInAsksForProfileSetup() {
        let auth = auth(apple)
        XCTAssertFalse(auth.takeFreshSignIn(), "A saved account at launch isn't a new sign-in")
        auth.completeApple(subject: apple.subject, name: nil, email: nil, identityToken: "apple-jwt")
        XCTAssertFalse(auth.takeFreshSignIn(), "Confirming the same Apple ID again isn't a new sign-in")
        auth.signOut()
        auth.completeApple(subject: apple.subject, name: nil, email: nil, identityToken: "apple-jwt")
        XCTAssertTrue(auth.takeFreshSignIn())
        XCTAssertFalse(auth.takeFreshSignIn(), "Setup opens once per sign-in")
    }

    func testAppleAccountDeletionConfirmsThenDeletesAndSignsOut() async {
        let auth = auth(apple)
        let social = store(apple) { grant in grant.isEmpty ? (200, Data()) : self.token("refresh-1") }
        let refused = await social.deleteAccount(auth)
        XCTAssertFalse(refused); XCTAssertTrue(social.needsAppleSignIn); XCTAssertNotNil(auth.account)
        auth.completeApple(subject: apple.subject, name: nil, email: nil, identityToken: "apple-jwt")
        let deleted = await social.deleteAccount(auth)
        XCTAssertTrue(deleted); XCTAssertNil(auth.account); XCTAssertNil(sessions.load(apple.storageKey))
        XCTAssertEqual(calls.map(\.grant), ["id_token", ""])
    }

    func testAppleDeletionRevokesTheGrantBeforeDeletingTheAccount() async {
        let auth = auth(apple)
        let social = store(apple) { grant in grant.isEmpty ? (200, Data()) : self.token("refresh-1") }
        auth.completeApple(subject: apple.subject, name: nil, email: nil, identityToken: "apple-jwt", authorizationCode: "apple-code")
        let deleted = await social.deleteAccount(auth)
        XCTAssertTrue(deleted); XCTAssertNil(auth.account); XCTAssertNil(auth.errorMessage)
        XCTAssertEqual(TokenURLProtocol.lock.withLock { TokenURLProtocol.paths }, ["/auth/v1/token", "/functions/v1/revoke-apple", "/rest/v1/rpc/delete_account"])
        XCTAssertEqual(calls[1].values["authorization_code"] as? String, "apple-code")
    }

    func testFailedAppleRevokeStillDeletesTheAccountAndSaysWhatRemains() async {
        let auth = auth(apple)
        let social = store(apple, failing: "revoke-apple") { grant in grant.isEmpty ? (200, Data()) : self.token("refresh-1") }
        auth.completeApple(subject: apple.subject, name: nil, email: nil, identityToken: "apple-jwt", authorizationCode: "apple-code")
        let deleted = await social.deleteAccount(auth)
        XCTAssertTrue(deleted); XCTAssertNil(auth.account)
        XCTAssertTrue(TokenURLProtocol.lock.withLock { TokenURLProtocol.paths }.contains("/rest/v1/rpc/delete_account"))
        XCTAssertEqual(auth.errorMessage?.contains("Sign in with Apple"), true)
    }

    func testFailedDeletionNeedsAFreshAppleCode() async {
        let auth = auth(apple)
        let social = store(apple, failing: "delete_account") { grant in grant.isEmpty ? (200, Data()) : self.token("refresh-1") }
        auth.completeApple(subject: apple.subject, name: nil, email: nil, identityToken: "apple-jwt", authorizationCode: "apple-code")
        let deleted = await social.deleteAccount(auth)
        XCTAssertFalse(deleted); XCTAssertNotNil(auth.account)
        XCTAssertNil(auth.takeAppleAuthorizationCode(), "Apple codes are single use")
    }

    func testReportSendsTheCommentAndPingsTheModerator() async {
        let auth = auth(apple), target = UUID(), comment = UUID()
        auth.completeApple(subject: apple.subject, name: nil, email: nil, identityToken: "apple-jwt")
        // The refresh after a report needs real rows, so it fails here; only what was sent matters.
        let social = store(apple) { grant in grant.isEmpty ? (200, Data("[]".utf8)) : self.token("refresh-1") }
        await social.safetyAction(auth, target: target, block: false, reason: "Rude", comment: comment)
        XCTAssertEqual(calls[1].values["target"] as? String, target.uuidString)
        XCTAssertEqual(calls[1].values["comment"] as? String, comment.uuidString)
        XCTAssertNil(calls[1].values["entry"])
        XCTAssertEqual(TokenURLProtocol.lock.withLock { TokenURLProtocol.paths }.prefix(3), ["/auth/v1/token", "/rest/v1/rpc/report_climber", "/functions/v1/report-alert"])
    }

    func testBlockedWordsExplainThemselves() async {
        let auth = auth(apple)
        auth.completeApple(subject: apple.subject, name: nil, email: nil, identityToken: "apple-jwt")
        let social = store(apple) { grant in grant.isEmpty ? (400, Data("{\"code\":\"SN001\"}".utf8)) : self.token("refresh-1") }
        let ok = await social.perform(auth) { _ = try await social.request("/rest/v1/rpc/add_session_comment", method: "POST", values: [:]) }
        XCTAssertFalse(ok); XCTAssertEqual(social.errorMessage, SocialError.contentRejected.localizedDescription)
    }
}
