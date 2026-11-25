import SwiftUI

@main
struct BrunelloApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .fontDesign(.rounded)
                .tint(Theme.brand)
        }
    }
}
