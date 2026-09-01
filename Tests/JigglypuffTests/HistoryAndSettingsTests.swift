import XCTest
@testable import Jigglypuff

@MainActor
final class HistoryAndSettingsTests: XCTestCase {

    // MARK: - Settings Store Tests

    func testSettingsStoreDefaultsAndMutations() {
        let settings = SettingsStore.shared
        
        // Test models and modes enum coverage
        for model in TranscribeModel.allCases {
            XCTAssertFalse(model.displayName.isEmpty)
            XCTAssertFalse(model.description.isEmpty)
            settings.selectedModel = model
            XCTAssertEqual(settings.selectedModel, model)
        }

        for mode in DictationMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty)
            XCTAssertFalse(mode.iconName.isEmpty)
            XCTAssertFalse(mode.defaultPrompt.isEmpty)
            settings.selectedDictationMode = mode
            XCTAssertEqual(settings.selectedDictationMode, mode)
        }

        for behavior in HotkeyBehavior.allCases {
            XCTAssertFalse(behavior.displayName.isEmpty)
            settings.hotkeyBehavior = behavior
            XCTAssertEqual(settings.hotkeyBehavior, behavior)
        }

        settings.autoInsertText = true
        XCTAssertTrue(settings.autoInsertText)

        settings.copyToClipboardAlways = true
        XCTAssertTrue(settings.copyToClipboardAlways)

        settings.showFloatingHUD = true
        XCTAssertTrue(settings.showFloatingHUD)

        settings.playSoundEffects = true
        XCTAssertTrue(settings.playSoundEffects)
    }

    func testSettingsStoreCustomPromptAndVocabulary() {
        let settings = SettingsStore.shared
        settings.customVocabulary = "Wispr, Jigglypuff, Anthropic, Gemini"
        XCTAssertEqual(settings.customVocabulary, "Wispr, Jigglypuff, Anthropic, Gemini")

        settings.customPrompt = "Translate English audio directly to French."
        XCTAssertEqual(settings.customPrompt, "Translate English audio directly to French.")
    }

    // MARK: - Keychain Helper Tests

    nonisolated func testKeychainSaveGetDelete() {
        let keychain = KeychainHelper.shared
        let testKey = "test_key_integration_\(UUID().uuidString)"

        // Save
        keychain.saveAPIKey(testKey)
        let retrieved = keychain.getAPIKey()
        XCTAssertEqual(retrieved, testKey)

        // Delete
        keychain.deleteAPIKey()
        let afterDelete = keychain.getAPIKey()
        XCTAssertTrue(afterDelete == nil || afterDelete?.isEmpty == true)
    }

    // MARK: - History Manager Tests

    func testHistoryManagerAddAndClear() {
        let history = HistoryManager.shared
        history.clearAll()
        XCTAssertEqual(history.items.count, 0)

        let item1 = TranscriptionItem(
            text: "First test transcription",
            duration: 3.2,
            model: "Gemini 3.5 Transcribe",
            mode: "Smart Flow",
            targetAppName: "Notes"
        )
        history.add(item: item1)
        XCTAssertEqual(history.items.count, 1)
        XCTAssertEqual(history.items.first?.text, "First test transcription")

        let item2 = TranscriptionItem(
            text: "Second test transcription",
            duration: 1.8,
            model: "Gemini 3.5 Transcribe",
            mode: "Smart Flow",
            targetAppName: "Xcode"
        )
        history.add(item: item2)
        XCTAssertEqual(history.items.count, 2)
        // Most recent should be first
        XCTAssertEqual(history.items.first?.text, "Second test transcription")

        history.clearAll()
        XCTAssertEqual(history.items.count, 0)
    }

    // MARK: - Text Insertion Tests

    func testTextInsertionServiceBehavior() {
        let service = TextInsertionService.shared
        let testString = "Hello from integration test!"

        // Test with autoInsert = false, copyToClipboard = true
        let result = service.insertText(testString, autoInsert: false, copyToClipboardAlways: true)
        XCTAssertEqual(result, .copiedToClipboardOnly)

        // Verify clipboard content
        let clipboardText = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(clipboardText, testString)
    }
}
