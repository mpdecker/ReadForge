import Combine
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

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// In-memory SwiftData stack for SwiftUI `@StateObject` defaults and previews.
    convenience init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: User.self, UserPreferences.self, UserSession.self, UserDevice.self,
            configurations: config
        )
        self.init(modelContext: ModelContext(container))
    }

    func signIn(email: String, password: String, deviceName: String, rememberDevice: Bool) async {
        isLoading = true
        defer { isLoading = false }

        let lowered = email.lowercased()
        let allUsers = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        if let user = allUsers.first(where: { $0.email == lowered }) {
            currentUser = user
            authenticationState = .authenticated(user)
            return
        }

        let user = User(email: email, name: nil)
        modelContext.insert(user)
        try? modelContext.save()
        currentUser = user
        authenticationState = .authenticated(user)
    }

    func signOut() async {
        currentUser = nil
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
        let user = User(email: email, name: name)
        modelContext.insert(user)
        try modelContext.save()
        currentUser = user
        authenticationState = .authenticated(user)
    }

    func resetPassword(email: String) async throws {}

    func confirmPasswordReset(email: String, newPassword: String, resetToken: String) async throws {}

    func verifyTwoFactorCode(_ code: String, challengeId: String) async {}

    func authenticateWithBiometrics() async {
        await signIn(email: "local@readforge.app", password: "", deviceName: UIDevice.current.name, rememberDevice: false)
    }
}
