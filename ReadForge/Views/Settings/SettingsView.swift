import SwiftUI
import SwiftData
import AVFoundation
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @Environment(\.modelContext) private var modelContext
    @AppStorage("defaultVoiceIdentifier") private var voiceIdentifier: String = ""
    @AppStorage("defaultPlaybackRate") private var playbackRate: Double = 1.0
    @AppStorage("useEnhancedCleanup") private var useEnhancedCleanup: Bool = false
    @AppStorage("offlineOnlyMode") private var offlineOnlyMode: Bool = true
    @State private var cacheUsageMB: Double = 0
    @State private var showingBackup = false
    @State private var showingRestore = false
    @State private var backupExportURL: URL?
    @State private var backupErrorMessage: String?
    /// `exportBackup()`/the file-mover's save step and `handleRestore()` shared a single
    /// hard-coded "Restore Failed" alert title before — a failed *export* (e.g. the backup
    /// couldn't be built, or saving it to the chosen location failed) showed that same title,
    /// which is simply wrong for that path.
    @State private var backupErrorTitle = "Backup Error"

    private let audioCache = AudioCacheService.shared

    /// Grouped by quality so Enhanced/Premium (Apple's higher-fidelity, larger downloadable
    /// voice assets — the practical "neural voice" tier available to third-party apps on iOS;
    /// full custom neural voice cloning is out of MVP scope per CLAUDE.md) sort ahead of the
    /// always-available Standard/compact voices.
    private var voicesByQuality: [(label: String, voices: [AVSpeechSynthesisVoice])] {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let premium = all.filter { $0.quality == .premium }
        let enhanced = all.filter { $0.quality == .enhanced }
        let standard = all.filter { $0.quality == .default }
        return [
            ("Premium", premium),
            ("Enhanced", enhanced),
            ("Standard", standard),
        ].filter { !$0.voices.isEmpty }
    }

    private var hasOnlyStandardVoices: Bool {
        voicesByQuality.count == 1 && voicesByQuality.first?.label == "Standard"
    }

    var body: some View {
        Form {
            Section("Account") {
                if let user = authService.currentUser {
                    LabeledContent("Signed in as", value: user.name?.isEmpty == false ? user.name! : user.email)
                    NavigationLink("Profile") {
                        ProfileView()
                    }
                    Button("Sign Out", role: .destructive) {
                        Task { await authService.signOut() }
                    }
                } else {
                    Text("Not signed in")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Playback") {
                Picker("Voice", selection: $voiceIdentifier) {
                    Text("System Default").tag("")
                    ForEach(voicesByQuality, id: \.label) { group in
                        Section(group.label) {
                            ForEach(group.voices, id: \.identifier) { voice in
                                Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                            }
                        }
                    }
                }
                Picker("Default Speed", selection: $playbackRate) {
                    Text("0.75×").tag(0.75)
                    Text("1×").tag(1.0)
                    Text("1.25×").tag(1.25)
                    Text("1.5×").tag(1.5)
                    Text("2×").tag(2.0)
                }
                if hasOnlyStandardVoices && !offlineOnlyMode {
                    Button("Download Higher-Quality Voices…") {
                        openVoiceSettings()
                    }
                    Text("Enhanced and Premium voices sound more natural. iOS manages their download in Settings › Accessibility › Spoken Content › Voices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if hasOnlyStandardVoices {
                    Text("Higher-quality voices are available, but downloading them needs network access — disabled by Offline-Only Mode in Profile › Privacy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Text Cleanup") {
                Toggle("Enhanced Cleanup", isOn: $useEnhancedCleanup)
                Text("Uses Apple's on-device Foundation Model where available (iOS 26+ with Apple Intelligence enabled), or on-device language analysis otherwise — never the cloud — to better rejoin broken sentences before narration, on top of the standard rule-based cleanup. Applies to documents imported from now on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Backup") {
                Button("Export Backup…") {
                    exportBackup()
                }
                Button("Restore from Backup…") {
                    showingRestore = true
                }
                Text("Creates a file with your library, reading progress, and bookmarks that you can save anywhere you like — iCloud Drive, another cloud provider, AirDrop to another device. Nothing is uploaded automatically; this only happens when you tap Export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Text("All documents and audio stay on your device. Nothing is uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Audio Cache", value: String(format: "%.1f MB", cacheUsageMB))
                Button("Delete Audio Cache", role: .destructive) {
                    deleteAudioCache()
                }
            }

            Section("Diagnostics") {
                NavigationLink("Crash Log") {
                    CrashLogView()
                }
                Text("Crash logs never include your document content, and stay on this device unless you choose to share one yourself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
        .task { await refreshCacheUsage() }
        .fileMover(
            isPresented: Binding(get: { backupExportURL != nil }, set: { if !$0 { backupExportURL = nil } }),
            file: backupExportURL
        ) { result in
            if case .failure(let error) = result {
                backupErrorTitle = "Export Failed"
                backupErrorMessage = error.localizedDescription
            }
            backupExportURL = nil
        }
        .fileImporter(isPresented: $showingRestore, allowedContentTypes: [.zip]) { result in
            handleRestore(result)
        }
        .errorAlert($backupErrorMessage, title: backupErrorTitle)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func deleteAudioCache() {
        Task {
            await audioCache.clearAll()
            await refreshCacheUsage()
        }
    }

    private func refreshCacheUsage() async {
        cacheUsageMB = await audioCache.totalSizeMB()
    }

    private func openVoiceSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func exportBackup() {
        Task {
            do {
                backupExportURL = try await BackupService().exportBackup(context: modelContext)
            } catch {
                backupErrorTitle = "Export Failed"
                backupErrorMessage = error.localizedDescription
            }
        }
    }

    private func handleRestore(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            backupErrorTitle = "Restore Failed"
            backupErrorMessage = error.localizedDescription
        case .success(let url):
            Task {
                do {
                    try await BackupService().importBackup(from: url, context: modelContext)
                } catch {
                    backupErrorTitle = "Restore Failed"
                    backupErrorMessage = error.localizedDescription
                }
            }
        }
    }
}
