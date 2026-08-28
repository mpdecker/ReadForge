import SwiftUI

/// Renders one or more sections to a single audio file and lets the user save/share it
/// (CLAUDE.md v2.0: "audio export"). See `AudioExportService` for why this always synthesizes
/// fresh rather than reusing cached per-sentence clips.
struct AudioExportView: View {
    let title: String
    let sections: [(title: String, text: String)]

    @Environment(\.dismiss) private var dismiss
    @State private var progress: Double = 0
    @State private var isExporting = true
    @State private var exportedURL: URL?
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                if isExporting {
                    ProgressView(value: progress)
                        .padding(.horizontal, 32)
                    Text("Rendering audio… \(Int(progress * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.green)
                    Text("Ready to save or share.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Export Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await runExport() }
            .fileMover(
                isPresented: Binding(
                    get: { exportedURL != nil },
                    set: { isPresented in
                        if !isPresented {
                            // Whether the move succeeded (the file's already gone from this
                            // path — a harmless no-op here), failed, or the user simply
                            // cancelled the picker (whose completion handler below isn't called
                            // at all in that case), the temp export file must never be left
                            // behind once this sheet closes. Previously only a *successful* move
                            // cleaned it up, so a cancelled or failed save leaked the full-size
                            // temp file every time.
                            if let url = exportedURL {
                                try? FileManager.default.removeItem(at: url)
                            }
                            exportedURL = nil
                        }
                    }
                ),
                file: exportedURL
            ) { result in
                if case .failure(let error) = result {
                    errorMessage = error.localizedDescription
                }
                dismiss()
            }
            .errorAlert($errorMessage, title: "Export Failed")
        }
    }

    private func runExport() async {
        let (voiceId, rate) = PlaybackController.defaultVoiceAndRate()
        do {
            let url = try await AudioExportService().export(sections: sections, voiceId: voiceId, rate: rate) { done, total in
                Task { @MainActor in progress = Double(done) / Double(total) }
            }
            isExporting = false
            exportedURL = url
        } catch {
            // Previously this branch left `isExporting` stuck at `true` forever — the error
            // alert would show, but underneath it the view kept rendering an indeterminate
            // "Rendering audio…" progress view with no way back except manually tapping Close.
            isExporting = false
            errorMessage = error.localizedDescription
        }
    }
}
