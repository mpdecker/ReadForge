import SwiftUI
import SwiftData

@main
struct ReadForgeApp: App {
    @State private var performanceCoordinator = SimplePerformanceCoordinator()
    @Environment(\.scenePhase) private var scenePhase
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
                for: DocumentRecord.self, SectionRecord.self, BookmarkRecord.self, PlaybackState.self, User.self,
                configurations: ModelConfiguration(
                    isStoredInMemoryOnly: UITestSupport.isEnabled(UITestSupport.inMemoryStoreArgument)
                )
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        modelContainer = container

        let auth = AuthenticationService(modelContext: container.mainContext)
        #if DEBUG
        if UITestSupport.isEnabled(UITestSupport.seedLibraryArgument) {
            UITestSupport.seedLibrary(in: container.mainContext)
        }
        if UITestSupport.isEnabled(UITestSupport.bypassAuthArgument) {
            auth.signInForUITesting(as: UITestSupport.makeTestUser(in: container.mainContext))
        }
        #endif
        _authService = StateObject(wrappedValue: auth)
    }

    var body: some Scene {
        WindowGroup {
            AuthenticationEntryView()
                .environmentObject(authService)
                .onAppear {
                    performanceCoordinator.startMonitoring()
                    PlaybackController.configureAudioSessionCategoryAtLaunch()
                    AppLogger.didLaunch()
                }
                .onDisappear {
                    performanceCoordinator.stopMonitoring()
                    AppLogger.willTerminate()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        authService.lock()
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
