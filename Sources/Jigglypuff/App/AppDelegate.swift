import AppKit
import AVFoundation
import ApplicationServices
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

        print("Jigglypuff initialized successfully.")

        // Present onboarding window on first run
        if !SettingsStore.shared.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                OnboardingWindowController.shared.show()
            }
        } else if ProcessInfo.processInfo.environment["JP_DEBUG_OPEN_ONBOARDING"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                OnboardingWindowController.shared.show()
            }
        }

        // Diagnostics hook: writes current permission statuses to a temp file so
        // scripts can verify TCC state without UI scripting.
        if ProcessInfo.processInfo.environment["JP_DEBUG_PERMISSIONS"] == "1" {
            let diagPath = "/tmp/jigglypuff_perm_diag.txt"
            func reportPermissionStatus(_ when: String) {
                let micRaw = AVCaptureDevice.authorizationStatus(for: .audio).rawValue
                let line = "[diag \(when)] axGranted=\(AXIsProcessTrusted()) micRaw=\(micRaw)\n"
                if let data = line.data(using: .utf8) {
                    if let fh = FileHandle(forWritingAtPath: diagPath) { fh.seekToEndOfFile(); fh.write(data); try? fh.close() }
                    else { try? data.write(to: URL(fileURLWithPath: diagPath)) }
                }
            }
            try? Data().write(to: URL(fileURLWithPath: diagPath))
            reportPermissionStatus("launch")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                reportPermissionStatus("t+5s")
            }
        }

        // Automation hook: opens Settings shortly after launch so UI tests and
        // diagnostic scripts can verify the window without UI scripting. Shows
        // and closes the popover first, mirroring the real user path (the
        // popover is where the Settings entry point lives).
        if ProcessInfo.processInfo.environment["JP_DEBUG_OPEN_SETTINGS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                MenuBarController.shared.showPopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MenuBarController.shared.closePopoverForAutomation()
                    MenuBarController.shared.openSettings()
                }
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
    }
}
