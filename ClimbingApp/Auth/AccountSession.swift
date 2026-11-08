import AuthenticationServices
import CryptoKit
import Foundation
import GoogleSignIn
import Observation
import Security
import UIKit

enum LoginProvider: String, Codable { case apple, google }

struct ClimberAccount: Codable, Equatable {
    let provider: LoginProvider
    let subject: String
    let name: String
    let email: String?

    var storageKey: String { sha256Hex("\(provider.rawValue):\(subject)") }
}

func sha256Hex(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }

protocol AccountVault {
    func load() throws -> ClimberAccount?
    func save(_ account: ClimberAccount) throws
    func clear() throws
}

struct GuestAccountVault: AccountVault {
    func load() throws -> ClimberAccount? { nil }
    func save(_ account: ClimberAccount) throws { throw AccountError.unavailable }
    func clear() throws {}
}

struct KeychainAccountVault: AccountVault {
    let service: String
    init(service: String = "com.frozenpop.ClimbingApp.account") { self.service = service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "current-account"]
    }

    func load() throws -> ClimberAccount? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw AccountError.keychain(status) }
        return try JSONDecoder().decode(ClimberAccount.self, from: data)
    }

    func save(_ account: ClimberAccount) throws {
        let data = try JSONEncoder().encode(account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let result = SecItemAdd(item as CFDictionary, nil)
            guard result == errSecSuccess else { throw AccountError.keychain(result) }
        } else if status != errSecSuccess { throw AccountError.keychain(status) }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountError.keychain(status) }
    }
}

/// The Friends refresh token per account. Apple can't silently re-issue an identity token after relaunch, so this keeps Friends connected.
struct FriendsSessionVault {
    var service = "com.frozenpop.ClimbingApp.friends-session"
    private func query(_ key: String?) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let key { query[kSecAttrAccount as String] = key }
        return query
    }
    func load(_ key: String) -> String? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func save(_ token: String, for key: String) {
        let data = Data(token.utf8)
        if SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var item = query(key)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
    /// Without a key, removes every account's session.
    func clear(_ key: String? = nil) { SecItemDelete(query(key) as CFDictionary) }
}

enum AccountError: LocalizedError {
    case keychain(OSStatus), unavailable, missingIdentity
    var errorDescription: String? {
        switch self {
        case .keychain: "Your account session couldn’t be updated securely. Please try again."
        case .unavailable: "Sign-in setup isn’t complete for this build. You can keep logging without an account."
        case .missingIdentity: "The provider didn’t return an account. Please try signing in again."
        }
    }
}

enum LoginConfiguration {
    static var appleEnabled: Bool { Bundle.main.object(forInfoDictionaryKey: "AppleSignInEnabled") as? String == "YES" }
    static var googleClientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              value.hasSuffix(".apps.googleusercontent.com"), !value.contains("$("), !value.contains("YOUR_") else { return nil }
        let reversed = value.split(separator: ".").reversed().joined(separator: ".")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        return schemes.contains(reversed) ? value : nil
    }
}

@MainActor
@Observable
final class AccountSession {
    private(set) var account: ClimberAccount?
    private(set) var isBusy = false
    var errorMessage: String?
    private let vault: any AccountVault
    private let googleSignOut: () -> Void
    private let friendsSessions: FriendsSessionVault
    // Apple identity tokens expire in minutes and can't be fetched silently, so only the latest one is kept, in memory.
    private var appleIdentityToken: String?
    // Single use and valid for minutes. Apple's revoke API needs it when the account is deleted.
    private var appleAuthorizationCode: String?
    // Right after an app is re-approved, Apple can still report the old revoked state, so an Apple ID confirmed in this run is trusted for 5 minutes.
    private var appleConfirmedSubject: String?
    private var appleConfirmedAt = Date.distantPast
    var now: () -> Date = Date.init
    // Google puts SHA256 of this in the sign-in ID token, and Supabase needs the raw value to accept it.
    private var googleNonce: String?
    // Set when a different account signs in, so profile setup opens even after an earlier "Not now".
    private var signedInFresh = false
    private var revision = 0
    private var restored = false

    init(vault: any AccountVault = KeychainAccountVault(), googleSignOut: @escaping () -> Void = { GIDSignIn.sharedInstance.signOut() },
         friendsSessions: FriendsSessionVault = .init()) {
        self.vault = vault
        self.googleSignOut = googleSignOut
        self.friendsSessions = friendsSessions
        do { account = try vault.load() } catch { errorMessage = error.localizedDescription }
    }

