//
//  PasswordResetView.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import SwiftUI

/// Resets a forgotten password using Face ID / Touch ID as proof of identity.
///
/// There's no way to email a reset link or SMS a code in an offline-only app with no backend
/// (see CLAUDE.md's privacy rules) — the previous version had a "reset code" text field with
/// nothing to ever send that code, so it could never have worked. Biometric verification is the
/// one form of "prove it's you" that's genuinely available on-device.
struct PasswordResetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthenticationService
    @State private var email = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isResetting = false
    @State private var errorMessage = ""
    @State private var showingPasswordRequirements = false
    @State private var didSucceed = false

    private var biometricName: String {
        BiometricService().getBiometricDisplayName()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection

                    if didSucceed {
                        successSection
                    } else {
                        resetForm
                    }

                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel password reset")
                }
            }
            .errorAlert($errorMessage, title: "Password Reset Error")
            .sheet(isPresented: $showingPasswordRequirements) {
                PasswordRequirementsView(isPresented: $showingPasswordRequirements, password: newPassword)
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "faceid")
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            Text("Reset Your Password")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Verify it's you with \(biometricName), then set a new password.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var resetForm: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Email Address")
                    .font(.headline)
                TextField("Enter your email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Email address")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("New Password")
                        .font(.headline)
                    Button("Requirements") { showingPasswordRequirements.toggle() }
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
                SecureField("Create a new password", text: $newPassword)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("New password")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm New Password")
                    .font(.headline)
                SecureField("Confirm your new password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Confirm new password")
            }

            Button {
                resetPassword()
            } label: {
                if isResetting {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("Verifying with \(biometricName)…")
                    }
                } else {
                    Label("Verify with \(biometricName) & Reset", systemImage: "faceid")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canReset || isResetting)
            .accessibilityLabel("Verify identity and reset password")
        }
    }

    private var successSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.green)
            Text("Your password has been reset. You can now sign in with your new password.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var canReset: Bool {
        !email.isEmpty && !newPassword.isEmpty &&
        newPassword == confirmPassword && isValidPassword(newPassword)
    }

    private func resetPassword() {
        guard canReset else { return }
        isResetting = true
        errorMessage = ""

        Task {
            do {
                try await authService.resetPasswordWithBiometrics(email: email, newPassword: newPassword)
                await MainActor.run {
                    isResetting = false
                    didSucceed = true
                }
            } catch {
                await MainActor.run {
                    isResetting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func isValidPassword(_ password: String) -> Bool {
        password.count >= 8 &&
        password.range(of: "[A-Z]", options: .regularExpression) != nil &&
        password.range(of: "[a-z]", options: .regularExpression) != nil &&
        password.range(of: "[0-9]", options: .regularExpression) != nil &&
        password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil
    }
}
