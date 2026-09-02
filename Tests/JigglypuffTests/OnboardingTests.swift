import XCTest
import SwiftUI
@testable import Jigglypuff

@MainActor
final class OnboardingTests: XCTestCase {

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        SettingsStore.shared.hasCompletedOnboarding = false
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        OnboardingWindowController.shared.dismiss()
    }

    // MARK: - Onboarding State & Persistence

    func testOnboardingStateDefaultsAndMutation() {
        let settings = SettingsStore.shared
        XCTAssertFalse(settings.hasCompletedOnboarding)

        settings.hasCompletedOnboarding = true
        XCTAssertTrue(settings.hasCompletedOnboarding)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"))

        settings.hasCompletedOnboarding = false
        XCTAssertFalse(settings.hasCompletedOnboarding)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"))
    }

    // MARK: - Onboarding Window Controller

    func testOnboardingWindowControllerShowAndDismiss() {
        let controller = OnboardingWindowController.shared

        // Dismiss any existing window
        controller.dismiss()

        // Show window
        controller.show()

        // Repeated show calls should be idempotent
        controller.show()

        // Dismiss
        controller.dismiss()
    }

    // MARK: - Onboarding View Instantiation & Dismissal

    func testOnboardingViewInstantiatesAndDismisses() {
        var didDismiss = false
        let view = OnboardingView(onDismiss: {
            didDismiss = true
        })

        XCTAssertNotNil(view.body)

        view.onDismiss()
        XCTAssertTrue(didDismiss)
    }

    // MARK: - History Preservation Setting

    func testSaveHistorySettingPreventsHistoryLogging() {
        let settings = SettingsStore.shared
        let history = HistoryManager.shared

        history.clearAll()
        XCTAssertEqual(history.items.count, 0)

        // When saveHistory is true, items are stored
        settings.saveHistory = true
        let item1 = TranscriptionItem(
            text: "Preserved item",
            duration: 1.0,
            model: "Gemini 3.5 Transcribe",
            mode: "Smart Flow"
        )
        history.add(item: item1)
        XCTAssertEqual(history.items.count, 1)

        // When saveHistory is false, items are ignored
        settings.saveHistory = false
        let item2 = TranscriptionItem(
            text: "Ignored item",
            duration: 1.0,
            model: "Gemini 3.5 Transcribe",
            mode: "Smart Flow"
        )
        history.add(item: item2)
        XCTAssertEqual(history.items.count, 1)
        XCTAssertEqual(history.items.first?.text, "Preserved item")

        // Cleanup
        settings.saveHistory = true
        history.clearAll()
    }
}
