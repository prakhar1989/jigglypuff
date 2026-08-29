import AppKit
import SwiftUI

/// Floating, non-activating overlay window displaying the HUD pill across all spaces.
@MainActor
public final class HUDOverlayWindow: NSPanel {
    public static let shared = HUDOverlayWindow()

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovableByWindowBackground = true
        self.ignoresMouseEvents = false

        let hostingView = NSHostingView(rootView: HUDOverlayView())
        self.contentView = hostingView
    }

    /// Shows the HUD overlay smoothly
    public func show() {
        guard SettingsStore.shared.showFloatingHUD else { return }
        updatePosition()
        self.alphaValue = 0.0
        self.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().alphaValue = 1.0
        }
    }

    /// Hides the HUD overlay smoothly
    public func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }

    /// Positions HUD pill near the bottom center of the active screen
    private func updatePosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenRect = screen.visibleFrame

        let windowWidth: CGFloat = 360
        let windowHeight: CGFloat = 60

        let x = screenRect.origin.x + (screenRect.width - windowWidth) / 2.0
        let y = screenRect.origin.y + 70 // Above dock/bottom bar

        self.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
    }
}
