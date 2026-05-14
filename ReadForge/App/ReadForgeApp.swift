import SwiftUI
import SwiftData

@main
struct ReadForgeApp: App {
    @State private var performanceCoordinator = SimplePerformanceCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    performanceCoordinator.startMonitoring()
                    AppLogger.didLaunch()
                }
                .onDisappear {
                    performanceCoordinator.stopMonitoring()
                    AppLogger.willTerminate()
                }
        }
        .modelContainer(for: [DocumentRecord.self, SectionRecord.self, BookmarkRecord.self, PlaybackState.self])
    }
}
