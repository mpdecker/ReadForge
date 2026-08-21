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
    @EnvironmentObject private var authService: AuthenticationService
    @State private var showingEditProfile = false
    @State private var showingPasswordChange = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            List {
                userSection
                accountSettingsSection
                securitySection
                appSettingsSection
                dangerZoneSection
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Done")
                }
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView().environmentObject(authService)
            }
            .sheet(isPresented: $showingPasswordChange) {
                ChangePasswordView().environmentObject(authService)
            }
            .errorAlert($errorMessage)
            .deleteAccountConfirmation(isPresented: $showingDeleteConfirmation) { deleteAccount() }
        }
        .environmentObject(authService)
    }

    // MARK: - User Section

    private var userSection: some View {
        Section {
            HStack(spacing: 16) {
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

                Button("Edit") { showingEditProfile = true }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Edit profile")
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Account Settings Section

    private var accountSettingsSection: some View {
        Section("Account Settings") {
            NavigationLink("This Device") {
                DeviceManagementView()
            }
            .accessibilityLabel("This device")
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Section("Security") {
            Button("Change Password") { showingPasswordChange = true }
                .accessibilityLabel("Change password")

            if BiometricService().shouldOfferBiometricAuthentication() {
                Label("\(BiometricService().getBiometricDisplayName()) available for sign-in", systemImage: "faceid")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - App Settings Section

    private var appSettingsSection: some View {
        Section("App Settings") {
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

            Button("Delete Account") { showingDeleteConfirmation = true }
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

    private func deleteAccount() {
        Task {
            do {
                try await authService.deleteAccount()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
