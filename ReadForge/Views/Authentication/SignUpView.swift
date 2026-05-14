//
//  SignUpView.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import SwiftUI
import SwiftData

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var agreeToTerms = false
    @State private var showingPasswordRequirements = false
    @State private var errorMessage = ""
    @State private var isCreatingAccount = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Sign Up Form
                    signUpForm
                    
                    // Terms and Submit
                    termsAndSubmitSection
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityLabel("Cancel account creation")
                }
            }
            .alert("Sign Up Error", isPresented: .constant(!errorMessage.isEmpty)) {
                Button("OK") { errorMessage = "" }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            
            Text("Create Your Account")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Join ReadForge to transform your documents into audio")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Sign Up Form
    
    private var signUpForm: some View {
        VStack(spacing: 20) {
            // Name Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Full Name")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                TextField("Enter your full name", text: $name)
                    .textContentType(.name)
                    .autocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Full name")
                    .accessibilityHint("Enter your full name")
            }
            
            // Email Field
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
            
            // Password Field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Password")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Button("Requirements") {
                        showingPasswordRequirements.toggle()
                    }
                    .font(.caption)
                    .foregroundStyle(.tint)
                }
                
                SecureField("Create a password", text: $password)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Password")
                    .accessibilityHint("Create a secure password")
            }
            
            // Confirm Password Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                SecureField("Confirm your password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Confirm password")
                    .accessibilityHint("Enter your password again to confirm")
            }
        }
    }
    
    // MARK: - Terms and Submit Section
    
    private var termsAndSubmitSection: some View {
        VStack(spacing: 16) {
            // Terms Agreement
            VStack(alignment: .leading, spacing: 8) {
                Toggle("I agree to the Terms of Service and Privacy Policy", isOn: $agreeToTerms)
                    .toggleStyle(.switch)
                    .accessibilityLabel("I agree to the Terms of Service and Privacy Policy")
                    .accessibilityHint("Toggle to agree to terms and conditions")
                
                HStack {
                    Button("Terms of Service") {
                        // Open terms in Safari
                        if let url = URL(string: "https://readforge.app/terms") {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.tint)
                    
                    Text("and")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Button("Privacy Policy") {
                        // Open privacy policy in Safari
                        if let url = URL(string: "https://readforge.app/privacy") {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.tint)
                }
            }
            
            // Create Account Button
            Button {
                createAccount()
            } label: {
                if isCreatingAccount {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Creating Account...")
                    }
                } else {
                    Text("Create Account")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canCreateAccount || isCreatingAccount)
            .accessibilityLabel("Create account")
            .accessibilityHint("Create your ReadForge account")
        }
    }
    
    // MARK: - Password Requirements
    
    private var passwordRequirementsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Password Requirements:")
                .font(.headline)
                .foregroundStyle(.primary)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: password.count >= 8 ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(password.count >= 8 ? .green : .secondary)
                    Text("At least 8 characters")
                        .font(.body)
                        .foregroundStyle(password.count >= 8 ? .primary : .secondary)
                }
                
                HStack {
                    Image(systemName: password.range(of: "[A-Z]", options: .regularExpression) != nil ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(password.range(of: "[A-Z]", options: .regularExpression) != nil ? .green : .secondary)
                    Text("One uppercase letter")
                        .font(.body)
                        .foregroundStyle(password.range(of: "[A-Z]", options: .regularExpression) != nil ? .primary : .secondary)
                }
                
                HStack {
                    Image(systemName: password.range(of: "[a-z]", options: .regularExpression) != nil ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(password.range(of: "[a-z]", options: .regularExpression) != nil ? .green : .secondary)
                    Text("One lowercase letter")
                        .font(.body)
                        .foregroundStyle(password.range(of: "[a-z]", options: .regularExpression) != nil ? .primary : .secondary)
                }
                
                HStack {
                    Image(systemName: password.range(of: "[0-9]", options: .regularExpression) != nil ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(password.range(of: "[0-9]", options: .regularExpression) != nil ? .green : .secondary)
                    Text("One number")
                        .font(.body)
                        .foregroundStyle(password.range(of: "[0-9]", options: .regularExpression) != nil ? .primary : .secondary)
                }
                
                HStack {
                    Image(systemName: password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil ? .green : .secondary)
                    Text("One special character")
                        .font(.body)
                        .foregroundStyle(password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil ? .primary : .secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(radius: 4)
    }
    
    // MARK: - Computed Properties
    
    private var canCreateAccount: Bool {
        return !email.isEmpty &&
               !password.isEmpty &&
               !confirmPassword.isEmpty &&
               password == confirmPassword &&
               agreeToTerms &&
               isValidEmail(email) &&
               isValidPassword(password)
    }
    
    // MARK: - Private Methods
    
    private func createAccount() {
        guard canCreateAccount else { return }
        
        isCreatingAccount = true
        errorMessage = ""
        
        Task {
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                let container = try ModelContainer(
                    for: User.self, UserPreferences.self, UserSession.self, UserDevice.self,
                    configurations: config
                )
                let authService = AuthenticationService(modelContext: ModelContext(container))
                try await authService.register(
                    email: email,
                    password: password,
                    confirmPassword: confirmPassword,
                    name: name.isEmpty ? nil : name,
                    agreeToTerms: agreeToTerms
                )
                
                await MainActor.run {
                    isCreatingAccount = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isCreatingAccount = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }
    
    private func isValidPassword(_ password: String) -> Bool {
        return password.count >= 8 &&
               password.range(of: "[A-Z]", options: .regularExpression) != nil &&
               password.range(of: "[a-z]", options: .regularExpression) != nil &&
               password.range(of: "[0-9]", options: .regularExpression) != nil &&
               password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil
    }
}

// MARK: - Password Requirements View

struct PasswordRequirementsView: View {
    @Binding var isPresented: Bool
    let password: String
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Password Requirements")
                    .font(.title2)
                    .fontWeight(.bold)
                
                VStack(alignment: .leading, spacing: 8) {
                    requirementRow(
                        text: "At least 8 characters",
                        isMet: password.count >= 8
                    )
                    
                    requirementRow(
                        text: "One uppercase letter",
                        isMet: password.range(of: "[A-Z]", options: .regularExpression) != nil
                    )
                    
                    requirementRow(
                        text: "One lowercase letter",
                        isMet: password.range(of: "[a-z]", options: .regularExpression) != nil
                    )
                    
                    requirementRow(
                        text: "One number",
                        isMet: password.range(of: "[0-9]", options: .regularExpression) != nil
                    )
                    
                    requirementRow(
                        text: "One special character",
                        isMet: password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil
                    )
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Requirements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private func requirementRow(text: String, isMet: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isMet ? .green : .secondary)
            
            Text(text)
                .font(.body)
                .foregroundStyle(isMet ? .primary : .secondary)
        }
    }
}
