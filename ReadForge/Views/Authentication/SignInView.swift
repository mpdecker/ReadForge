//
//  SignInView.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import SwiftUI
import LocalAuthentication

struct SignInView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var email = ""
    @State private var password = ""
    @State private var rememberDevice = false
    @State private var showingPasswordReset = false
    @State private var showingSignUp = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Logo and Title
                headerSection
                
                // Sign In Form
                signInForm
                
                // Additional Options
                additionalOptions
                
                Spacer()
            }
            .padding()
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.large)
            .errorAlert($errorMessage, title: "Sign In Error")
            .sheet(isPresented: $showingPasswordReset) {
                PasswordResetView()
            }
            .sheet(isPresented: $showingSignUp) {
                SignUpView()
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            
            Text("Welcome to ReadForge")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Sign in to access your library")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Sign In Form
    
    private var signInForm: some View {
        VStack(spacing: 16) {
            // Email Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
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
                Text("Password")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                SecureField("Enter your password", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Password")
                    .accessibilityHint("Enter your password")
            }
            
            // Remember Device
            Toggle("Remember this device", isOn: $rememberDevice)
                .accessibilityLabel("Remember this device")
                .accessibilityHint("Keep signed in on this device")
        }
    }
    
    // MARK: - Additional Options
    
    private var additionalOptions: some View {
        VStack(spacing: 16) {
            // Biometric Authentication Button
            if BiometricService().shouldOfferBiometricAuthentication() {
                biometricButton
            }
            
            // Sign In Button
            signInButton
            
            // Forgot Password & Sign Up Links
            actionLinks
        }
    }
    
    // MARK: - Biometric Button
    
    private var biometricButton: some View {
        Button {
            Task {
                await authService.authenticateWithBiometrics()
                reflectAuthenticationError()
            }
        } label: {
            HStack {
                Image(systemName: BiometricService().getBiometricType() == .faceID ? "faceid" : "touchid")
                Text("Sign in with \(BiometricService().getBiometricDisplayName())")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityLabel("Sign in with \(BiometricService().getBiometricDisplayName())")
        .accessibilityHint("Use biometric authentication to sign in")
    }
    
    // MARK: - Sign In Button
    
    private var signInButton: some View {
        Button {
            Task {
                await authService.signIn(
                    email: email,
                    password: password,
                    deviceName: UIDevice.current.name,
                    rememberDevice: rememberDevice
                )
                reflectAuthenticationError()
            }
        } label: {
            if authService.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Signing In...")
                }
            } else {
                Text("Sign In")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(email.isEmpty || password.isEmpty || authService.isLoading)
        .accessibilityLabel("Sign in")
        .accessibilityHint("Sign in to your account")
    }
    
    // MARK: - Action Links
    
    private var actionLinks: some View {
        VStack(spacing: 12) {
            Button("Forgot Password?") {
                showingPasswordReset = true
            }
            .font(.footnote)
            .foregroundStyle(.tint)
            .accessibilityLabel("Forgot password")
            .accessibilityHint("Reset your password")
            
            HStack {
                Text("Don't have an account?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                Button("Sign Up") {
                    showingSignUp = true
                }
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
                .accessibilityLabel("Sign up")
                .accessibilityHint("Create a new account")
            }
        }
    }

    // MARK: - Error Reflection

    /// `signIn`/`authenticateWithBiometrics` don't throw — a failure is expressed by setting
    /// `authenticationState` to `.error(...)`. Nothing previously read that back out into this
    /// view's own `errorMessage`/alert, so a wrong password or a failed Face ID/Touch ID
    /// attempt produced no visible feedback at all: the button's spinner just stopped and the
    /// screen sat there. Called right after each `await` above.
    private func reflectAuthenticationError() {
        if case .error(let error) = authService.authenticationState {
            errorMessage = error.localizedDescription
        }
    }
}

// Two-factor authentication was removed: it needs a delivery mechanism (SMS, email, or an
// authenticator app) that a fully offline, no-backend app has no way to provide (see
// CLAUDE.md's privacy rules and NetworkService), so the sheet here was previously unreachable
// dead code with nothing behind it.
