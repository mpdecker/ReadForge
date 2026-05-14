//
//  ProfileView.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authService: AuthenticationService
    @State private var showingEditProfile = false
    @State private var showingDeviceManagement = false
    @State private var showingPasswordChange = false
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            List {
                // User Information Section
                userSection

                // Account Settings Section
                accountSettingsSection

                // Security Section
                securitySection

                // App Settings Section
                appSettingsSection

                // Danger Zone Section
                dangerZoneSection
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityLabel("Done")
                }
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView()
                    .environmentObject(authService)
            }
            .sheet(isPresented: $showingDeviceManagement) {
                DeviceManagementView()
                    .environmentObject(authService)
            }
            .sheet(isPresented: $showingPasswordChange) {
                ChangePasswordView()
                    .environmentObject(authService)
            }
            .alert("Error", isPresented: .constant(!errorMessage.isEmpty)) {
                Button("OK") { errorMessage = "" }
            } message: {
                Text(errorMessage)
            }
        }
        .environmentObject(authService)
    }
    
    // MARK: - User Section
    
    private var userSection: some View {
        Section {
            HStack(spacing: 16) {
                // Avatar
                Circle()
                    .fill(.primary.opacity(0.1))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Text(getUserInitials())
                            .font(.title)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(authService.currentUser?.name ?? "User")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(authService.currentUser?.email ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if let createdAt = authService.currentUser?.createdAt {
                        Text("Member since \(createdAt.formatted(.dateTime.year().month()))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
                
                Button("Edit") {
                    showingEditProfile = true
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Edit profile")
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Account Settings Section
    
    private var accountSettingsSection: some View {
        Section("Account Settings") {
            NavigationLink("Device Management") {
                DeviceManagementView()
            }
            .accessibilityLabel("Manage trusted devices")
            
            NavigationLink("Email Preferences") {
                EmailPreferencesView()
            }
            .accessibilityLabel("Email notification preferences")
        }
    }
    
    // MARK: - Security Section
    
    private var securitySection: some View {
        Section("Security") {
            NavigationLink("Change Password") {
                ChangePasswordView()
            }
            .accessibilityLabel("Change password")
            
            NavigationLink("Two-Factor Authentication") {
                TwoFactorSettingsView()
            }
            .accessibilityLabel("Two-factor authentication settings")
            
            if BiometricService().shouldOfferBiometricAuthentication() {
                Toggle("Biometric Authentication", isOn: .constant(true))
                    .disabled(true)
                    .accessibilityLabel("Biometric authentication is enabled")
            }
        }
    }
    
    // MARK: - App Settings Section
    
    private var appSettingsSection: some View {
        Section("App Settings") {
            NavigationLink("Notifications") {
                NotificationSettingsView()
            }
            .accessibilityLabel("Notification settings")
            
            NavigationLink("Privacy") {
                PrivacySettingsView()
            }
            .accessibilityLabel("Privacy settings")
            
            NavigationLink("Data & Storage") {
                DataStorageView()
            }
            .accessibilityLabel("Data and storage settings")
        }
    }
    
    // MARK: - Danger Zone Section
    
    private var dangerZoneSection: some View {
        Section("Danger Zone") {
            Button("Sign Out") {
                Task {
                    await authService.signOut()
                    dismiss()
                }
            }
            .foregroundStyle(.red)
            .accessibilityLabel("Sign out of your account")
            
            Button("Delete Account") {
                // Show confirmation dialog
            }
            .foregroundStyle(.red)
            .accessibilityLabel("Delete your account")
        }
    }
    
    // MARK: - Helper Methods
    
    private func getUserInitials() -> String {
        guard let name = authService.currentUser?.name, !name.isEmpty else {
            let letter = authService.currentUser?.email.first ?? Character("U")
            return String(letter).uppercased()
        }

        let components = name.components(separatedBy: " ")
        return components.map { String($0.prefix(1)) }.joined().uppercased()
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authService: AuthenticationService
    @State private var name = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Information") {
                    TextField("Full Name", text: $name)
                        .textContentType(.name)
                        .autocapitalization(.words)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Full name")
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityLabel("Cancel")
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveProfile()
                    }
                    .disabled(name.isEmpty || isLoading)
                    .accessibilityLabel("Save profile changes")
                }
            }
            .alert("Error", isPresented: .constant(!errorMessage.isEmpty)) {
                Button("OK") { errorMessage = "" }
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            name = authService.currentUser?.name ?? ""
        }
    }
    
    private func saveProfile() {
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                guard let user = authService.currentUser else { return }
                
                let updatedUser = user
                updatedUser.name = name.isEmpty ? nil : name
                
                _ = try await NetworkService().updateUserProfile(updatedUser, accessToken: try await getAccessToken())
                
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
    
    private func getAccessToken() -> String {
        // This would come from the token storage
        return ""
    }
}

// MARK: - Device Management View

struct DeviceManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authService: AuthenticationService
    @State private var devices: [UserDevice] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(devices) { device in
                    DeviceRowView(device: device)
                }
                .onDelete(perform: deleteDevice)
            }
            .navigationTitle("Device Management")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                loadDevices()
            }
        }
        .onAppear {
            loadDevices()
        }
    }
    
    private func loadDevices() {
        guard let user = authService.currentUser else { return }
        
        isLoading = true
        
        Task {
            do {
                let networkService = NetworkService()
                devices = try await networkService.getDevices(user.id, accessToken: try await getAccessToken())
                isLoading = false
            } catch {
                isLoading = false
                // Handle error
            }
        }
    }
    
    private func deleteDevice(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        let device = devices[index]
        
        Task {
            do {
                let networkService = NetworkService()
                try await networkService.revokeDevice(device.id, accessToken: try await getAccessToken())
                
                await MainActor.run {
                    devices.remove(atOffsets: offsets)
                }
            } catch {
                // Handle error
            }
        }
    }
    
    private func getAccessToken() async throws -> String {
        guard let accessToken = try await TokenManager.shared.getAccessToken() else {
            throw AuthenticationError.sessionExpired
        }
        return accessToken
    }
}

