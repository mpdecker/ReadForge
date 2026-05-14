//
//  AuthenticationModels.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import Foundation
import SwiftData

// MARK: - User Model

@Model
final class User: Codable {
    var id: UUID
    var email: String
    var name: String?
    var createdAt: Date
    var lastLoginAt: Date?
    var isEmailVerified: Bool
    var preferences: UserPreferences?
    
    @Relationship(deleteRule: .cascade) var sessions: [UserSession] = []
    @Relationship(deleteRule: .cascade) var devices: [UserDevice] = []
    
    init(email: String, name: String? = nil) {
        self.id = UUID()
        self.email = email.lowercased()
        self.name = name
        self.createdAt = Date()
        self.isEmailVerified = false
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, email, name, createdAt, lastLoginAt, isEmailVerified, preferences
    }
    
    required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let email = try container.decode(String.self, forKey: .email)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        self.init(email: email, name: name)
        
        self.id = try container.decode(UUID.self, forKey: .id)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.lastLoginAt = try container.decodeIfPresent(Date.self, forKey: .lastLoginAt)
        self.isEmailVerified = try container.decode(Bool.self, forKey: .isEmailVerified)
        self.preferences = try container.decodeIfPresent(UserPreferences.self, forKey: .preferences)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(email, forKey: .email)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastLoginAt, forKey: .lastLoginAt)
        try container.encode(isEmailVerified, forKey: .isEmailVerified)
        try container.encodeIfPresent(preferences, forKey: .preferences)
    }
}

// MARK: - User Preferences

@Model
final class UserPreferences: Codable {
    var id: UUID
    var enableBiometrics: Bool
    var autoLockTimeout: TimeInterval // in seconds
    var enableOfflineAccess: Bool
    var dataSyncEnabled: Bool
    var theme: AppTheme
    var languageCode: String
    
    init() {
        self.id = UUID()
        self.enableBiometrics = false
        self.autoLockTimeout = 300 // 5 minutes
        self.enableOfflineAccess = true
        self.dataSyncEnabled = true
        self.theme = .system
        self.languageCode = "en"
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, enableBiometrics, autoLockTimeout, enableOfflineAccess, dataSyncEnabled, theme, languageCode
    }
    
    required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        
        self.id = try container.decode(UUID.self, forKey: .id)
        self.enableBiometrics = try container.decode(Bool.self, forKey: .enableBiometrics)
        self.autoLockTimeout = try container.decode(TimeInterval.self, forKey: .autoLockTimeout)
        self.enableOfflineAccess = try container.decode(Bool.self, forKey: .enableOfflineAccess)
        self.dataSyncEnabled = try container.decode(Bool.self, forKey: .dataSyncEnabled)
        self.theme = try container.decode(AppTheme.self, forKey: .theme)
        self.languageCode = try container.decode(String.self, forKey: .languageCode)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(enableBiometrics, forKey: .enableBiometrics)
        try container.encode(autoLockTimeout, forKey: .autoLockTimeout)
        try container.encode(enableOfflineAccess, forKey: .enableOfflineAccess)
        try container.encode(dataSyncEnabled, forKey: .dataSyncEnabled)
        try container.encode(theme, forKey: .theme)
        try container.encode(languageCode, forKey: .languageCode)
    }
}

// MARK: - User Session

@Model
final class UserSession: Codable {
    var id: UUID
    var userId: UUID
    var deviceToken: String
    var createdAt: Date
    var expiresAt: Date
    var isActive: Bool
    var ipAddress: String?
    var userAgent: String?
    
    @Relationship(inverse: \User.sessions) var user: User?
    
    init(userId: UUID, deviceToken: String) {
        self.id = UUID()
        self.userId = userId
        self.deviceToken = deviceToken
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(7 * 24 * 3600) // 7 days
        self.isActive = true
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, userId, deviceToken, createdAt, expiresAt, isActive, ipAddress, userAgent
    }
    
    required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let userId = try container.decode(UUID.self, forKey: .userId)
        let deviceToken = try container.decode(String.self, forKey: .deviceToken)
        self.init(userId: userId, deviceToken: deviceToken)
        
        self.id = try container.decode(UUID.self, forKey: .id)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        self.isActive = try container.decode(Bool.self, forKey: .isActive)
        self.ipAddress = try container.decodeIfPresent(String.self, forKey: .ipAddress)
        self.userAgent = try container.decodeIfPresent(String.self, forKey: .userAgent)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(deviceToken, forKey: .deviceToken)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(ipAddress, forKey: .ipAddress)
        try container.encodeIfPresent(userAgent, forKey: .userAgent)
    }
}

// MARK: - User Device

@Model
final class UserDevice: Codable {
    var id: UUID
    var userId: UUID
    var deviceName: String
    var deviceType: DeviceType
    var deviceIdentifier: String
    var isTrusted: Bool
    var lastUsedAt: Date
    var registeredAt: Date
    
    @Relationship(inverse: \User.devices) var user: User?
    
    init(userId: UUID = UUID(), deviceName: String, deviceType: DeviceType, deviceIdentifier: String) {
        self.id = UUID()
        self.userId = userId
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.deviceIdentifier = deviceIdentifier
        self.isTrusted = false
        self.lastUsedAt = Date()
        self.registeredAt = Date()
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, userId, deviceName, deviceType, deviceIdentifier, isTrusted, lastUsedAt, registeredAt
    }
    
    required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let deviceName = try container.decode(String.self, forKey: .deviceName)
        let deviceType = try container.decode(DeviceType.self, forKey: .deviceType)
        let deviceIdentifier = try container.decode(String.self, forKey: .deviceIdentifier)
        self.init(deviceName: deviceName, deviceType: deviceType, deviceIdentifier: deviceIdentifier)
        
