//
//  DataStorageView.swift
//  ReadForge
//
//  Created by Matthieu Decker on 5/10/26.
//

import SwiftUI
import SwiftData

struct DataStorageView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthenticationService
    @State private var cacheSizeMB: Double = 0
    @State private var documentCount = 0
    @State private var showingExporter = false
    @State private var exportURL: URL?
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage = ""

    private let audioCache = AudioCacheService.shared

    var body: some View {
        List {
            Section("Storage Usage") {
                LabeledContent {
                    Text("\(documentCount)")
                } label: {
                    Label("Documents", systemImage: "doc.text")
                }
                LabeledContent {
                    Text(String(format: "%.1f MB", cacheSizeMB))
                } label: {
                    Label("Audio Cache", systemImage: "externaldrive")
                }
            }

            Section("Actions") {
                Button("Clear Audio Cache", role: .destructive) { clearCache() }
                Button("Export Backup…") { exportData() }
                Button("Delete Account", role: .destructive) { showingDeleteConfirmation = true }
            }
        }
        .navigationTitle("Data & Storage")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadData() }
        .task { await loadData() }
        .fileMover(isPresented: $showingExporter, file: exportURL) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .errorAlert($errorMessage)
        .deleteAccountConfirmation(isPresented: $showingDeleteConfirmation) { deleteAccount() }
    }

    private func loadData() async {
        documentCount = (try? modelContext.fetchCount(FetchDescriptor<DocumentRecord>())) ?? 0
        cacheSizeMB = await audioCache.totalSizeMB()
    }

    private func clearCache() {
        Task {
            await audioCache.clearAll()
            await loadData()
        }
    }

    private func exportData() {
        Task {
            do {
                exportURL = try await BackupService().exportBackup(context: modelContext)
                showingExporter = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteAccount() {
        Task {
            do {
                try await authService.deleteAccount()
                // Previously missing here (unlike ProfileView's own delete-account button) —
                // this view is reached via a pushed NavigationLink inside ProfileView's sheet,
                // so without an explicit dismiss it stayed on screen showing a now-deleted
                // account's data until the user backed out manually.
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
