//
//  EditProfileView.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import SwiftUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
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
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveProfile() }
                        .disabled(name.isEmpty || isLoading)
                        .accessibilityLabel("Save profile changes")
                }
            }
            .errorAlert($errorMessage)
        }
        .onAppear { name = authService.currentUser?.name ?? "" }
    }

    private func saveProfile() {
        isLoading = true
        errorMessage = ""
        Task {
            do {
                try await authService.updateProfile(name: name)
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
}
