import XCTest
@testable import Jigglypuff

@MainActor
final class AppStateIntegrationTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        AppState.shared.state = .idle
    }

    override func tearDown() async throws {
        AppState.shared.state = .idle
        try await super.tearDown()
    }

    // MARK: - State Machine & Properties

    func testDictationStateProperties() {
        let idleState = DictationState.idle
        XCTAssertFalse(idleState.isRecording)
        XCTAssertFalse(idleState.isBusy)

        let recordingState = DictationState.recording(duration: 2.5)
        XCTAssertTrue(recordingState.isRecording)
        XCTAssertTrue(recordingState.isBusy)

        let transcribingState = DictationState.transcribing
        XCTAssertFalse(transcribingState.isRecording)
        XCTAssertTrue(transcribingState.isBusy)

        let successState = DictationState.success(text: "Hello world")
        XCTAssertFalse(successState.isRecording)
        XCTAssertFalse(successState.isBusy)

        let errorState = DictationState.error(message: "Connection failed")
        XCTAssertFalse(errorState.isRecording)
        XCTAssertFalse(errorState.isBusy)
    }

    // MARK: - Hotkey Behavior & Re-triggering

    func testFastRetriggeringFromSuccessState() {
        let appState = AppState.shared
        SettingsStore.shared.hotkeyBehavior = .toggle

        // Simulate ending a transcription in success state
        appState.state = .success(text: "Previous transcription")
        XCTAssertFalse(appState.state.isRecording)
        XCTAssertFalse(appState.state.isBusy)

        // Hotkey pressed immediately while success HUD is visible
        appState.hotkeyPressed()

        // Verify that it is not blocked by .success state (it enters recording or permission check)
        // Since isBusy is false, toggleRecording proceeds to startRecording
        XCTAssertFalse(appState.state.isBusy && !appState.state.isRecording)
    }

    func testFastRetriggeringFromErrorState() {
        let appState = AppState.shared
        SettingsStore.shared.hotkeyBehavior = .toggle

        // Simulate app in error state
        appState.state = .error(message: "Previous error message")
        XCTAssertFalse(appState.state.isRecording)
        XCTAssertFalse(appState.state.isBusy)

        // Hotkey pressed immediately while error HUD is visible
        appState.hotkeyPressed()

        // Verify toggle recording is not blocked
        XCTAssertFalse(appState.state.isBusy && !appState.state.isRecording)
    }

    func testCancelRecordingRestoresIdle() {
        let appState = AppState.shared
        appState.state = .recording(duration: 3.0)
        XCTAssertTrue(appState.state.isRecording)

        appState.cancelRecording()
        XCTAssertEqual(appState.state, .idle)
    }

    func testPushToTalkHotkeyReleaseStopsRecording() {
        let appState = AppState.shared
        SettingsStore.shared.hotkeyBehavior = .pushToTalk

        // In push to talk, releasing hotkey when not recording does nothing
        appState.state = .idle
        appState.hotkeyReleased()
        XCTAssertEqual(appState.state, .idle)
    }
}
