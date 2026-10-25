import XCTest
@testable import ClimbingApp

final class KeychainIntegrationTests: XCTestCase {
    func testAccountVaultRoundTripWithSimulatorSigning() throws {
        // A distinct service keeps this probe separate from every real account session.
        let vault = KeychainAccountVault(service: "com.frozenpop.ClimbingApp.tests.\(UUID().uuidString)")
        defer { try? vault.clear() }
        let fixture = ClimberAccount(provider: .google, subject: "keychain-test-fixture", name: "Keychain test", email: nil)
        try vault.save(fixture)
        XCTAssertEqual(try vault.load(), fixture)
        try vault.clear()
        XCTAssertNil(try vault.load())
    }
}
