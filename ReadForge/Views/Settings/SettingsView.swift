import SwiftUI
import AVFoundation

struct SettingsView: View {
    @AppStorage("defaultVoiceIdentifier") private var voiceIdentifier: String = ""
    @AppStorage("defaultPlaybackRate") private var playbackRate: Double = 1.0

    private var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
    }

    var body: some View {
        Form {
            Section("Playback") {
                Picker("Voice", selection: $voiceIdentifier) {
                    Text("System Default").tag("")
                    ForEach(voices, id: \.identifier) { voice in
                        Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                    }
                }
                Picker("Default Speed", selection: $playbackRate) {
                    Text("0.75×").tag(0.75)
                    Text("1×").tag(1.0)
                    Text("1.25×").tag(1.25)
                    Text("1.5×").tag(1.5)
                    Text("2×").tag(2.0)
                }
            }

            Section("Privacy") {
                Text("All documents and audio stay on your device. Nothing is uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Delete Audio Cache", role: .destructive) {
                    deleteAudioCache()
                }
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func deleteAudioCache() {
        // Audio cache directory (reserved for Phase 11 pre-generated audio)
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let dir = cacheDir?.appendingPathComponent("AudioCache") else { return }
        try? FileManager.default.removeItem(at: dir)
    }
}
