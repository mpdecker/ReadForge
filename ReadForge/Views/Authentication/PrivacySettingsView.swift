//
//  PrivacySettingsView.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import SwiftUI

struct PrivacySettingsView: View {
    /// CLAUDE.md's privacy rules explicitly call for this: "Offline-only mode is a first-class
    /// setting." It gates the one place ReadForge ever touches the network at all — prompting
    /// to download higher-quality system voices in Settings (see `SettingsView`).
    @AppStorage("offlineOnlyMode") private var offlineOnlyMode: Bool = true

    var body: some View {
        Form {
            Section {
                Toggle("Offline-Only Mode", isOn: $offlineOnlyMode)
                Text("When on, ReadForge won't suggest downloading higher-quality voices (the only feature that touches the network at all — everything else already runs fully on-device).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("What ReadForge Never Does") {
                Label("Upload your documents", systemImage: "xmark.circle")
                Label("Send analytics on document content", systemImage: "xmark.circle")
                Label("Sync your account to a server — there isn't one", systemImage: "xmark.circle")
            }
            .foregroundStyle(.secondary)
            .font(.subheadline)
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
