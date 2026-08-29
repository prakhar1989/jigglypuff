import Foundation
import AppKit
import ApplicationServices
import Carbon

/// Service responsible for injecting transcribed text directly into the user's active application.
@MainActor
public final class TextInsertionService {
    public static let shared = TextInsertionService()

    private init() {}

    /// Outcome of an insertText call — tells the user where their text actually went.
    public enum InsertionResult: Sendable, Equatable {
        case inserted
        case copiedToClipboardOnly
    }

    /// Inserts text into the currently active application using simulated paste (Cmd+V).
    @discardableResult
    public func insertText(_ text: String, autoInsert: Bool = true, copyToClipboardAlways: Bool = true) -> InsertionResult {
        guard !text.isEmpty else { return .copiedToClipboardOnly }

        let pasteboard = NSPasteboard.general

        // Always copy text to clipboard if configured or if autoInsert is disabled
        if copyToClipboardAlways || !autoInsert {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }

        guard autoInsert else { return .copiedToClipboardOnly }

        // Check if Accessibility permission is granted for CGEvent injection
        if !AXIsProcessTrusted() {
            print("Accessibility not granted. Falling back to clipboard only.")
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copiedToClipboardOnly
        }

        // Save original clipboard if we only want temporary paste
        var previousItems: [NSPasteboardItem] = []
        if !copyToClipboardAlways {
            if let items = pasteboard.pasteboardItems {
                previousItems = items.compactMap { item in
                    let copy = NSPasteboardItem()
                    for type in item.types {
                        if let data = item.data(forType: type) {
                            copy.setData(data, forType: type)
                        }
                    }
                    return copy
                }
            }
        }

        // Put new text onto pasteboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure focused app is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.simulatePaste()

            // If we didn't want to overwrite clipboard permanently, restore original contents after paste completes
            if !copyToClipboardAlways && !previousItems.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    pasteboard.clearContents()
                    pasteboard.writeObjects(previousItems)
                }
            }
        }

        return .inserted
    }

    /// Simulates pressing Command + V using CGEvent
    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 0x09 // 'V' key in US layout

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            print("Failed to create keyboard events.")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