    func completeApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  !credential.user.isEmpty else { errorMessage = AccountError.missingIdentity.localizedDescription; return }
            completeApple(subject: credential.user, name: credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) },
                          email: credential.email, identityToken: credential.identityToken.flatMap { String(data: $0, encoding: .utf8) },
                          authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) })
        case let .failure(error):
            switch (error as NSError).code {
            case ASAuthorizationError.canceled.rawValue: break
            // Apple's own text here is a bare error code, so name the likely cause instead.
            case ASAuthorizationError.unknown.rawValue, ASAuthorizationError.notInteractive.rawValue:
                errorMessage = "Apple sign-in couldn’t start. Check that you’re signed in to an Apple Account in the Settings app, then try again."
            case ASAuthorizationError.failed.rawValue, ASAuthorizationError.invalidResponse.rawValue, ASAuthorizationError.notHandled.rawValue:
                errorMessage = "Apple couldn’t confirm your sign-in. Check your connection and try again."
            default: errorMessage = error.localizedDescription
            }
        }
    }

    /// Apple shares the name and email only on the first authorization, so confirming the same Apple ID again keeps the saved ones.
    func completeApple(subject: String, name: String?, email: String?, identityToken: String?, authorizationCode: String? = nil) {
        let existing = account?.provider == .apple && account?.subject == subject ? account : nil
        let name = name ?? ""
        activate(ClimberAccount(provider: .apple, subject: subject,
                                name: name.isEmpty ? existing?.name ?? "Climber" : name, email: email ?? existing?.email))
        if account?.subject == subject { appleIdentityToken = identityToken; appleAuthorizationCode = authorizationCode; appleConfirmedSubject = subject; appleConfirmedAt = now() }
    }

    private var appleRecentlyConfirmed: Bool { account?.subject == appleConfirmedSubject && now().timeIntervalSince(appleConfirmedAt) < 300 }

    func appleCredentialRevoked() {
        if account?.provider == .apple && !appleRecentlyConfirmed { signOut() }
    }

    func takeFreshSignIn() -> Bool {
        defer { signedInFresh = false }
        return signedInFresh
    }

    func takeAppleAuthorizationCode() -> String? {
        defer { appleAuthorizationCode = nil }
        return appleAuthorizationCode
    }

    func signInWithGoogle(presenting controller: UIViewController) async {
        guard let clientID = LoginConfiguration.googleClientID else { errorMessage = AccountError.unavailable.localizedDescription; return }
        guard !isBusy else { return }
        revision += 1
        let operation = revision
        isBusy = true
        defer { if revision == operation { isBusy = false } }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: controller, hint: nil, additionalScopes: nil, nonce: newGoogleNonce())
            guard operation == revision else { return }
            guard let subject = result.user.userID, !subject.isEmpty else { throw AccountError.missingIdentity }
            activate(ClimberAccount(provider: .google, subject: subject, name: result.user.profile?.name ?? "Climber", email: result.user.profile?.email))
        } catch {
            guard operation == revision else { return }
            if (error as NSError).code != GIDSignInError.canceled.rawValue { errorMessage = error.localizedDescription }
        }
    }

    /// Keeps a new raw nonce and returns its SHA256 hex for Google.
    func newGoogleNonce() -> String {
        // SystemRandomNumberGenerator is cryptographically secure on Apple platforms.
        let raw = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
        googleNonce = raw
        return sha256Hex(raw)
    }

    /// The raw nonce Supabase needs for this ID token, or nil when the token has no nonce (Apple, or a Google token refreshed since sign-in).
    func friendsNonce(for idToken: String) throws -> String? {
        let parts = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let claim = claims["nonce"] as? String else { return nil }
        // After a relaunch the raw nonce is gone, and the SDK has no forced refresh to drop the claim before the token expires.
        guard let raw = googleNonce, sha256Hex(raw) == claim else {
            throw FriendsProblem(message: "Google sign-in needs refreshing. Sign out and sign in with Google again.")
        }
        return raw
    }

    private func activate(_ verifiedAccount: ClimberAccount) {
        do {
            try vault.save(verifiedAccount)
            if account?.storageKey != verifiedAccount.storageKey { signedInFresh = true }
            revision += 1
            isBusy = false
            account = verifiedAccount
            errorMessage = nil
        } catch {
            if verifiedAccount.provider == .google { googleSignOut() }
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        do {
            try vault.clear()
            friendsSessions.clear()
            appleIdentityToken = nil
            appleAuthorizationCode = nil
            appleConfirmedSubject = nil
            googleNonce = nil
            revision += 1
            googleSignOut()
            account = nil
            isBusy = false
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func restore() async {
        guard !restored else { return }; restored = true
        await verifyExistingSession()
    }

    func identityTokenForFriends() async throws -> String {
        guard let current = account else { throw SocialError.signIn }
        if current.provider == .apple {
            guard let token = appleIdentityToken else { throw SocialError.appleSignIn }
            appleIdentityToken = nil // Single use: Supabase returns its own refresh token.
            return token
        }
        guard let clientID = LoginConfiguration.googleClientID else { throw AccountError.unavailable }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let restored = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
        let refreshed = try await restored.refreshTokensIfNeeded()
        guard account == current, refreshed.userID == current.subject,
              let token = refreshed.idToken?.tokenString else { throw AccountError.missingIdentity }
        return token
    }

    // Apple treats simulators as untrusted and always reports REVOKED there, which would sign out on every launch.
    #if targetEnvironment(simulator)
    private static let isSimulator = true
    #else
    private static let isSimulator = false
    #endif

    func verifyExistingSession() async {
        guard let current = account else { return }
        let operation = revision
        switch current.provider {
        case .apple:
            guard !appleRecentlyConfirmed, !Self.isSimulator else { return }
            do {
                let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: current.subject)
                guard operation == revision else { return }
                if state != .authorized { signOut() }
            } catch {
                // A network failure doesn't erase an already signed-in user's offline log.
            }
        case .google:
            guard let clientID = LoginConfiguration.googleClientID, GIDSignIn.sharedInstance.hasPreviousSignIn() else { signOut(); return }
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            do {
                let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
                guard operation == revision else { return }
                guard user.userID == current.subject else { signOut(); return }
            } catch {
                guard operation == revision else { return }
                let failure = error as NSError
                let expired = failure.domain == kGIDSignInErrorDomain &&
                    [GIDSignInError.hasNoAuthInKeychain.rawValue, GIDSignInError.refreshTokenExpired.rawValue].contains(failure.code)
                if expired || !GIDSignIn.sharedInstance.hasPreviousSignIn() { signOut() }
            }
        }
    }
}
