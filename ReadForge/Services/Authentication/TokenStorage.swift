import Foundation

/// In-memory token store for tests and future auth wiring.
actor TokenStorage {
    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?
    private var biometricCredentials: (email: String, password: String, deviceId: String)?

    func storeTokens(accessToken: String, refreshToken: String, expiresAt: Date) async throws {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    func getStoredTokens() async throws -> (String, String)? {
        guard let accessToken, let refreshToken else { return nil }
        return (accessToken, refreshToken)
    }

    func clearTokens() async throws {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        biometricCredentials = nil
    }

    func storeCredentialsForBiometrics(_ credentials: (email: String, password: String, deviceId: String)) async throws {
        biometricCredentials = credentials
    }

    func getStoredCredentials() async throws -> (email: String, password: String, deviceId: String)? {
        biometricCredentials
    }

    func isTokenValid(_ token: String) async throws -> Bool {
        guard let expiresAt, let accessToken else { return false }
        return token == accessToken && expiresAt > Date()
    }
}
