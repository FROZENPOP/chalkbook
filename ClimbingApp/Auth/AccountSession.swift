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

    var storageKey: String {
        SHA256.hash(data: Data("\(provider.rawValue):\(subject)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

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
    private var revision = 0
    private var restored = false

    init(vault: any AccountVault = KeychainAccountVault(), googleSignOut: @escaping () -> Void = { GIDSignIn.sharedInstance.signOut() }) {
        self.vault = vault
        self.googleSignOut = googleSignOut
        do { account = try vault.load() } catch { errorMessage = error.localizedDescription }
    }

    func completeApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  !credential.user.isEmpty else { errorMessage = AccountError.missingIdentity.localizedDescription; return }
            let fullName = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) } ?? ""
            activate(ClimberAccount(provider: .apple, subject: credential.user,
                                    name: fullName.isEmpty ? "Climber" : fullName, email: credential.email))
        case let .failure(error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue { errorMessage = error.localizedDescription }
        }
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
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: controller)
            guard operation == revision else { return }
            guard let subject = result.user.userID, !subject.isEmpty else { throw AccountError.missingIdentity }
            activate(ClimberAccount(provider: .google, subject: subject, name: result.user.profile?.name ?? "Climber", email: result.user.profile?.email))
        } catch {
            guard operation == revision else { return }
            if (error as NSError).code != GIDSignInError.canceled.rawValue { errorMessage = error.localizedDescription }
        }
    }

    private func activate(_ verifiedAccount: ClimberAccount) {
        do {
            try vault.save(verifiedAccount)
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

    func googleIdentityTokenForFriends() async throws -> String {
        guard let current = account else { throw SocialError.signIn }
        guard current.provider == .google else { throw SocialError.applePending }
        guard let clientID = LoginConfiguration.googleClientID else { throw AccountError.unavailable }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let restored = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
        let refreshed = try await restored.refreshTokensIfNeeded()
        guard account == current, refreshed.userID == current.subject,
              let token = refreshed.idToken?.tokenString else { throw AccountError.missingIdentity }
        return token
    }

    func verifyExistingSession() async {
        guard let current = account else { return }
        let operation = revision
        switch current.provider {
        case .apple:
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