// MARK: - Device Row View

struct DeviceRowView: View {
    let device: UserDevice
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: getDeviceIcon())
                        .foregroundStyle(.primary)
                    
                    Text(device.deviceName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                
                if device.isTrusted {
                    Label("Trusted", systemImage: "checkmark.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(device.deviceType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("Last used: \(device.lastUsedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func getDeviceIcon() -> String {
        switch device.deviceType {
        case .iphone: return "iphone"
        case .ipad: return "ipad"
        case .mac: return "desktopcomputer"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - Change Password View

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
                        .accessibilityHint("Enter your current password")
                }
                
                Section("New Password") {
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
                }
                
                Section {
                    Button {
                        changePassword()
                    } label: {
                        if isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Changing Password...")
                            }
                        } else {
                            Text("Change Password")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canChangePassword || isLoading)
                    .accessibilityLabel("Change password")
                    .accessibilityHint("Update your password")
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityLabel("Cancel password change")
                }
            }
            .alert("Error", isPresented: .constant(!errorMessage.isEmpty)) {
                Button("OK") { errorMessage = "" }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingPasswordRequirements) {
                PasswordRequirementsView(isPresented: $showingPasswordRequirements, password: newPassword)
            }
        }
    }
    
    private var canChangePassword: Bool {
        return !currentPassword.isEmpty &&
               !newPassword.isEmpty &&
               !confirmPassword.isEmpty &&
               newPassword == confirmPassword &&
               isValidPassword(newPassword)
    }
    
    private func changePassword() {
        guard canChangePassword else { return }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                let networkService = NetworkService()
                try await networkService.changePassword(
                    currentPassword: currentPassword,
                    newPassword: newPassword,
                    accessToken: try await getAccessToken()
                )
                
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
    
    private func getAccessToken() async throws -> String {
        guard let accessToken = try await TokenManager.shared.getAccessToken() else {
            throw AuthenticationError.sessionExpired
        }
        return accessToken
    }
    
    private func isValidPassword(_ password: String) -> Bool {
        return password.count >= 8 &&
               password.range(of: "[A-Z]", options: .regularExpression) != nil &&
               password.range(of: "[a-z]", options: .regularExpression) != nil &&
               password.range(of: "[0-9]", options: .regularExpression) != nil &&
               password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil
    }
}

// MARK: - Two-Factor Settings View

struct TwoFactorSettingsView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var isEnabled = false
    @State private var selectedMethod: TwoFactorMethod = .email
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Two-Factor Authentication") {
                    Toggle("Enable Two-Factor Authentication", isOn: $isEnabled)
                        .toggleStyle(.switch)
                        .accessibilityLabel("Enable two-factor authentication")
                        .accessibilityHint("Add an extra layer of security to your account")
                }
                
                if isEnabled {
                    Section("Authentication Method") {
                        Picker("Method", selection: $selectedMethod) {
                            ForEach(TwoFactorMethod.allCases, id: \.self) { method in
                                Label(method.displayName, systemImage: method.iconName)
                                    .tag(method)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityLabel("Authentication method")
                    }
                    
                    Section {
                        Button("Set Up \(selectedMethod.displayName)") {
                            setupTwoFactor()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isLoading)
                        .accessibilityLabel("Set up two-factor authentication")
                        .accessibilityHint("Configure two-factor authentication with selected method")
                    }
                }
            }
            .navigationTitle("Two-Factor Authentication")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: .constant(!errorMessage.isEmpty)) {
                Button("OK") { errorMessage = "" }
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            // Load current 2FA settings
            loadTwoFactorSettings()
        }
    }
    
    private func loadTwoFactorSettings() {
        // Load user's current 2FA settings from API
        // This would make an API call to get current settings
    }
    
    private func setupTwoFactor() {
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                // API call to set up 2FA
                // This would initiate the 2FA setup process
                
                await MainActor.run {
                    isLoading = false
                    // Handle success - maybe show verification screen
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Email Preferences View

struct EmailPreferencesView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var emailNotifications = true
    @State private var securityAlerts = true
    @State private var productUpdates = false
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Email Notifications") {
                    Toggle("Document Processing Updates", isOn: $emailNotifications)
                        .toggleStyle(.switch)
                        .accessibilityLabel("Document processing email notifications")
                    
                    Toggle("Security Alerts", isOn: $securityAlerts)
                        .toggleStyle(.switch)
                        .accessibilityLabel("Security alert emails")
                    
                    Toggle("Product Updates", isOn: $productUpdates)
                        .toggleStyle(.switch)
                        .accessibilityLabel("Product update emails")
                }
                
                Section {
                    Button("Save Preferences") {
                        saveEmailPreferences()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isLoading)
                    .accessibilityLabel("Save email preferences")
                }
            }
            .navigationTitle("Email Preferences")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            loadEmailPreferences()
        }
    }
    
    private func loadEmailPreferences() {
        // Load user's current email preferences
        // This would make an API call to get current preferences
    }
    
    private func saveEmailPreferences() {
        isLoading = true
        
        Task {
            do {
                // API call to save email preferences
                // This would update the user's preferences
                
                await MainActor.run {
                    isLoading = false
                    // Handle success
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    // Handle error
                }
            }
        }
    }
}

