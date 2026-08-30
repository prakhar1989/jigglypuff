import Foundation
import SwiftUI
import Combine
import AppKit

/// Dictation state machine
public enum DictationState: Equatable, Sendable {
    case idle
    case recording(duration: TimeInterval)
    case transcribing
    case success(text: String)
    case error(message: String)

    public var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    public var isBusy: Bool {
        switch self {
        case .recording, .transcribing:
            return true
        default:
            return false
        }
    }
}

/// Central App State Controller
@MainActor
public final class AppState: ObservableObject, HotkeyManagerDelegate {
    public static let shared = AppState()

    @Published public var state: DictationState = .idle
    @Published public var audioLevel: Float = 0.0
    @Published public var currentDuration: TimeInterval = 0.0
    @Published public var lastTranscribedText: String = ""
    @Published public var lastInsertionResult: TextInsertionService.InsertionResult = .inserted
    @Published public var activeAppName: String? = nil

    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var dismissTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Bind audio level from recorder
        AudioRecorder.shared.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.audioLevel = level
            }
            .store(in: &cancellables)

        // Setup hotkey manager
        HotkeyManager.shared.delegate = self
        HotkeyManager.shared.register(
            keyCode: SettingsStore.shared.hotkeyKeyCode,
            modifiers: SettingsStore.shared.hotkeyModifiers
        )
    }

    // MARK: - Hotkey Delegate

    public func hotkeyPressed() {
        let behavior = SettingsStore.shared.hotkeyBehavior
        switch behavior {
        case .pushToTalk:
            if state == .idle {
                startRecording()
            }
        case .toggle:
            toggleRecording()
        }
    }

    public func hotkeyReleased() {
        let behavior = SettingsStore.shared.hotkeyBehavior
        if behavior == .pushToTalk && state.isRecording {
            stopRecording()
        }
    }

    // MARK: - Actions

    public func toggleRecording() {
        if state.isRecording {
            stopRecording()
        } else if state == .idle {
            startRecording()
        }
    }

    public func startRecording() {
        guard state == .idle else { return }
        dismissTimer?.invalidate()

        // Capture frontmost application before showing our UI
        self.activeAppName = NSWorkspace.shared.frontmostApplication?.localizedName

        // Check permissions
        if !PermissionManager.shared.isMicrophoneGranted {
            PermissionManager.shared.requestMicrophoneAccess { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.startRecording()
                    } else {
                        self?.state = .error(message: "Microphone access required.")
                        SoundEffects.shared.playError()
                        self?.scheduleAutoDismiss(after: 3.0)
                    }
                }
            }
            return
        }

        do {
            try AudioRecorder.shared.startRecording()
            SoundEffects.shared.playStart()

            let start = Date()
            self.recordingStartTime = start
            self.currentDuration = 0.0
            self.state = .recording(duration: 0.0)

            durationTimer?.invalidate()
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, let startTime = self.recordingStartTime else { return }
                    let elapsed = Date().timeIntervalSince(startTime)
                    self.currentDuration = elapsed
                    self.state = .recording(duration: elapsed)
                }
            }

            HUDOverlayWindow.shared.show()
        } catch {
            self.state = .error(message: error.localizedDescription)
            SoundEffects.shared.playError()
            scheduleAutoDismiss(after: 3.0)
        }
    }

    public func stopRecording() {
        guard state.isRecording else { return }

        durationTimer?.invalidate()
        durationTimer = nil

        SoundEffects.shared.playStop()
        let recordedDuration = currentDuration
        let audioData = AudioRecorder.shared.stopRecording()

        self.state = .transcribing

        Task {
            do {
                let settings = SettingsStore.shared
                let transcribed = try await GeminiTranscribeService.shared.transcribe(
                    audioData: audioData,
                    model: settings.selectedModel,
                    mode: settings.selectedDictationMode,
                    customPrompt: settings.customPrompt,
                    customVocabulary: settings.customVocabulary
                )

                guard !transcribed.isEmpty else {
                    SoundEffects.shared.playError()
                    self.state = .error(message: "No speech detected. Please try again.")
                    self.scheduleAutoDismiss(after: 2.5)
                    return
                }

                self.lastTranscribedText = transcribed

                // Auto-type into target application
                self.lastInsertionResult = TextInsertionService.shared.insertText(
                    transcribed,
                    autoInsert: settings.autoInsertText,
                    copyToClipboardAlways: settings.copyToClipboardAlways
                )

                // Log to history
                let item = TranscriptionItem(
                    text: transcribed,
                    duration: recordedDuration,
                    model: settings.selectedModel.displayName,
                    mode: settings.selectedDictationMode.displayName,
                    targetAppName: self.activeAppName
                )
                HistoryManager.shared.add(item: item)

                SoundEffects.shared.playSuccess()
                self.state = .success(text: transcribed)
                self.scheduleAutoDismiss(after: 1.8)
            } catch {
                SoundEffects.shared.playError()
                self.state = .error(message: error.localizedDescription)
                self.scheduleAutoDismiss(after: 5.0)
            }
        }
    }

    public func cancelRecording() {
        durationTimer?.invalidate()
        durationTimer = nil
        AudioRecorder.shared.cancelRecording()
        self.state = .idle
        HUDOverlayWindow.shared.hide()
    }

    private func scheduleAutoDismiss(after delay: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.state = .idle
                HUDOverlayWindow.shared.hide()
            }
        }
    }
}
