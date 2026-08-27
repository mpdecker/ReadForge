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

    // Everything here runs on-device with no backend (see CLAUDE.md's privacy rules), so
    // there's no server to verify a password against — it has to be checked locally. Salted
    // and hashed via `SecurityService`, never stored or compared in plain text. `nil` for
    // accounts that only ever sign in via biometrics.
    var passwordSalt: String?
    var passwordHash: String?

    init(email: String, name: String? = nil) {
        self.id = UUID()
        self.email = email.lowercased()
        self.name = name
        self.createdAt = Date()
        self.isEmailVerified = false
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, email, name, createdAt, lastLoginAt, isEmailVerified
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
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(email, forKey: .email)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastLoginAt, forKey: .lastLoginAt)
        try container.encode(isEmailVerified, forKey: .isEmailVerified)
    }
}

// MARK: - Authentication State

enum AuthenticationState {
    case unauthenticated
    case authenticating
    case authenticated(User)
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
    case accountNotFound
    case emailAlreadyExists
    case weakPassword
    case biometricFailed
    case biometricResetUnsupportedWithMultipleAccounts
    case reservedEmailAddress
    case tooManyAttempts

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .accountNotFound:
            return "Account not found"
        case .emailAlreadyExists:
            return "An account with this email already exists"
        case .weakPassword:
            return "Password does not meet security requirements"
        case .biometricFailed:
            return "Biometric authentication failed"
        case .biometricResetUnsupportedWithMultipleAccounts:
            return "Biometric password reset isn't available with more than one account on this device — Face ID/Touch ID proves you're this device's owner, not which account is yours. Sign in with your current password instead."
        case .reservedEmailAddress:
            return "This email address is reserved and can't be used for a password-protected account"
        case .tooManyAttempts:
            return "Too many failed sign-in attempts. Please wait a moment before trying again."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidCredentials:
            return "Check your email and password, or reset your password"
        case .weakPassword:
            return "Use a stronger password with at least 8 characters, including uppercase, lowercase, numbers, and symbols"
        default:
            return nil
        }
    }
}