// MARK: - Notification Settings View

struct NotificationSettingsView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var pushNotifications = true
    @State private var soundEnabled = true
    @State private var badgeEnabled = true
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Push Notifications") {
                    Toggle("Enable Push Notifications", isOn: $pushNotifications)
                        .toggleStyle(.switch)
                        .accessibilityLabel("Enable push notifications")
                    
                    if pushNotifications {
                        Toggle("Sound", isOn: $soundEnabled)
                            .toggleStyle(.switch)
                            .accessibilityLabel("Notification sound")
                        
                        Toggle("App Badge", isOn: $badgeEnabled)
                            .toggleStyle(.switch)
                            .accessibilityLabel("App badge notifications")
                    }
                }
                
                Section {
                    Button("Save Settings") {
                        saveNotificationSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isLoading)
                    .accessibilityLabel("Save notification settings")
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            loadNotificationSettings()
        }
    }
    
    private func loadNotificationSettings() {
        // Load user's current notification settings
        // This would make an API call to get current settings
    }
    
    private func saveNotificationSettings() {
        isLoading = true
        
        Task {
            do {
                // API call to save notification settings
                // This would update the user's notification settings
                
                await MainActor.run {
                    isLoading = false
                    // Handle success
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    // Handle error
                }
            }
        }
    }
}

