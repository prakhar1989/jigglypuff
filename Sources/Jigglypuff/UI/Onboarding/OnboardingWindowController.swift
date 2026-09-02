import AppKit
import SwiftUI

/// Window Controller managing the first-launch Onboarding Setup window.
@MainActor
public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    public static let shared = OnboardingWindowController()

    private var window: NSWindow?

    override private init() {
        super.init()
    }

    public func show() {
        if let window = self.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView { [weak self] in
            self?.dismiss()
        }

        let hostingController = NSHostingController(rootView: onboardingView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Welcome to Jigglypuff"
        newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.isReleasedWhenClosed = false
        newWindow.setContentSize(NSSize(width: 520, height: 650))
        newWindow.isMovableByWindowBackground = true
        newWindow.backgroundColor = NSColor(red: 0.992, green: 0.973, blue: 1.0, alpha: 1.0)
        newWindow.center()
        newWindow.delegate = self

        // Clean window buttons: hide miniaturize/zoom
        newWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newWindow.standardWindowButton(.zoomButton)?.isHidden = true

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func dismiss() {
        window?.close()
        window = nil
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
