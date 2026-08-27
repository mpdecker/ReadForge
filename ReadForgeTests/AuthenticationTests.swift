//
//  AuthenticationTests.swift
//  ReadForgeTests
//
//  Created by Matthieu Decker on 5/10/26.
//

import Testing
import Foundation
import SwiftData
import LocalAuthentication
@testable import ReadForge

@Suite(.serialized)
@MainActor
struct AuthenticationTests {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var authService: AuthenticationService!

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: User.self, configurations: config)
        modelContext = modelContainer.mainContext
        authService = AuthenticationService(modelContext: modelContext)
    }

    // MARK: - Authentication Service Tests

    @Test
    func testAuthenticationInitialState() {
        #expect(authService.authenticationState.isAuthenticated == false)
        #expect(authService.currentUser == nil)
        #expect(authService.isLoading == false)
    }

    @Test
    func testValidEmailValidation() async throws {
        let validEmails = [
            "test@example.com",
            "user.name@domain.co.uk",
            "user+tag@example.org",
            "user123@test-domain.com"
        ]

        for email in validEmails {
            #expect(isValidEmailFormat(email), "Email \(email) should be valid")
        }
    }

    @Test
    func testInvalidEmailValidation() async throws {
        let invalidEmails = [
            "invalid-email",
            "@example.com",
            "user@",
            "user..name@example.com",
            "user@.com",
            "user name@example.com"
        ]

        for email in invalidEmails {
            #expect(!isValidEmailFormat(email), "Email \(email) should be invalid")
        }
    }

    @Test
    func testPasswordValidation() async throws {
        let validPasswords = [
            "Password123!",
            "MySecureP@ss1",
            "Str0ngP@ssw0rd",
            "C0mpl3x!Password"
        ]

        for password in validPasswords {
            #expect(isValidPasswordFormat(password), "Password should be valid")
        }

        let invalidPasswords = [
            "weak",           // Too short
            "nouppercase",    // No uppercase
            "NOLOWERCASE",    // No lowercase
            "nonumbers",      // No numbers
            "nospecial!",     // No special characters
        ]

        for password in invalidPasswords {
            #expect(!isValidPasswordFormat(password), "Password should be invalid")
        }
    }

    @Test
    func testUserCreation() async throws {
        let user = User(email: "test@example.com", name: "Test User")

        #expect(user.email == "test@example.com")
        #expect(user.name == "Test User")
        #expect(user.isEmailVerified == false)
        #expect(user.createdAt <= Date())
    }

    // MARK: - Biometric Service Tests

    @Test
    func testBiometricServiceAvailability() async throws {
        let biometricService = BiometricService()
        _ = biometricService.isBiometricAvailable()
        #expect(true, "Biometric availability check should not crash")
    }

    @Test
    func testBiometricType() async throws {
        let biometricService = BiometricService()

        let biometricType = biometricService.getBiometricType()
        let displayName = biometricService.getBiometricDisplayName()

        #expect(!displayName.isEmpty, "Biometric display name should not be empty")
        #expect([LABiometryType.none, .touchID, .faceID, .opticID].contains(biometricType), "Biometric type should be valid")
    }

    // MARK: - Registration + Sign-In Flow Tests
    //
    // These exercise the real local password hashing/verification in AuthenticationService —
    // there's no network mock needed since there's no network involved at all.

    @Test
    func testRegisterThenSignInSucceeds() async throws {
        try await authService.register(
            email: "test@example.com", password: "TestPassword123!", confirmPassword: "TestPassword123!",
            name: "Test User", agreeToTerms: true
        )
        #expect(authService.authenticationState.isAuthenticated == true)
        await authService.signOut()

        await authService.signIn(email: "test@example.com", password: "TestPassword123!", deviceName: "Test Device", rememberDevice: false)
        #expect(authService.authenticationState.isAuthenticated == true)
        #expect(authService.currentUser?.email == "test@example.com")
    }

    @Test
    func testSignInWithWrongPasswordFails() async throws {
        try await authService.register(
            email: "test@example.com", password: "TestPassword123!", confirmPassword: "TestPassword123!",
            name: nil, agreeToTerms: true
        )
        await authService.signOut()

        await authService.signIn(email: "test@example.com", password: "WrongPassword1!", deviceName: "Test Device", rememberDevice: false)
        #expect(authService.authenticationState.isAuthenticated == false)
        if case .error(let error) = authService.authenticationState {
            #expect(error == .invalidCredentials)
        } else {
            Issue.record("Expected .error(.invalidCredentials)")
        }
    }

    @Test
    func testSignInWithUnknownAccountFails() async throws {
        await authService.signIn(email: "nobody@example.com", password: "TestPassword123!", deviceName: "Test Device", rememberDevice: false)
        #expect(authService.authenticationState.isAuthenticated == false)
        if case .error(let error) = authService.authenticationState {
            #expect(error == .accountNotFound)
        } else {
            Issue.record("Expected .error(.accountNotFound)")
        }
    }

    @Test
    func testRegisterWithDuplicateEmailThrows() async throws {
        try await authService.register(
            email: "test@example.com", password: "TestPassword123!", confirmPassword: "TestPassword123!",
            name: nil, agreeToTerms: true
        )
        await #expect(throws: AuthenticationError.emailAlreadyExists) {
            try await authService.register(
                email: "test@example.com", password: "AnotherPassword1!", confirmPassword: "AnotherPassword1!",
                name: nil, agreeToTerms: true
            )
        }
    }

    @Test
    func testSignOutFlow() async throws {
        let user = User(email: "test@example.com", name: "Test User")
        modelContext.insert(user)
        try modelContext.save()

        let authService = AuthenticationService(modelContext: modelContext)
        await authService.signOut()

        #expect(authService.authenticationState.isAuthenticated == false)
        #expect(authService.currentUser == nil)
    }

    @Test
    func testChangePasswordWithCorrectCurrentPasswordSucceeds() async throws {
        try await authService.register(
            email: "test@example.com", password: "OldPassword1!", confirmPassword: "OldPassword1!",
            name: nil, agreeToTerms: true
        )
        try await authService.changePassword(currentPassword: "OldPassword1!", newPassword: "NewPassword2!")
        await authService.signOut()

        await authService.signIn(email: "test@example.com", password: "NewPassword2!", deviceName: "Test Device", rememberDevice: false)
        #expect(authService.authenticationState.isAuthenticated == true)
    }

    @Test
    func testChangePasswordWithWrongCurrentPasswordThrows() async throws {
        try await authService.register(
            email: "test@example.com", password: "OldPassword1!", confirmPassword: "OldPassword1!",
            name: nil, agreeToTerms: true
        )
        await #expect(throws: AuthenticationError.invalidCredentials) {
            try await authService.changePassword(currentPassword: "WrongPassword!", newPassword: "NewPassword2!")
        }
    }

    @Test
    func testUpdateProfileChangesName() async throws {
        try await authService.register(
            email: "test@example.com", password: "TestPassword123!", confirmPassword: "TestPassword123!",
            name: nil, agreeToTerms: true
        )
        try await authService.updateProfile(name: "New Name")
        #expect(authService.currentUser?.name == "New Name")
    }

    @Test
    func testDeleteAccountSignsOutAndRemovesUser() async throws {
        try await authService.register(
            email: "test@example.com", password: "TestPassword123!", confirmPassword: "TestPassword123!",
            name: nil, agreeToTerms: true
        )
        try await authService.deleteAccount()

        #expect(authService.currentUser == nil)
        #expect(authService.authenticationState.isAuthenticated == false)
        let remaining = try modelContext.fetch(FetchDescriptor<User>())
        #expect(remaining.isEmpty)
    }

    // MARK: - Password Reset Tests

    // Regression test: `resetPasswordWithBiometrics` used to look up an account purely by the
    // typed email and reset it after any successful biometric challenge — but biometrics only
    // prove "this is the device's owner," not "this is the owner of THIS account." On a device
    // with more than one local account, that let anyone who could unlock the device type in a
    // different account's email and take it over. This confirms the guard fires before
    // biometrics are even requested.
    @Test func testBiometricResetRefusedWithMultipleAccounts() async throws {
        try await authService.register(
            email: "victim@example.com", password: "VictimPassword1!", confirmPassword: "VictimPassword1!",
            name: nil, agreeToTerms: true
        )
        await authService.signOut()
        try await authService.register(
            email: "attacker@example.com", password: "AttackerPassword1!", confirmPassword: "AttackerPassword1!",
            name: nil, agreeToTerms: true
        )

        await #expect(throws: AuthenticationError.biometricResetUnsupportedWithMultipleAccounts) {
            try await authService.resetPasswordWithBiometrics(email: "victim@example.com", newPassword: "NewPassword2!")
        }

        // The victim's password must be provably untouched.
        await authService.signOut()
        await authService.signIn(email: "victim@example.com", password: "VictimPassword1!", deviceName: "Test Device", rememberDevice: false)
        #expect(authService.authenticationState.isAuthenticated == true)
    }

    @Test func testBiometricResetAccountNotFoundCheckedBeforeBiometrics() async throws {
        // With zero accounts registered, an unknown email should fail with `.accountNotFound`
        // rather than ever prompting for biometrics.
        await #expect(throws: AuthenticationError.accountNotFound) {
            try await authService.resetPasswordWithBiometrics(email: "nobody@example.com", newPassword: "NewPassword2!")
        }
    }

    // MARK: - Hardening Regression Tests

    // Regression test: registering a real password under the reserved biometric-only email used
    // to succeed silently — anyone who could pass a device biometric check (proves "device
    // owner," not "this account's owner") could then sign into that account via Face ID,
    // bypassing whatever password was set.
    @Test
    func testRegisteringReservedBiometricEmailFails() async throws {
        do {
            try await authService.register(
                email: AuthenticationService.reservedBiometricEmail, password: "TestPassword123!",
                confirmPassword: "TestPassword123!", name: nil, agreeToTerms: true
            )
            Issue.record("Expected AuthenticationError.reservedEmailAddress to be thrown")
        } catch let error as AuthenticationError {
            #expect(error == .reservedEmailAddress)
        }
    }

    // Regression test: `register`/`changePassword`/`resetPasswordWithBiometrics` previously only
    // checked `password == confirmPassword` and `agreeToTerms` — all real strength enforcement
    // lived solely in each SwiftUI view's disabled-button logic, so any caller that reached the
    // service directly (like this test) could set an empty or trivial password.
    @Test
    func testWeakPasswordRejectedAtServiceLayerNotJustInViews() async throws {
        do {
            try await authService.register(
                email: "weak@example.com", password: "weak", confirmPassword: "weak",
                name: nil, agreeToTerms: true
            )
            Issue.record("Expected AuthenticationError.weakPassword to be thrown")
        } catch let error as AuthenticationError {
            #expect(error == .weakPassword)
        }
    }

    // Regression test: nothing previously observed scene-phase transitions, so authenticating
    // once unlocked the app for the rest of the process's lifetime — `lock()` is the fix,
    // called from `ReadForgeApp` when the app backgrounds.
    @Test
    func testLockRequiresReauthenticationButPreservesTheAccount() async throws {
        try await authService.register(
            email: "test@example.com", password: "TestPassword123!", confirmPassword: "TestPassword123!",
            name: nil, agreeToTerms: true
        )
        #expect(authService.isAuthenticated)

        authService.lock()
        #expect(!authService.isAuthenticated)

        await authService.signIn(email: "test@example.com", password: "TestPassword123!", deviceName: "Test Device", rememberDevice: false)
        #expect(authService.isAuthenticated)
    }

    // Regression test: repeated failed sign-ins previously had no lockout/throttling at all
    // beyond PBKDF2's own per-guess cost — no defense against a scripted local brute-force loop.
    @Test
    func testRepeatedFailedSignInsEventuallyLockOut() async throws {
        try await authService.register(
            email: "test@example.com", password: "TestPassword123!", confirmPassword: "TestPassword123!",
            name: nil, agreeToTerms: true
        )
        await authService.signOut()

        for _ in 0..<5 {
            await authService.signIn(email: "test@example.com", password: "WrongPassword1!", deviceName: "Test Device", rememberDevice: false)
        }
        // The 6th attempt should be rejected as locked out even though the password is correct.
        await authService.signIn(email: "test@example.com", password: "TestPassword123!", deviceName: "Test Device", rememberDevice: false)
        guard case .error(let err) = authService.authenticationState else {
            Issue.record("Expected .error(.tooManyAttempts) after repeated failures")
            return
        }
        #expect(err == .tooManyAttempts)
    }

    // MARK: - Security Tests

    @Test
    func testPasswordHashing() async throws {
        let password = "TestPassword123!"
        let hash = SecurityService.hash(password.data(using: .utf8)!)

        let hash2 = SecurityService.hash(password.data(using: .utf8)!)
        #expect(hash == hash2, "Password hash should be consistent")
        #expect(hash != password, "Hash should not equal original password")
    }

    @Test
    func testSecureStorage() async throws {
        let sensitiveData = "sensitive-information"
        let key = "test-key"

        try SecurityService.storeInKeychain(sensitiveData.data(using: .utf8)!, forKey: key)

        if let retrievedData = try SecurityService.retrieveFromKeychain(forKey: key),
           let retrievedString = String(data: retrievedData, encoding: .utf8) {
            #expect(retrievedString == sensitiveData)
        } else {
            #expect(Bool(false), "Sensitive data should be retrievable")
        }

        try SecurityService.deleteFromKeychain(forKey: key)

        let deletedData = try SecurityService.retrieveFromKeychain(forKey: key)
        #expect(deletedData == nil, "Deleted data should not be retrievable")
    }

    // MARK: - Helper Methods

    private func isValidEmailFormat(_ email: String) -> Bool {
        // No consecutive dots, and no dot immediately touching '@' or the start of the domain —
        // the previous pattern let "user..name@example.com" and "user@.com" through as valid.
        let emailRegex = #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,}$"#
        guard email.range(of: emailRegex, options: .regularExpression) != nil else { return false }
        return !email.contains("..")
    }

    private func isValidPasswordFormat(_ password: String) -> Bool {
        return password.count >= 8 &&
               password.range(of: "[A-Z]", options: .regularExpression) != nil &&
               password.range(of: "[a-z]", options: .regularExpression) != nil &&
               password.range(of: "[0-9]", options: .regularExpression) != nil &&
               password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil
    }
}
