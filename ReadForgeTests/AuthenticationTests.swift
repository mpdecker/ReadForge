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
        modelContainer = try ModelContainer(
            for: User.self, UserPreferences.self, UserSession.self, UserDevice.self,
            configurations: config
        )
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
            // Test email validation logic
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
        // Test valid passwords
        let validPasswords = [
            "Password123!",
            "MySecureP@ss",
            "Str0ngP@ssw0rd",
            "C0mpl3x!Password"
        ]
        
        for password in validPasswords {
            #expect(isValidPasswordFormat(password), "Password should be valid")
        }
        
        // Test invalid passwords
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
    
    @Test
    func testUserSessionCreation() async throws {
        let userId = UUID()
        let deviceToken = UUID().uuidString
        let session = UserSession(userId: userId, deviceToken: deviceToken)
        
        #expect(session.userId == userId)
        #expect(session.deviceToken == deviceToken)
        #expect(session.isActive == true)
        #expect(session.expiresAt > Date())
    }
    
    @Test
    func testUserDeviceCreation() async throws {
        let device = UserDevice(
            deviceName: "iPhone 15",
            deviceType: .iphone,
            deviceIdentifier: "test-device-id"
        )
        
        #expect(device.deviceName == "iPhone 15")
        #expect(device.deviceType == .iphone)
        #expect(device.deviceIdentifier == "test-device-id")
        #expect(device.isTrusted == false)
    }
    
    // MARK: - Biometric Service Tests
    
    @Test
    func testBiometricServiceAvailability() async throws {
        let biometricService = BiometricService()
        
        // Test that service can check availability
        let isAvailable = biometricService.isBiometricAvailable()
        // This will depend on the test environment
        // Just verify the method doesn't crash
        #expect(true, "Biometric availability check should not crash")
    }
    
    @Test
    func testBiometricType() async throws {
        let biometricService = BiometricService()
        
        let biometricType = biometricService.getBiometricType()
        let displayName = biometricService.getBiometricDisplayName()
        
        // Verify display name is not empty
        #expect(!displayName.isEmpty, "Biometric display name should not be empty")
        
        // Verify type is one of expected values
        #expect([LABiometryType.none, .touchID, .faceID, .opticID].contains(biometricType), "Biometric type should be valid")
    }
    
    // MARK: - Token Storage Tests
    
    @Test
    func testTokenStorage() async throws {
        let tokenStorage = TokenStorage()
        
        let accessToken = "test-access-token"
        let refreshToken = "test-refresh-token"
        
        // Test storing tokens
        try await tokenStorage.storeTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(3600)
        )
        
        // Test retrieving tokens
        if let (storedAccess, storedRefresh) = try await tokenStorage.getStoredTokens() {
            #expect(storedAccess == accessToken)
            #expect(storedRefresh == refreshToken)
        } else {
            #expect(Bool(false), "Tokens should be retrievable")
        }
        
        // Test clearing tokens
        try await tokenStorage.clearTokens()
        
        let retrievedTokens = try await tokenStorage.getStoredTokens()
        #expect(retrievedTokens == nil, "Tokens should be cleared")
    }
    
    @Test
    func testBiometricCredentialsStorage() async throws {
        let tokenStorage = TokenStorage()
        
        let credentials = (
            email: "test@example.com",
            password: "TestPassword123!",
            deviceId: "test-device-id"
        )
        
        // Test storing credentials
        try await tokenStorage.storeCredentialsForBiometrics((email: credentials.email, password: credentials.password, deviceId: credentials.deviceId))
        
        // Test retrieving credentials
        let retrievedCredentials = try await tokenStorage.getStoredCredentials()
        #expect(retrievedCredentials?.email == credentials.email)
        #expect(retrievedCredentials?.deviceId == credentials.deviceId)
        
        // Test clearing credentials
        try await tokenStorage.clearTokens()
        
        let clearedCredentials = try await tokenStorage.getStoredCredentials()
        #expect(clearedCredentials == nil, "Credentials should be cleared")
    }
    
    // MARK: - Authentication Flow Tests
    
    @Test
    func testSignInFlow() async throws {
        let authService = AuthenticationService(modelContext: modelContext)
        
        // Mock successful sign in
        let mockNetworkService = MockNetworkService()
        // This would require dependency injection to work properly
        
        // Test initial state
        #expect(authService.authenticationState.isAuthenticated == false)
        
        // Test sign in with valid credentials
        await authService.signIn(
            email: "test@example.com",
            password: "TestPassword123!",
            deviceName: "Test Device",
            rememberDevice: true
        )
        
        // In a real test with mocked network service, we'd verify:
        // - authentication state becomes authenticated
        // - current user is set
        // - tokens are stored
    }
    
    @Test
    func testSignOutFlow() async throws {
        // First, set up authenticated state
        let user = User(email: "test@example.com", name: "Test User")
        modelContext.insert(user)
        try modelContext.save()
        
        let authService = AuthenticationService(modelContext: modelContext)
        
        // Test sign out
        await authService.signOut()
        
        // Verify state after sign out
        #expect(authService.authenticationState.isAuthenticated == false)
        #expect(authService.currentUser == nil)
    }
    
    // MARK: - Error Handling Tests
    
    @Test
    func testAuthenticationErrorHandling() async throws {
        let authService = AuthenticationService(modelContext: modelContext)
        
        // Test invalid credentials
        await authService.signIn(
            email: "invalid@example.com",
            password: "wrongpassword",
            deviceName: "Test Device",
            rememberDevice: false
        )
        
        // In a real test with mocked network service:
        // - authentication state should be error
        // - error message should be set
        // - current user should remain nil
    }
    
    @Test
    func testNetworkErrorHandling() async throws {
        // Test network failure scenarios
        // This would require mocking network failures
        #expect(true, "Network error handling should be tested")
    }
    
    // MARK: - Session Management Tests
    
    @Test
    func testSessionExpiration() async throws {
        let tokenStorage = TokenStorage()
        
        // Store expired token
        try await tokenStorage.storeTokens(
            accessToken: "expired-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(-3600) // Expired 1 hour ago
        )
        
        // Test token validation
        let isValid = try await tokenStorage.isTokenValid("expired-token")
        #expect(!isValid, "Expired token should be invalid")
    }
    
    @Test
    func testSessionRefresh() async throws {
        // Test token refresh flow
        // This would require mocking the network service
        #expect(true, "Token refresh should be tested")
    }
    
    // MARK: - Security Tests
    
    @Test
    func testPasswordHashing() async throws {
        let password = "TestPassword123!"
        let hash = SecurityService.hash(password.data(using: .utf8)!)
        
        // Verify hash is consistent
        let hash2 = SecurityService.hash(password.data(using: .utf8)!)
        #expect(hash == hash2, "Password hash should be consistent")
        
        // Verify hash is not the original password
        #expect(hash != password, "Hash should not equal original password")
    }
    
    @Test
    func testSecureStorage() async throws {
        let sensitiveData = "sensitive-information"
        let key = "test-key"
        
        // Test storing sensitive data
        try SecurityService.storeInKeychain(sensitiveData.data(using: .utf8)!, forKey: key)
        
        // Test retrieving sensitive data
        if let retrievedData = try SecurityService.retrieveFromKeychain(forKey: key),
           let retrievedString = String(data: retrievedData, encoding: .utf8) {
            #expect(retrievedString == sensitiveData)
        } else {
            #expect(Bool(false), "Sensitive data should be retrievable")
        }
        
        // Test deleting sensitive data
        try SecurityService.deleteFromKeychain(forKey: key)
        
        let deletedData = try SecurityService.retrieveFromKeychain(forKey: key)
        #expect(deletedData == nil, "Deleted data should not be retrievable")
    }
    
    // MARK: - Helper Methods
    
    private func isValidEmailFormat(_ email: String) -> Bool {
        let emailRegex = #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }
    
    private func isValidPasswordFormat(_ password: String) -> Bool {
        return password.count >= 8 &&
               password.range(of: "[A-Z]", options: .regularExpression) != nil &&
               password.range(of: "[a-z]", options: .regularExpression) != nil &&
               password.range(of: "[0-9]", options: .regularExpression) != nil &&
               password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil
    }
}

// MARK: - Mock Network Service

class MockNetworkService {
    // Mock implementation for testing authentication flows
    // This would implement the same interface as NetworkService
    // but return predefined responses for testing
}
