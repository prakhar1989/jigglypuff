import AppKit
import SwiftUI

/// Custom NSHostingView that prevents automatic window resizing to the pill's content box
/// and allows clicks outside the pill frame to pass through to underlying applications.
private final class HUDHostingView<Content: View>: NSHostingView<Content> {
    var pillFrame: NSRect = .zero

    required init(rootView: Content) {
        super.init(rootView: rootView)
        self.sizingOptions = []
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if pillFrame != .zero {
            let hitArea = pillFrame.insetBy(dx: -6, dy: -6)
            if !hitArea.contains(point) {
                return nil
            }
        }
        return super.hitTest(point)
    }
}

/// Floating, non-activating overlay window displaying the HUD pill across all spaces.
@MainActor
public final class HUDOverlayWindow: NSPanel {
    public static let shared = HUDOverlayWindow()
    private var hudHostingView: HUDHostingView<HUDOverlayView>?

    private static let defaultWidth: CGFloat = 560
    private static let defaultHeight: CGFloat = 120

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.defaultWidth, height: Self.defaultHeight),
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

        let hostingView = HUDHostingView(rootView: HUDOverlayView())
        self.hudHostingView = hostingView
        self.contentView = hostingView
    }

    /// Updates the clickable region to match the pill's active geometry.
    public func updatePillFrame(_ frame: CGRect) {
        hudHostingView?.pillFrame = frame
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

        let windowWidth = Self.defaultWidth
        let windowHeight = Self.defaultHeight

        let x = screenRect.origin.x + (screenRect.width - windowWidth) / 2.0
        let y = screenRect.origin.y + 50 // Centers pill ~70pt above dock/bottom bar

        self.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
    }
}
