import ETFMomentumCore
import SwiftUI

@main
struct ETFMomentumApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minHeight: 760)
                .task {
                    if store.snapshot == nil {
                        _ = await store.refresh()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentSize)
    }
}