// MARK: - Privacy Settings View

struct PrivacySettingsView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var analyticsEnabled = false
    @State private var crashReporting = true
    @State private var usageData = false
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Data Collection") {
                    Toggle("Analytics", isOn: $analyticsEnabled)
                        .toggleStyle(.switch)
                        .accessibilityLabel("Share analytics data")
                    
                    Toggle("Crash Reporting", isOn: $crashReporting)
                        .toggleStyle(.switch)
                        .accessibilityLabel("Share crash reports")
                    
                    Toggle("Usage Data", isOn: $usageData)
                        .toggleStyle(.switch)
                        .accessibilityLabel("Share usage data")
                }
                
                Section {
                    Button("Save Privacy Settings") {
                        savePrivacySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isLoading)
                    .accessibilityLabel("Save privacy settings")
                }
            }
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            loadPrivacySettings()
        }
    }
    
    private func loadPrivacySettings() {
        // Load user's current privacy settings
        // This would make an API call to get current settings
    }
    
    private func savePrivacySettings() {
        isLoading = true
        
        Task {
            do {
                // API call to save privacy settings
                // This would update the user's privacy settings
                
                await MainActor.run {
                    isLoading = false
                    // Handle success
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    // Handle error
                }
            }
        }
    }
}

// MARK: - Data & Storage View

struct DataStorageView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var cacheSize: Double = 0
    @State private var documentCount = 0
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Storage Usage") {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading) {
                            Text("Documents")
                                .font(.headline)
                            Text("\(documentCount) documents")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    HStack {
                        Image(systemName: "externaldrive")
                            .foregroundStyle(.orange)
                        
                        VStack(alignment: .leading) {
                            Text("Cache")
                                .font(.headline)
                            Text("\(String(format: "%.1f", cacheSize)) MB")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                
                Section("Actions") {
                    Button("Clear Cache") {
                        clearCache()
                    }
                    .foregroundStyle(.red)
                    .accessibilityLabel("Clear cache")
                    
                    Button("Export Data") {
                        exportData()
                    }
                    .accessibilityLabel("Export data")
                    
                    Button("Delete Account") {
                        deleteAccount()
                    }
                    .foregroundStyle(.red)
                    .accessibilityLabel("Delete account")
                }
            }
            .navigationTitle("Data & Storage")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                loadData()
            }
        }
        .onAppear {
            loadData()
        }
    }
    
    private func loadData() {
        isLoading = true
        
        Task {
            // Load storage data
            // This would calculate actual cache size and document count
            
            await MainActor.run {
                cacheSize = 12.5 // Example value
                documentCount = 24 // Example value
                isLoading = false
            }
        }
    }
    
    private func clearCache() {
        // Clear cache implementation
        // This would clear the app's cache
    }
    
    private func exportData() {
        // Export data implementation
        // This would export user's data
    }
    
    private func deleteAccount() {
        // Delete account implementation
        // This would show confirmation and delete the account
    }
}
