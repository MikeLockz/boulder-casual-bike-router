import SwiftUI
import SwiftData

@main
struct BoulderBikeRouterApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(for: [LocalRoute.self, LocalNavigationTick.self])
    }
}
