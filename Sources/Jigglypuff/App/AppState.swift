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
    @Published public var liveStreamingText: String = ""

    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var dismissTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var liveSession: GeminiLiveTranscribeSession?
    private var streamingTextSession: StreamingTextSession?
    private var liveEventStreamTask: Task<Void, Never>?
    private var liveSessionErrorMessage: String?

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
            if !state.isBusy {
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
        } else if !state.isBusy {
            startRecording()
        }
    }

    public func startRecording() {
        guard !state.isRecording else { return }
        dismissTimer?.invalidate()
        dismissTimer = nil

        // Capture frontmost application before showing our UI
        self.activeAppName = NSWorkspace.shared.frontmostApplication?.localizedName

        // Check permissions
        if !PermissionManager.shared.isMicrophoneGranted {
            PermissionManager.shared.requestMicrophoneAccess { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.startRecording()
                    } else {
                        self?.state = .error(message: "Microphone access required. Please enable it in Settings.")
                        SoundEffects.shared.playError()
                        self?.scheduleAutoDismiss(after: 4.5)
                    }
                }
            }
            return
        }

        self.liveStreamingText = ""
        self.liveSessionErrorMessage = nil
        self.liveEventStreamTask?.cancel()
        self.liveEventStreamTask = nil
        self.liveSession = nil
        self.streamingTextSession = nil

        let settings = SettingsStore.shared
        let shouldStreamLive = settings.enableLiveStreaming || settings.selectedModel == .gemini35TranscribeLive

        if shouldStreamLive,
           let apiKey = KeychainHelper.shared.getAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !apiKey.isEmpty {
            let textSession = StreamingTextSession()
            self.streamingTextSession = textSession

            let session = GeminiLiveTranscribeSession(
                apiKey: apiKey,
                mode: settings.selectedDictationMode,
                customVocabulary: settings.customVocabulary
            )
            self.liveSession = session
            self.liveEventStreamTask = Task { [weak self] in
                do {
                    let stream = try await session.start()
                    for try await event in stream {
                        await MainActor.run {
                            self?.handleLiveTranscriptEvent(event, textSession: textSession)
                        }
                    }
                } catch {
                    await MainActor.run {
                        print("Jigglypuff: Live transcription WebSocket error: \(error.localizedDescription)")
                        self?.liveSessionErrorMessage = error.localizedDescription
                    }
                }
            }
        }

        do {
            if let session = self.liveSession {
                try AudioRecorder.shared.startRecording { chunk in
                    Task {
                        await session.sendAudioChunk(chunk)
                    }
                }
            } else {
                try AudioRecorder.shared.startRecording()
            }
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
            self.liveEventStreamTask?.cancel()
            self.liveEventStreamTask = nil
            if let activeSession = self.liveSession {
                self.liveSession = nil
                self.streamingTextSession = nil
                Task { await activeSession.close() }
            }
            self.state = .error(message: "Audio error: \(error.localizedDescription)")
            SoundEffects.shared.playError()
            scheduleAutoDismiss(after: 4.5)
        }
    }

    public func stopRecording() {
        guard state.isRecording else { return }

        durationTimer?.invalidate()
        durationTimer = nil

        SoundEffects.shared.playStop()
        let recordedDuration = currentDuration
        let audioData = AudioRecorder.shared.stopRecording()
        print("Jigglypuff: Recording finished (\(String(format: "%.1f", recordedDuration))s). Captured WAV payload: \(audioData.count) bytes.")

        let activeLiveSession = self.liveSession
        let activeTextSession = self.streamingTextSession
        let activeEventTask = self.liveEventStreamTask
        self.liveSession = nil
        self.streamingTextSession = nil
        self.liveEventStreamTask = nil

        self.state = .transcribing

        Task {
            let settings = SettingsStore.shared

            if let liveSession = activeLiveSession, let textSession = activeTextSession {
                await liveSession.finishAudioStream(timeoutSeconds: 2.5)
                if let eventTask = activeEventTask {
                    _ = await eventTask.result
                }

                let (streamedText, insertionResult) = textSession.finalizeSession(
                    autoInsert: settings.autoInsertText,
                    copyToClipboardAlways: settings.copyToClipboardAlways
                )
                self.liveStreamingText = ""

                if !streamedText.isEmpty {
                    print("Jigglypuff: Live streamed result length: \(streamedText.count) characters: '\(streamedText)'")
                    self.lastTranscribedText = streamedText
                    self.lastInsertionResult = insertionResult

                    if settings.saveHistory {
                        let item = TranscriptionItem(
                            text: streamedText,
                            duration: recordedDuration,
                            model: TranscribeModel.gemini35TranscribeLive.displayName,
                            mode: settings.selectedDictationMode.displayName,
                            targetAppName: self.activeAppName
                        )
                        HistoryManager.shared.add(item: item)
                    }

                    SoundEffects.shared.playSuccess()
                    self.state = .success(text: streamedText)
                    self.scheduleAutoDismiss(after: 1.8)
                    return
                }

                print("Jigglypuff: Live session ended with no streamed text; falling back to batch transcription.")
            }

            do {
                let transcribed = try await GeminiTranscribeService.shared.transcribe(
                    audioData: audioData,
                    model: settings.selectedModel,
                    mode: settings.selectedDictationMode,
                    customPrompt: settings.customPrompt,
                    customVocabulary: settings.customVocabulary
                )

                print("Jigglypuff: Transcribed result length: \(transcribed.count) characters: '\(transcribed)'")

                guard !transcribed.isEmpty else {
                    SoundEffects.shared.playError()
                    self.state = .error(message: "No speech recognized in audio. Please try speaking closer to the microphone.")
                    self.scheduleAutoDismiss(after: 4.5)
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
                if settings.saveHistory {
                    let item = TranscriptionItem(
                        text: transcribed,
                        duration: recordedDuration,
                        model: settings.selectedModel.displayName,
                        mode: settings.selectedDictationMode.displayName,
                        targetAppName: self.activeAppName
                    )
                    HistoryManager.shared.add(item: item)
                }

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
        self.liveEventStreamTask?.cancel()
        self.liveEventStreamTask = nil
        if let activeLiveSession = self.liveSession {
            self.liveSession = nil
            self.streamingTextSession = nil
            Task {
                await activeLiveSession.close()
            }
        }
        self.liveStreamingText = ""
        AudioRecorder.shared.cancelRecording()
        self.state = .idle
        HUDOverlayWindow.shared.hide()
    }

    private func handleLiveTranscriptEvent(_ event: LiveTranscriptEvent, textSession: StreamingTextSession) {
        let autoInsert = SettingsStore.shared.autoInsertText

        switch event {
        case .setupComplete:
            print("Jigglypuff: Live transcription WebSocket setupComplete.")
        case .interim(let text):
            textSession.updateInterim(text, autoInsert: autoInsert)
            self.liveStreamingText = textSession.displayText
        case .final(let text):
            textSession.commitFinal(text, autoInsert: autoInsert)
            self.liveStreamingText = textSession.displayText
        case .turnComplete:
            break
        }
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
