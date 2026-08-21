import SwiftUI
import SwiftData

@main
struct ReadForgeApp: App {
    @State private var performanceCoordinator = SimplePerformanceCoordinator()
    let modelContainer: ModelContainer
    @StateObject private var authService: AuthenticationService

    init() {
        // Installed first, before anything else can crash.
        CrashReportingService.shared.start()

        // Built explicitly (rather than via the `.modelContainer(for:)` scene modifier) so the
        // same container's context can back a single, shared `AuthenticationService` — every
        // auth view consumes that one instance via `@EnvironmentObject` rather than each
        // constructing its own, which is what silently broke sign-in/sign-up before.
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: DocumentRecord.self, SectionRecord.self, BookmarkRecord.self, PlaybackState.self, User.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        modelContainer = container
        _authService = StateObject(wrappedValue: AuthenticationService(modelContext: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            AuthenticationEntryView()
                .environmentObject(authService)
                .onAppear {
                    performanceCoordinator.startMonitoring()
                    AppLogger.didLaunch()
                }
                .onDisappear {
                    performanceCoordinator.stopMonitoring()
                    AppLogger.willTerminate()
                }
        }
        .modelContainer(modelContainer)
    }
}
