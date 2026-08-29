import AppKit
import SwiftUI
import Combine

/// Manages the NSStatusItem in the macOS Menu Bar.
@MainActor
public final class MenuBarController: NSObject {
    public static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private var settingsWindowController: NSWindowController?
    private var historyWindowController: NSWindowController?

    override private init() {
        super.init()
    }

    public func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = item

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Jiggypuff")
            button.imagePosition = .imageLeft
            button.target = self
            button.action = #selector(togglePopover)
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 420)
        popover.behavior = .transient

        let contentView = MenuBarView(
            onOpenSettings: { [weak self] in
                self?.closePopover()
                self?.openSettings()
            },
            onOpenHistory: { [weak self] in
                self?.closePopover()
                self?.openHistory()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )

        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover

        // Observe app state to update menu bar icon
        AppState.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateStatusIcon(for: state)
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon(for state: DictationState) {
        guard let button = statusItem?.button else { return }

        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Jiggypuff")
            button.title = ""
        case .recording:
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")?
                .withSymbolConfiguration(config)
            button.title = " REC"
        case .transcribing:
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemBlue])
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Transcribing")?
                .withSymbolConfiguration(config)
            button.title = " ..."
        case .success:
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
            button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Done")?
                .withSymbolConfiguration(config)
            button.title = ""
        case .error:
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            button.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "Error")?
                .withSymbolConfiguration(config)
            button.title = ""
        }
    }

    @objc private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }

        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
    }

    public func openSettings() {
        if let controller = settingsWindowController, let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Jiggypuff Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 540, height: 480))
        window.center()
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        self.settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func openHistory() {
        if let controller = historyWindowController, let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let historyView = HistoryView()
        let hostingController = NSHostingController(rootView: historyView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Dictation History"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 500))
        window.center()
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        self.historyWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
