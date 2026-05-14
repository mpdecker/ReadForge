import Foundation

/// Placeholder client for account-related HTTP APIs (not used by the on-device MVP path).
final class NetworkService {
    func updateUserProfile(_ user: User, accessToken: String) async throws {}

    func getDevices(_ userId: UUID, accessToken: String) async throws -> [UserDevice] {
        []
    }

    func revokeDevice(_ deviceId: UUID, accessToken: String) async throws {}

    func changePassword(currentPassword: String, newPassword: String, accessToken: String) async throws {}
}
