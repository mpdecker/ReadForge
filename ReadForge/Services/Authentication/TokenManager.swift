import Foundation

/// Holds access tokens for the account stack; stubbed until real auth is wired.
final class TokenManager: @unchecked Sendable {
    static let shared = TokenManager()

    private var accessToken: String?
    private let lock = NSLock()

    private init() {}

    func getAccessToken() async throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return accessToken
    }

    func setAccessToken(_ token: String?) {
        lock.lock()
        accessToken = token
        lock.unlock()
    }
}
