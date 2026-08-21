//
//  DeviceManagementView.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//
// There's no account backend and no multi-device sync (see CLAUDE.md's "Do Not Build Yet"
// list) — the previous version fetched a device list from a network call that went nowhere.
// This shows the one device that's actually real: the one you're using.

import SwiftUI

struct DeviceManagementView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: deviceIcon)
                            Text(UIDevice.current.name)
                                .font(.headline)
                        }
                        Label("This device", systemImage: "checkmark.shield.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    Text(UIDevice.current.systemName + " " + UIDevice.current.systemVersion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Text("ReadForge doesn't sync accounts across devices — everything you import stays on this device. Use Settings › Backup to move your library to another device manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("This Device")
        .navigationBarTitleDisplayMode(.large)
    }

    private var deviceIcon: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }
}