        self.id = try container.decode(UUID.self, forKey: .id)
        self.userId = try container.decode(UUID.self, forKey: .userId)
        self.isTrusted = try container.decode(Bool.self, forKey: .isTrusted)
        self.lastUsedAt = try container.decode(Date.self, forKey: .lastUsedAt)
        self.registeredAt = try container.decode(Date.self, forKey: .registeredAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encode(deviceType, forKey: .deviceType)
        try container.encode(deviceIdentifier, forKey: .deviceIdentifier)
        try container.encode(isTrusted, forKey: .isTrusted)
        try container.encode(lastUsedAt, forKey: .lastUsedAt)
        try container.encode(registeredAt, forKey: .registeredAt)
    }
}

// MARK: - Authentication Request

struct AuthenticationRequest: Codable {
    let email: String
    let password: String
    let deviceName: String
    let deviceIdentifier: String
    let rememberDevice: Bool
}

// MARK: - Authentication Response

struct AuthenticationResponse: Codable {
    let user: User
    let session: UserSession
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let requiresTwoFactor: Bool
    let twoFactorMethods: [TwoFactorMethod]
}

// MARK: - Registration Request

struct RegistrationRequest: Codable {
    let email: String
    let password: String
    let confirmPassword: String
    let name: String?
    let agreeToTerms: Bool
    let deviceName: String
    let deviceIdentifier: String
}

// MARK: - Password Reset Request

struct PasswordResetRequest: Codable {
    let email: String
    let newPassword: String
    let resetToken: String
}

// MARK: - Two Factor Authentication

enum TwoFactorMethod: String, CaseIterable, Codable {
    case email = "email"
    case sms = "sms"
    case authenticatorApp = "authenticator_app"
    case biometric = "biometric"
    
    var displayName: String {
        switch self {
        case .email: return "Email"
        case .sms: return "SMS"
        case .authenticatorApp: return "Authenticator App"
        case .biometric: return "Biometric"
        }
    }
    
    var iconName: String {
        switch self {
        case .email: return "envelope"
        case .sms: return "message"
        case .authenticatorApp: return "key"
        case .biometric: return "faceid"
        }
    }
}

struct TwoFactorChallenge: Codable {
    let method: TwoFactorMethod
    let challengeId: String
    let maskedTarget: String // e.g., "em***@domain.com" or "***-***-1234"
    let expiresAt: Date
}

struct TwoFactorVerification: Codable {
    let challengeId: String
    let code: String
}

// MARK: - Helper Types for Network Requests

struct EmptyRequest: Codable {}

struct EmptyResponse: Codable {}

struct BiometricCredentials: Codable {
    let deviceId: String
    let publicKey: String
    let signature: String
    let timestamp: Date
}

// MARK: - Device Types

enum DeviceType: String, CaseIterable, Codable {
    case iphone = "iphone"
    case ipad = "ipad"
    case mac = "mac"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .iphone: return "iPhone"
        case .ipad: return "iPad"
        case .mac: return "Mac"
        case .unknown: return "Unknown Device"
        }
    }
}

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Codable {
    case light = "light"
    case dark = "dark"
    case system = "system"
    
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
}

// MARK: - Authentication State

enum AuthenticationState {
    case unauthenticated
    case authenticating
    case authenticated(User)
    case needsTwoFactor(TwoFactorChallenge)
    case error(AuthenticationError)
    
    var isAuthenticated: Bool {
        if case .authenticated(_) = self {
            return true
        }
        return false
    }
    
    var user: User? {
        if case .authenticated(let user) = self {
            return user
        }
        return nil
    }
}

// MARK: - Authentication Errors

enum AuthenticationError: LocalizedError, Equatable {
    case invalidCredentials
    case accountLocked
    case emailNotVerified
    case accountNotFound
    case emailAlreadyExists
    case weakPassword
    case invalidEmail
    case networkError
    case serverError(String)
    case sessionExpired
    case invalidTwoFactorCode
    case twoFactorRequired
    case biometricNotAvailable
    case biometricNotEnrolled
    case biometricFailed
    case deviceNotTrusted
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .accountLocked:
            return "Account has been locked due to too many failed attempts"
        case .emailNotVerified:
            return "Please verify your email address before signing in"
        case .accountNotFound:
            return "Account not found"
        case .emailAlreadyExists:
            return "An account with this email already exists"
        case .weakPassword:
            return "Password does not meet security requirements"
        case .invalidEmail:
            return "Invalid email address"
        case .networkError:
            return "Network connection error"
        case .serverError(let message):
            return "Server error: \(message)"
        case .sessionExpired:
            return "Your session has expired. Please sign in again"
        case .invalidTwoFactorCode:
            return "Invalid verification code"
        case .twoFactorRequired:
            return "Two-factor authentication is required"
        case .biometricNotAvailable:
            return "Biometric authentication is not available on this device"
        case .biometricNotEnrolled:
            return "No biometric identity is enrolled on this device"
        case .biometricFailed:
            return "Biometric authentication failed"
        case .deviceNotTrusted:
            return "This device is not trusted. Please verify your identity"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidCredentials:
            return "Check your email and password, or reset your password"
        case .accountLocked:
            return "Please wait 15 minutes and try again, or reset your password"
        case .emailNotVerified:
            return "Check your email for a verification link"
        case .weakPassword:
            return "Use a stronger password with at least 8 characters, including uppercase, lowercase, numbers, and symbols"
        case .biometricNotEnrolled:
            return "Enroll Face ID or Touch ID in Settings"
        default:
            return nil
        }
    }
}
