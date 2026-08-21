import SwiftUI

/// Shows the on-device crash log (see `CrashReportingService`). Viewing and sharing are both
/// explicit user actions — nothing here is sent anywhere automatically.
struct CrashLogView: View {
    @State private var log: String = ""

    var body: some View {
        Group {
            if log.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("No crashes recorded.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(log)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("Crash Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !log.isEmpty {
                ToolbarItemGroup(placement: .primaryAction) {
                    ShareLink(item: log)
                    Button("Clear", role: .destructive) {
                        CrashReportingService.shared.clearLog()
                        log = ""
                    }
                }
            }
        }
        .onAppear {
            log = CrashReportingService.shared.readLog() ?? ""
        }
    }
}
