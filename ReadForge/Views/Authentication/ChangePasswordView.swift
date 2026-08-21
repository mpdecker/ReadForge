//
//  ChangePasswordView.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import SwiftUI

struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthenticationService
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showingPasswordRequirements = false
    @State private var isLoading = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Password") {
                    SecureField("Enter current password", text: $currentPassword)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Current password")
                }

                Section("New Password") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("New Password").font(.headline)
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
                        Text("Confirm New Password").font(.headline)
                        SecureField("Confirm your new password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Confirm new password")
                    }
                }

                Section {
                    Button {
                        changePassword()
                    } label: {
                        if isLoading {
                            HStack { ProgressView().scaleEffect(0.8); Text("Changing Password...") }
                        } else {
                            Text("Change Password")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canChangePassword || isLoading)
                    .accessibilityLabel("Change password")
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel password change")
                }
            }
            .errorAlert($errorMessage)
            .sheet(isPresented: $showingPasswordRequirements) {
                PasswordRequirementsView(isPresented: $showingPasswordRequirements, password: newPassword)
            }
        }
    }

    private var canChangePassword: Bool {
        !currentPassword.isEmpty && !newPassword.isEmpty &&
        newPassword == confirmPassword && isValidPassword(newPassword)
    }

    private func changePassword() {
        guard canChangePassword else { return }
        isLoading = true
        errorMessage = ""

        Task {
            do {
                try await authService.changePassword(currentPassword: currentPassword, newPassword: newPassword)
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
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
