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
    public func insertText(_ text: String, autoInsert: Bool = true, copyToClipboardAlways: Bool = false) -> InsertionResult {
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

    // MARK: - Live Streaming Incremental Typing & Self-Correction

    /// Computes the minimal Backspace count and replacement suffix needed to transform `oldText` into `newText`
    /// based on their longest common Character prefix.
    nonisolated public static func reconcileDiff(from oldText: String, to newText: String) -> (backspaces: Int, suffixToType: String) {
        let oldChars = Array(oldText)
        let newChars = Array(newText)
        let minLen = min(oldChars.count, newChars.count)
        var commonPrefixLen = 0

        while commonPrefixLen < minLen && oldChars[commonPrefixLen] == newChars[commonPrefixLen] {
            commonPrefixLen += 1
        }

        let backspaces = oldChars.count - commonPrefixLen
        let suffix = String(newChars[commonPrefixLen...])
        return (backspaces: backspaces, suffixToType: suffix)
    }

    /// Applies an incremental diff to the active application using Backspace key events followed by direct Unicode keystrokes.
    public func applyDiff(backspaces: Int, suffixToType: String) {
        guard AXIsProcessTrusted() else { return }
        if backspaces > 0 {
            sendBackspaces(backspaces)
        }
        if !suffixToType.isEmpty {
            typeUnicodeString(suffixToType)
        }
    }

    /// Sends `count` Backspace (`kVK_Delete` = 0x33) key events with empty modifier flags so held Push-To-Talk modifiers do not interfere.
    public func sendBackspaces(_ count: Int) {
        guard count > 0, AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .privateState)
        let deleteKeyCode: CGKeyCode = 0x33 // kVK_Delete (Backspace)

        for _ in 0..<count {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: deleteKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: deleteKeyCode, keyDown: false) else {
                continue
            }
            keyDown.flags = []
            keyUp.flags = []
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// Directly types a Unicode string character-by-character via `CGEvent.keyboardSetUnicodeString` without touching `NSPasteboard`.
    public func typeUnicodeString(_ text: String) {
        guard !text.isEmpty, AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .privateState)

        for character in text {
            var utf16Units = Array(String(character).utf16)
            guard !utf16Units.isEmpty,
                  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            keyDown.flags = []
            keyUp.flags = []
            keyDown.keyboardSetUnicodeString(stringLength: utf16Units.count, unicodeString: &utf16Units)
            keyUp.keyboardSetUnicodeString(stringLength: utf16Units.count, unicodeString: &utf16Units)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}

/// Manages incremental in-place typing and self-correction across utterances during a single live dictation session.
@MainActor
public final class StreamingTextSession {
    /// All finalized utterance transcripts committed so far in this session.
    public private(set) var committedText: String = ""

    /// The currently typed speculative (`interim`) transcript for the active utterance.
    public private(set) var currentInterimText: String = ""

    /// The combined text currently visible to the user (`committedText + currentInterimText`).
    public var displayText: String {
        committedText + currentInterimText
    }

    /// Whether any text (interim or final) has been received in this session.
    public var hasReceivedText: Bool {
        !committedText.isEmpty || !currentInterimText.isEmpty
    }

    private let diffInjector: (Int, String) -> Void

    public init(diffInjector: ((Int, String) -> Void)? = nil) {
        self.diffInjector = diffInjector ?? { backspaces, suffix in
            TextInsertionService.shared.applyDiff(backspaces: backspaces, suffixToType: suffix)
        }
    }

    /// Updates the speculative transcript for the current utterance, backspacing any revised trailing characters and typing new ones.
    public func updateInterim(_ rawText: String, autoInsert: Bool) {
        let formatted = formatSegment(rawText)
        guard !formatted.isEmpty else { return }

        let diff = TextInsertionService.reconcileDiff(from: currentInterimText, to: formatted)
        if autoInsert && (diff.backspaces > 0 || !diff.suffixToType.isEmpty) {
            diffInjector(diff.backspaces, diff.suffixToType)
        }
        currentInterimText = formatted
    }

    /// Commits a finalized utterance transcript, reconciling against any previously typed speculative characters for the utterance.
    public func commitFinal(_ rawText: String, autoInsert: Bool) {
        let formatted = formatSegment(rawText)
        guard !formatted.isEmpty else { return }

        let diff = TextInsertionService.reconcileDiff(from: currentInterimText, to: formatted)
        if autoInsert && (diff.backspaces > 0 || !diff.suffixToType.isEmpty) {
            diffInjector(diff.backspaces, diff.suffixToType)
        }
        committedText += formatted
        currentInterimText = ""
    }

    /// Finalizes the session on recording stop, committing any remaining unfinalized interim text and updating the clipboard if needed.
    public func finalizeSession(
        autoInsert: Bool,
        copyToClipboardAlways: Bool
    ) -> (fullText: String, insertionResult: TextInsertionService.InsertionResult) {
        if !currentInterimText.isEmpty {
            committedText += currentInterimText
            currentInterimText = ""
        }

        let fullText = committedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fullText.isEmpty else {
            return ("", .copiedToClipboardOnly)
        }

        let isTrusted = AXIsProcessTrusted()
        if copyToClipboardAlways || !autoInsert || !isTrusted {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(fullText, forType: .string)
        }

        let result: TextInsertionService.InsertionResult = (autoInsert && isTrusted) ? .inserted : .copiedToClipboardOnly
        return (fullText, result)
    }

    private func formatSegment(_ rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if committedText.isEmpty {
            return trimmed
        }

        // Add a separating space between finalized utterances unless committedText already ends with whitespace
        // or the new segment starts with common closing/attaching punctuation.
        if let lastChar = committedText.last, lastChar.isWhitespace {
            return trimmed
        }
        if let firstChar = trimmed.first, [Character("."), ",", "!", "?", ":", ";"].contains(firstChar) {
            return trimmed
        }
        return " " + trimmed
    }
}

