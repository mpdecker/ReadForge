import Foundation

/// On-device crash logging (CLAUDE.md Beta milestone: "crash reporting (no doc content)").
///
/// Scope note: a hosted crash service (Crashlytics, Sentry, etc.) uploads crash data to a server
/// automatically — that needs a third-party account this session can't create, and it cuts
/// against CLAUDE.md's "no cloud processing by default" / "optional cloud sync is explicit
/// opt-in only" privacy rules regardless. So this captures crashes locally instead: nothing
/// leaves the device unless the user explicitly views and shares the log themselves (Settings ›
/// Crash Log). For App Store builds, Apple already collects crash reports automatically with
/// zero code required, visible to the developer in App Store Connect / Xcode Organizer — that's
/// the zero-setup baseline this complements rather than replaces, and it *does* include raw
/// signal crashes (SIGSEGV, SIGABRT, ...); this class doesn't need to duplicate that coverage.
///
/// Scope note on signals: an earlier version of this also installed handlers for SIGABRT/SIGILL/
/// SIGSEGV/SIGFPE/SIGBUS via `signal(3)`. That was removed — a signal handler is only reliable
/// if it's async-signal-safe (raw `write(2)` to a pre-opened file descriptor, no allocation, no
/// GCD, no Swift string interpolation), and this one was none of those things: it built a
/// `String` via interpolation, called into `DispatchQueue.sync`, and touched `FileHandle` — all
/// undefined behavior from inside a real signal handler, and in practice more likely to hang or
/// crash-within-a-crash than to reliably log anything. It also turned out to be actively
/// dangerous during unit testing: because these are process-wide handlers and tests run inside
/// the full app process, any real crash during a test run would take the handler's `exit(_:)`
/// path instead of letting XCTest report one clean test failure, cascading into every other test
/// in that process reporting as "crashed with signal trap" even though only one of them actually
/// failed — which happened for real and corrupted an entire suite run this session. Catching
/// `NSException` (below) doesn't share either problem: it's the standard, safe mechanism most
/// crash reporters rely on for Swift/Obj-C level crashes, and Apple's own automatic collection
/// already has the low-level signal case covered.
final class CrashReportingService: @unchecked Sendable {
    static let shared = CrashReportingService()

    private let logURL: URL
    private let queue = DispatchQueue(label: "app.readforge.crashlog")

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        // Application Support isn't guaranteed to exist yet on a fresh install — this runs
        // before any document has ever been imported (DocumentImportService.sandboxURL() is
        // the only other thing that touches this directory, and it always creates it first).
        // Without this, `record(...)`'s `FileHandle`/atomic-write fallback would both fail
        // silently (swallowed by `try?`), so the very first crash on a fresh install would
        // never get logged at all — exactly the case crash reporting exists for.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logURL = dir.appendingPathComponent("CrashLog.txt")
    }

    /// Installs the uncaught-exception handler. Call once, at launch.
    ///
    /// Skipped entirely under a test host: unit tests run inside the full app process
    /// (`ReadForgeApp.init()` executes as part of the host app launching), so this is a
    /// process-wide handler — installing it during a test run isn't the same kind of hazard the
    /// removed signal handlers were (an uncaught `NSException` propagating out of a test is
    /// already treated as that test's failure either way), but there's no reason to run it
    /// somewhere it can't do anything useful, so it stays off for consistency.
    func start() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        NSSetUncaughtExceptionHandler { exception in
            CrashReportingService.shared.record(
                reason: exception.name.rawValue,
                details: exception.reason ?? "",
                stack: exception.callStackSymbols.joined(separator: "\n")
            )
        }
    }

    private func record(reason: String, details: String, stack: String) {
        let entry = """
        ---
        Date: \(ISO8601DateFormatter().string(from: Date()))
        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
        Reason: \(reason)
        Details: \(details)
        Stack:
        \(stack)

        """
        queue.sync {
            if let data = entry.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    try? entry.write(to: logURL, atomically: true, encoding: .utf8)
                }
            }
        }
    }

    // MARK: - Public read access (for the Settings "Crash Log" screen)

    func readLog() -> String? {
        try? String(contentsOf: logURL, encoding: .utf8)
    }

    func hasLog() -> Bool {
        FileManager.default.fileExists(atPath: logURL.path)
    }

    func clearLog() {
        try? FileManager.default.removeItem(at: logURL)
    }
}
