import CryptoKit
import XCTest
@testable import ClimbingApp

@MainActor final class GoogleNonceTests: XCTestCase {
    private let refreshMessage = "Google sign-in needs refreshing. Sign out and sign in with Google again."
    // A distinct service keeps signOut away from every real Friends session.
    private func session() -> AccountSession {
        AccountSession(vault: GuestAccountVault(), googleSignOut: {}, friendsSessions: FriendsSessionVault(service: "com.frozenpop.ClimbingApp.tests.\(UUID().uuidString)"))
    }

    /// An unsigned JWT with an unpadded base64url payload, like Google's.
    static func jwt(_ claims: [String: Any]) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: claims).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJSUzI1NiJ9.\(payload).signature"
    }

    private func problem(_ auth: AccountSession, _ token: String) -> String? {
        do { _ = try auth.friendsNonce(for: token); return nil } catch { return SocialError.message(for: error) }
    }

    func testSDKGetsTheSHA256HexOfTheKeptNonce() throws {
        let auth = session(), hashed = auth.newGoogleNonce()
        XCTAssertEqual(hashed.count, 64); XCTAssertEqual(hashed, hashed.lowercased())
        let raw = try XCTUnwrap(auth.friendsNonce(for: Self.jwt(["nonce": hashed])))
        XCTAssertEqual(SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined(), hashed)
        XCTAssertNotEqual(raw, hashed)
    }

    func testTokensWithoutANonceClaimNeedNone() throws {
        let auth = session()
        _ = auth.newGoogleNonce()
        XCTAssertNil(try auth.friendsNonce(for: "google-jwt"), "Test stubs aren't JWTs")
        XCTAssertNil(try auth.friendsNonce(for: "a.%%%.c"))
        XCTAssertNil(try auth.friendsNonce(for: Self.jwt(["sub": "google-test", "name": "Ada ✓"])), "Tokens refreshed by Google carry no nonce")
    }

    func testMatchingClaimReturnsTheRawNonceOfTheLatestSignIn() throws {
        let auth = session(), first = auth.newGoogleNonce(), second = auth.newGoogleNonce()
        XCTAssertNotEqual(first, second)
        let raw = try XCTUnwrap(auth.friendsNonce(for: Self.jwt(["sub": "google-test", "nonce": second])))
        XCTAssertEqual(raw.count, 64)
        XCTAssertEqual(problem(auth, Self.jwt(["nonce": first])), refreshMessage, "Each sign-in replaces the nonce")
    }

    func testUnmatchedClaimAsksToSignInWithGoogleAgain() {
        let auth = session()
        XCTAssertEqual(problem(auth, Self.jwt(["nonce": "restored-after-relaunch"])), refreshMessage)
        _ = auth.newGoogleNonce()
        XCTAssertEqual(problem(auth, Self.jwt(["nonce": "someone-else"])), refreshMessage)
    }

    func testSignOutForgetsTheNonce() {
        let auth = session(), hashed = auth.newGoogleNonce()
        auth.signOut()
        XCTAssertEqual(problem(auth, Self.jwt(["nonce": hashed])), refreshMessage)
    }
}
