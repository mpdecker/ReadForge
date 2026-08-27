import Combine
import CryptoKit
import Foundation
import SwiftData
import SwiftUI
import UIKit

/// Coordinates sign-in, registration, and session state for the optional account UI.
@MainActor
final class AuthenticationService: ObservableObject {
    @Published private(set) var authenticationState: AuthenticationState = .unauthenticated
    @Published private(set) var currentUser: User?
    @Published private(set) var isLoading = false

    var isAuthenticated: Bool { authenticationState.isAuthenticated }

    private let modelContext: ModelContext

    /// The email used for the on-device biometric-only profile (`authenticateWithBiometrics`).
    /// Reserved so a password-protected account can never be registered under this address —
    /// otherwise anyone who can pass a device biometric check (proves "device owner," not
    /// "this account's owner") could sign straight into that account via Face ID/Touch ID,
    /// bypassing whatever password was set on it.
    static let reservedBiometricEmail = "local@readforge.app"

    /// Failed sign-in attempts per lowercased email, in-memory only (resets on relaunch) — a
    /// basic brake against a scripted local brute-force loop. Not a substitute for PBKDF2's own
    /// per-guess cost, just an additional layer.
    private var failedAttempts: [String: (count: Int, lockedUntil: Date)] = [:]
    private static let maxFailedAttempts = 5
    private static let lockoutDuration: TimeInterval = 30

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// In-memory SwiftData stack for SwiftUI `@StateObject` defaults and previews.
    convenience init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: User.self, configurations: config)
        self.init(modelContext: ModelContext(container))
    }

    func signIn(email: String, password: String, deviceName: String, rememberDevice: Bool) async {
        isLoading = true
        defer { isLoading = false }

        let lowered = email.lowercased()
        if let locked = failedAttempts[lowered], locked.count >= Self.maxFailedAttempts, Date() < locked.lockedUntil {
            authenticationState = .error(.tooManyAttempts)
            return
        }

        let allUsers = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        guard let user = allUsers.first(where: { $0.email == lowered }) else {
            recordFailedAttempt(for: lowered)
            authenticationState = .error(.accountNotFound)
            return
        }
        guard Self.verifyPassword(password, against: user) else {
            recordFailedAttempt(for: lowered)
            authenticationState = .error(.invalidCredentials)
            return
        }

        failedAttempts[lowered] = nil
        user.lastLoginAt = Date()
        try? modelContext.save()
        currentUser = user
        authenticationState = .authenticated(user)
    }

    private func recordFailedAttempt(for email: String) {
        let current = failedAttempts[email]?.count ?? 0
        failedAttempts[email] = (current + 1, Date().addingTimeInterval(Self.lockoutDuration))
    }

    func signOut() async {
        currentUser = nil
        authenticationState = .unauthenticated
    }

    /// Re-locks the app without discarding the signed-in user's identity — there's no server
    /// session to invalidate (this is entirely local), so "locking" just means requiring
    /// re-authentication before showing any document content again. Called when the app leaves
    /// the foreground so a backgrounded or handed-off device can't simply be reopened straight
    /// into unlocked content; previously nothing observed scene-phase transitions at all, so
    /// authenticating once unlocked the app for the rest of the process's lifetime.
    func lock() {
        guard isAuthenticated else { return }
        authenticationState = .unauthenticated
    }

    func register(
        email: String,
        password: String,
        confirmPassword: String,
        name: String?,
        agreeToTerms: Bool
    ) async throws {
        guard agreeToTerms else { throw AuthenticationError.weakPassword }
        guard password == confirmPassword else { throw AuthenticationError.weakPassword }
        guard Self.isStrongPassword(password) else { throw AuthenticationError.weakPassword }

        let lowered = email.lowercased()
        // Reserved for the biometric-only profile (see `reservedBiometricEmail`) — registering a
        // real password under this exact address would let anyone who passes a device biometric
        // check sign into it via Face ID/Touch ID instead, bypassing the password entirely.
        guard lowered != Self.reservedBiometricEmail else {
            throw AuthenticationError.reservedEmailAddress
        }

        let allUsers = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        guard !allUsers.contains(where: { $0.email == lowered }) else {
            throw AuthenticationError.emailAlreadyExists
        }

        let user = User(email: email, name: name)
        let (salt, hash) = try Self.makePasswordRecord(for: password)
        user.passwordSalt = salt
        user.passwordHash = hash

        modelContext.insert(user)
        try modelContext.save()
        currentUser = user
        authenticationState = .authenticated(user)
    }

    /// Resets a forgotten password using Face ID / Touch ID as proof of identity instead of an
    /// emailed reset link — there's no email delivery possible in an offline-only app (see
    /// CLAUDE.md's privacy rules), so the previous email-token flow could never actually work.
    /// This only succeeds if the account both exists and can pass a live biometric challenge.
    func resetPasswordWithBiometrics(email: String, newPassword: String) async throws {
        let lowered = email.lowercased()
        let allUsers = try modelContext.fetch(FetchDescriptor<User>())
        guard let user = allUsers.first(where: { $0.email == lowered }) else {
            throw AuthenticationError.accountNotFound
        }

        // Biometrics only prove "this is the device's owner" — not that they own the specific
        // account named by `email`. On a device with just one local account those are the same
        // thing, but with more than one, anyone who can unlock the device could type in a
        // different account's email and reset ITS password purely from knowing that email
        // address. Restricting to the single-account case closes that gap; a multi-account
        // device has to fall back to changing the password while signed in instead.
        guard allUsers.count == 1 else {
            throw AuthenticationError.biometricResetUnsupportedWithMultipleAccounts
        }

        guard await BiometricService().evaluate(reason: "Reset your ReadForge password") else {
            throw AuthenticationError.biometricFailed
        }
        guard Self.isStrongPassword(newPassword) else { throw AuthenticationError.weakPassword }

        let (salt, hash) = try Self.makePasswordRecord(for: newPassword)
        user.passwordSalt = salt
        user.passwordHash = hash
        try modelContext.save()
    }

    /// Changes the signed-in user's password, requiring the current one.
    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let user = currentUser else { throw AuthenticationError.accountNotFound }
        guard Self.verifyPassword(currentPassword, against: user) else {
            throw AuthenticationError.invalidCredentials
        }
        guard Self.isStrongPassword(newPassword) else { throw AuthenticationError.weakPassword }
        let (salt, hash) = try Self.makePasswordRecord(for: newPassword)
        user.passwordSalt = salt
        user.passwordHash = hash
        try modelContext.save()
    }

    /// Updates the signed-in user's display name.
    func updateProfile(name: String?) async throws {
        guard let user = currentUser else { throw AuthenticationError.accountNotFound }
        user.name = (name?.isEmpty ?? true) ? nil : name
        try modelContext.save()
    }

    /// Permanently deletes the signed-in account and all of its data (sessions/devices cascade
    /// via the model's delete rules), then signs out. This only ever touches the local store —
    /// there's no server-side account to delete.
    func deleteAccount() async throws {
        guard let user = currentUser else { return }
        modelContext.delete(user)
        try modelContext.save()
        await signOut()
    }

    /// Signs in the on-device local profile using Face ID / Touch ID as the sole factor —
    /// there's no password to check, so this deliberately bypasses `signIn(email:password:...)`.
    /// Requires an actual passed biometric challenge; `BiometricService.isBiometricAvailable()`
    /// only reports whether biometrics *could* be used, not that the user passed one.
    func authenticateWithBiometrics() async {
        isLoading = true
        defer { isLoading = false }

        guard await BiometricService().evaluate() else {
            authenticationState = .error(.biometricFailed)
            return
        }

        let lowered = "local@readforge.app"
        let allUsers = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        let user = allUsers.first(where: { $0.email == lowered }) ?? {
            let newUser = User(email: lowered, name: nil)
            modelContext.insert(newUser)
            return newUser
        }()

        user.lastLoginAt = Date()
        try? modelContext.save()
        currentUser = user
        authenticationState = .authenticated(user)
    }

    // MARK: - Local password hashing
    //
    // Everything here runs on-device with no backend to verify a password against (see
    // CLAUDE.md's privacy rules), so it's checked locally: PBKDF2-HMAC-SHA256, 100k
    // iterations, random 16-byte salt per user, via SecurityService. Never compared or stored
    // in plain text.

    private static func makePasswordRecord(for password: String) throws -> (salt: String, hash: String) {
        let saltData = try SecurityService.generateSecureRandomData(count: 16)
        let key = try SecurityService.deriveKey(from: password, salt: saltData)
        let hashData = key.withUnsafeBytes { Data($0) }
        return (saltData.base64EncodedString(), hashData.base64EncodedString())
    }

    private static func verifyPassword(_ password: String, against user: User) -> Bool {
        guard let saltB64 = user.passwordSalt, let expectedHashB64 = user.passwordHash,
              let saltData = Data(base64Encoded: saltB64), let expectedHashData = Data(base64Encoded: expectedHashB64)
        else { return false }
        guard let key = try? SecurityService.deriveKey(from: password, salt: saltData) else { return false }
        let hashData = key.withUnsafeBytes { Data($0) }
        return constantTimeEquals(hashData, expectedHashData)
    }

    /// Byte-by-byte comparison that always inspects every byte of the shorter input rather than
    /// short-circuiting on the first mismatch, unlike `Data`/`String`'s `==`. Comparing the raw
    /// PBKDF2 output this way (rather than round-tripping through base64 strings, whose `==` is
    /// even less predictable) closes off a timing side channel — low-severity here given PBKDF2's
    /// own 100k-iteration cost already adds substantial per-guess noise, but simple to close.
    private static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (l, r) in zip(lhs, rhs) {
            difference |= l ^ r
        }
        return difference == 0
    }

    /// Mirrors the client-side rule shown in `SignUpView`/`ChangePasswordView`/`PasswordResetView`
    /// (8+ chars, upper/lower/digit/symbol) — enforced here too so it can't be bypassed by any
    /// caller that reaches the service directly instead of going through a view's disabled-button
    /// gate (as several existing tests already do).
    static func isStrongPassword(_ password: String) -> Bool {
        password.count >= 8 &&
            password.range(of: "[A-Z]", options: .regularExpression) != nil &&
            password.range(of: "[a-z]", options: .regularExpression) != nil &&
            password.range(of: "[0-9]", options: .regularExpression) != nil &&
            password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil
    }
}
