import ETFMomentumCore
import SwiftUI

@main
struct ETFMomentumApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1180, minHeight: 760)
                .task {
                    if store.snapshot == nil {
                        await store.refresh()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
