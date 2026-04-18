import SwiftUI

@main
struct SnorOhApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No default window — everything is managed via NSPanel in AppDelegate.
        // SwiftUI requires at least one scene, so we use a Settings placeholder.
        Settings {
            EmptyView()
        }
    }
}
