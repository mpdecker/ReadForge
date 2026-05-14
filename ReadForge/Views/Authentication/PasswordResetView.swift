//
//  PasswordResetView.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import SwiftUI
import SwiftData

struct PasswordResetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var resetToken = ""
    @State private var isRequestingReset = false
    @State private var isConfirmingReset = false
    @State private var errorMessage = ""
    @State private var showingPasswordRequirements = false
    @State private var resetRequested = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    if !resetRequested {
                        // Request Password Reset Form
                        requestResetForm
                    } else {
                        // Confirm Password Reset Form
                        confirmResetForm
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle(resetRequested ? "Reset Password" : "Forgot Password")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityLabel("Cancel password reset")
                }
            }
            .alert("Password Reset Error", isPresented: .constant(!errorMessage.isEmpty)) {
                Button("OK") { errorMessage = "" }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingPasswordRequirements) {
                PasswordRequirementsView(isPresented: $showingPasswordRequirements, password: newPassword)
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "key")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            
            Text(resetRequested ? "Reset Your Password" : "Forgot Password?")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(resetRequested ? 
                 "Enter your new password below" : 
                 "Enter your email address and we'll send you instructions to reset your password")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Request Reset Form
    
    private var requestResetForm: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Email Address")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                TextField("Enter your email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Email address")
                    .accessibilityHint("Enter your email address")
            }
            
            Button {
                requestPasswordReset()
            } label: {
                if isRequestingReset {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Sending Instructions...")
                    }
                } else {
                    Text("Send Reset Instructions")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(email.isEmpty || isRequestingReset)
            .accessibilityLabel("Send password reset instructions")
            .accessibilityHint("Send password reset email")
        }
    }
    
    // MARK: - Confirm Reset Form
    
    private var confirmResetForm: some View {
        VStack(spacing: 16) {
            Text("Enter the reset code from your email and create a new password")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)
            
            // Reset Token Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Reset Code")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                TextField("Enter reset code", text: $resetToken)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Reset code")
                    .accessibilityHint("Enter the reset code from your email")
            }
            
            // New Password Field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("New Password")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Button("Requirements") {
                        showingPasswordRequirements.toggle()
                    }
                    .font(.caption)
                    .foregroundStyle(.tint)
                }
                
                SecureField("Create a new password", text: $newPassword)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("New password")
                    .accessibilityHint("Create a new secure password")
            }
            
            // Confirm Password Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm New Password")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                SecureField("Confirm your new password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Confirm new password")
                    .accessibilityHint("Enter your new password again to confirm")
            }
            
            // Reset Password Button
            Button {
                confirmPasswordReset()
            } label: {
                if isConfirmingReset {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Resetting Password...")
                    }
                } else {
                    Text("Reset Password")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canConfirmReset || isConfirmingReset)
            .accessibilityLabel("Reset password")
            .accessibilityHint("Reset your password with the provided code")
        }
    }
    
    // MARK: - Computed Properties
    
    private var canConfirmReset: Bool {
        return !resetToken.isEmpty &&
               !newPassword.isEmpty &&
               !confirmPassword.isEmpty &&
               newPassword == confirmPassword &&
               isValidPassword(newPassword)
    }
    
    // MARK: - Private Methods
    
    private func requestPasswordReset() {
        guard !email.isEmpty else { return }
        
        isRequestingReset = true
        errorMessage = ""
        
        Task {
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                let container = try ModelContainer(
                    for: User.self, UserPreferences.self, UserSession.self, UserDevice.self,
                    configurations: config
                )
                let authService = AuthenticationService(modelContext: ModelContext(container))
                try await authService.resetPassword(email: email)
                
                await MainActor.run {
                    isRequestingReset = false
                    resetRequested = true
                }
            } catch {
                await MainActor.run {
                    isRequestingReset = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func confirmPasswordReset() {
        guard canConfirmReset else { return }
        
        isConfirmingReset = true
        errorMessage = ""
        
        Task {
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                let container = try ModelContainer(
                    for: User.self, UserPreferences.self, UserSession.self, UserDevice.self,
                    configurations: config
                )
                let authService = AuthenticationService(modelContext: ModelContext(container))
                try await authService.confirmPasswordReset(
                    email: email,
                    newPassword: newPassword,
                    resetToken: resetToken
                )
                
                await MainActor.run {
                    isConfirmingReset = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isConfirmingReset = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func isValidPassword(_ password: String) -> Bool {
        return password.count >= 8 &&
               password.range(of: "[A-Z]", options: .regularExpression) != nil &&
               password.range(of: "[a-z]", options: .regularExpression) != nil &&
               password.range(of: "[0-9]", options: .regularExpression) != nil &&
               password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil
    }
}

// MARK: - Success View

struct PasswordResetSuccessView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            Text("Password Reset Successful")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Your password has been reset successfully. You can now sign in with your new password.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Sign In") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel("Sign in")
            .accessibilityHint("Go to sign in screen")
            
            Spacer(minLength: 100)
        }
        .padding()
    }
}
