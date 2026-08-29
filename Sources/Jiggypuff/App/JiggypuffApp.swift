import SwiftUI

/// Main application entry point for Jiggypuff
@main
struct JiggypuffApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
