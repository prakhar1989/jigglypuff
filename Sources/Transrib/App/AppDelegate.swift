import AppKit
import SwiftUI

/// Application delegate managing background lifecycle and menu bar status item.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app runs as an agent / menu bar app without dock icon if LSUIElement is active
        NSApp.setActivationPolicy(.accessory)

        // Setup Menu Bar controller
        MenuBarController.shared.setup()

        // Check permissions on startup
        PermissionManager.shared.checkPermissions()

        // Pre-warm audio and hotkey systems
        _ = AppState.shared

        print("Transrib initialized successfully.")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
    }
}
