//
//  SimpleAuthenticationService.swift
//  ReadForge
//
//  Simplified authentication for local document reader app
//

import Foundation
import SwiftData

/// Simple authentication service for local app usage
@MainActor
@Observable
final class SimpleAuthenticationService {

    // MARK: - Properties

    private(set) var isUnlocked = false
    private(set) var errorMessage: String?

    // MARK: - Initialization

    init() {
        checkUnlockStatus()
    }

    /// Designated for callers that already hold a SwiftData context (e.g. tests); persistence is unused for now.
    init(modelContext _: ModelContext) {
        checkUnlockStatus()
    }

    // MARK: - Public Methods

    /// Simple unlock with optional passcode
    func unlock(with passcode: String? = nil) {
        // For now, just unlock without any complex authentication
        // This can be enhanced later if needed
        isUnlocked = true
        errorMessage = nil
        ReadForgeLogger.debug(category: "Auth", message: "App unlocked")
    }

    /// Lock the app
    func lock() {
        isUnlocked = false
        ReadForgeLogger.debug(category: "Auth", message: "App locked")
    }

    /// Check if app is unlocked
    func checkUnlockStatus() {
        // Simple check - could be enhanced with biometrics later
        isUnlocked = true
    }

    /// Clear any error messages
    func clearError() {
        errorMessage = nil
    }
}
