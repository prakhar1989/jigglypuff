import Foundation
import SwiftUI
import Combine

/// Stable, persisted identity for a user-selected audio input device.
///
/// The Core Audio device UID is preferred. Model/manufacturer/name metadata lets
/// the app recover when a driver assigns a new UID after a device is reconnected.
public struct AudioInputDeviceSelection: Codable, Hashable, Sendable {
    public let uid: String?
    public let modelUID: String?
    public let manufacturer: String?
    public let name: String?

    public static let systemDefault = AudioInputDeviceSelection()

    public init(uid: String? = nil,
                modelUID: String? = nil,
                manufacturer: String? = nil,
                name: String? = nil) {
        self.uid = uid
        self.modelUID = modelUID
        self.manufacturer = manufacturer
        self.name = name
    }

    public var isSystemDefault: Bool {
        uid == nil && modelUID == nil && manufacturer == nil && name == nil
    }
}

/// Supported Gemini transcription models
public enum TranscribeModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case gemini35Transcribe = "gemini-3.5-transcribe"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gemini35Transcribe:
            return "Gemini 3.5 Transcribe (Recommended)"
        }
    }

    public var description: String {
        switch self {
        case .gemini35Transcribe:
            return "Google's dedicated speech-to-text model with native smart self-correction, disfluency cleanup, and custom vocabulary support (Interactions API)."
        }
    }
}

/// Dictation mode / tone preset
public enum DictationMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case smartFlow = "smart_flow"
    case rawVerbatim = "raw_verbatim"
    case email = "email"
    case bulletPoints = "bullet_points"
    case codeTech = "code_tech"
    case custom = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .smartFlow:
            return "Smart Flow"
        case .rawVerbatim:
            return "Raw Verbatim"
        case .email:
            return "Email / Professional"
        case .bulletPoints:
            return "Bullet Points / Notes"
        case .codeTech:
            return "Code & Technical"
        case .custom:
            return "Custom Prompt"
        }
    }

    public var summary: String {
        switch self {
        case .smartFlow:
            return "Clean up fillers and self-corrections automatically"
        case .rawVerbatim:
            return "Exactly what you said, word for word"
        case .email:
            return "Polished, professional email or message"
        case .bulletPoints:
            return "Concise bullet points and action items"
        case .codeTech:
            return "Technical dictation with code-aware formatting"
        case .custom:
            return "Your own instructions for the transcript"
        }
    }

    public var iconName: String {
        switch self {
        case .smartFlow:
            return "wand.and.stars"
        case .rawVerbatim:
            return "quote.bubble"
        case .email:
            return "envelope"
        case .bulletPoints:
            return "list.bullet"
        case .codeTech:
            return "chevron.left.forwardslash.chevron.right"
        case .custom:
            return "slider.horizontal.3"
        }
    }

    public var defaultPrompt: String {
        switch self {
        case .smartFlow:
            return """
            You are an intelligent transcription engine. Transcribe the spoken audio accurately into clean, well-formatted text.
            - Automatically correct speech disfluencies, hesitations, and self-corrections (e.g. if the speaker says "tomorrow at 2... actually 3", write "tomorrow at 3").
            - Remove filler words like "um", "uh", "ah", "like", "you know".
            - Use proper capitalization, punctuation, numbers, and natural paragraph breaks.
            - Output ONLY the final transcribed text without any quotes, preambles, or explanations.
            """
        case .rawVerbatim:
            return """
            Transcribe the provided audio verbatim, preserving the speaker's exact words including filler words and exact phrasing without rewriting.
            Output ONLY the verbatim text.
            """
        case .email:
            return """
            Transcribe the spoken audio and format it as a polished, professional email or message.
            - Clean up rambling and fix grammatical errors while keeping the core message and tone.
            - Include appropriate greeting and sign-off if implied by the speaker.
            - Output ONLY the polished message text.
            """
        case .bulletPoints:
            return """
            Transcribe the spoken audio and summarize it into clear, concise bullet points and actionable items.
            - Use markdown bullet points (- Item).
            - Output ONLY the formatted bullet points.
            """
        case .codeTech:
            return """
            Transcribe technical dictation for a software engineer.
            - Recognize programming terms, variable names (format as camelCase or snake_case where appropriate), API names, terminal commands, and file paths.
            - Format code snippets in markdown backticks.
            - Output ONLY the transcribed technical text.
            """
        case .custom:
            return """
            Transcribe the audio accurately. Output only the transcribed text.
            """
        }
    }
}

/// Hotkey trigger mode
public enum HotkeyBehavior: String, CaseIterable, Identifiable, Codable, Sendable {
    case pushToTalk = "push_to_talk"
    case toggle = "toggle"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pushToTalk:
            return "Push to Talk"
        case .toggle:
            return "Toggle"
        }
    }

    public var explanation: String {
        switch self {
        case .pushToTalk:
            return "Hold the shortcut to record, release to insert the transcript."
        case .toggle:
            return "Press the shortcut to start recording, press again to stop."
        }
    }
}

/// Global App Settings Store
@MainActor
public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    private static let recommendedDefaultsMigrationVersion = 1

    @Published public var apiKey: String {
        didSet {
            KeychainHelper.shared.saveAPIKey(apiKey)
        }
    }

    @Published public var selectedModel: TranscribeModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "selectedModel")
        }
    }

    @Published public var selectedDictationMode: DictationMode {
        didSet {
            UserDefaults.standard.set(selectedDictationMode.rawValue, forKey: "selectedDictationMode")
        }
    }

    @Published public var customPrompt: String {
        didSet {
            UserDefaults.standard.set(customPrompt, forKey: "customPrompt")
        }
    }

    @Published public var customVocabulary: String {
        didSet {
            UserDefaults.standard.set(customVocabulary, forKey: "customVocabulary")
        }
    }

    @Published public var hotkeyBehavior: HotkeyBehavior {
        didSet {
            UserDefaults.standard.set(hotkeyBehavior.rawValue, forKey: "hotkeyBehavior")
        }
    }

    @Published public var playSoundEffects: Bool {
        didSet {
            UserDefaults.standard.set(playSoundEffects, forKey: "playSoundEffects")
        }
    }

    @Published public var autoInsertText: Bool {
        didSet {
            UserDefaults.standard.set(autoInsertText, forKey: "autoInsertText")
        }
    }

    @Published public var copyToClipboardAlways: Bool {
        didSet {
            UserDefaults.standard.set(copyToClipboardAlways, forKey: "copyToClipboardAlways")
        }
    }

    @Published public var saveHistory: Bool {
        didSet {
            UserDefaults.standard.set(saveHistory, forKey: "saveHistory")
        }
    }

    @Published public var hotkeyKeyCode: UInt32 {
        didSet {
            UserDefaults.standard.set(hotkeyKeyCode, forKey: "hotkeyKeyCode")
        }
    }

    @Published public var hotkeyModifiers: UInt32 {
        didSet {
            UserDefaults.standard.set(hotkeyModifiers, forKey: "hotkeyModifiers")
        }
    }

    @Published public var showFloatingHUD: Bool {
        didSet {
            UserDefaults.standard.set(showFloatingHUD, forKey: "showFloatingHUD")
        }
    }

    /// Persisted identity of the selected Core Audio input device.
    @Published public var audioInputDeviceSelection: AudioInputDeviceSelection {
        didSet {
            persistAudioInputDeviceSelection()
        }
    }

    /// Backward-compatible UID access; an empty string means System Default.
    public var audioInputDeviceUID: String {
        get { audioInputDeviceSelection.uid ?? "" }
        set {
            if newValue.isEmpty {
                audioInputDeviceSelection = .systemDefault
            } else {
                audioInputDeviceSelection = AudioInputDeviceSelection(
                    uid: newValue,
                    modelUID: audioInputDeviceSelection.modelUID,
                    manufacturer: audioInputDeviceSelection.manufacturer,
                    name: audioInputDeviceSelection.name
                )
            }
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        let shouldApplyRecommendedDefaults = defaults.integer(forKey: "recommendedDefaultsMigrationVersion") < Self.recommendedDefaultsMigrationVersion

        self.apiKey = KeychainHelper.shared.getAPIKey() ?? ""

        let modelRaw = UserDefaults.standard.string(forKey: "selectedModel") ?? TranscribeModel.gemini35Transcribe.rawValue
        self.selectedModel = TranscribeModel(rawValue: modelRaw) ?? .gemini35Transcribe

        let modeRaw = shouldApplyRecommendedDefaults
            ? DictationMode.smartFlow.rawValue
            : defaults.string(forKey: "selectedDictationMode") ?? DictationMode.smartFlow.rawValue
        self.selectedDictationMode = DictationMode(rawValue: modeRaw) ?? .smartFlow

        self.customPrompt = UserDefaults.standard.string(forKey: "customPrompt") ?? DictationMode.custom.defaultPrompt
        self.customVocabulary = UserDefaults.standard.string(forKey: "customVocabulary") ?? ""

        let hotkeyRaw = shouldApplyRecommendedDefaults
            ? HotkeyBehavior.pushToTalk.rawValue
            : defaults.string(forKey: "hotkeyBehavior") ?? HotkeyBehavior.pushToTalk.rawValue
        self.hotkeyBehavior = HotkeyBehavior(rawValue: hotkeyRaw) ?? .pushToTalk

        self.playSoundEffects = defaults.object(forKey: "playSoundEffects") as? Bool ?? true
        self.autoInsertText = defaults.object(forKey: "autoInsertText") as? Bool ?? true
        self.copyToClipboardAlways = shouldApplyRecommendedDefaults
            ? false
            : defaults.object(forKey: "copyToClipboardAlways") as? Bool ?? false
        self.saveHistory = defaults.object(forKey: "saveHistory") as? Bool ?? true
        self.showFloatingHUD = defaults.object(forKey: "showFloatingHUD") as? Bool ?? true
        if let data = UserDefaults.standard.data(forKey: "audioInputDeviceSelection"),
           let selection = try? JSONDecoder().decode(AudioInputDeviceSelection.self, from: data) {
            self.audioInputDeviceSelection = selection
        } else {
            // Migrate the original UID-only preference. The richer identity is
            // refreshed the next time the user selects a currently available device.
            let legacyUID = UserDefaults.standard.string(forKey: "audioInputDeviceUID") ?? ""
            self.audioInputDeviceSelection = legacyUID.isEmpty
                ? .systemDefault
                : AudioInputDeviceSelection(uid: legacyUID)
        }

        // Default shortcut: Option + Space (keyCode 49, optionKey 0x0800)
        self.hotkeyKeyCode = UInt32(UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int ?? 49) // 49 = Space
        self.hotkeyModifiers = UInt32(UserDefaults.standard.object(forKey: "hotkeyModifiers") as? Int ?? 0x0800) // optionKey

        if shouldApplyRecommendedDefaults {
            defaults.set(Self.recommendedDefaultsMigrationVersion, forKey: "recommendedDefaultsMigrationVersion")
            defaults.set(self.selectedDictationMode.rawValue, forKey: "selectedDictationMode")
            defaults.set(self.hotkeyBehavior.rawValue, forKey: "hotkeyBehavior")
            defaults.set(self.copyToClipboardAlways, forKey: "copyToClipboardAlways")
        }

        persistAudioInputDeviceSelection()
    }

    private func persistAudioInputDeviceSelection() {
        if let data = try? JSONEncoder().encode(audioInputDeviceSelection) {
            UserDefaults.standard.set(data, forKey: "audioInputDeviceSelection")
        }
        // Keep the legacy key synchronized for compatibility with older builds.
        UserDefaults.standard.set(audioInputDeviceSelection.uid ?? "", forKey: "audioInputDeviceUID")
    }

    /// Returns prompt instructions for the currently selected dictation mode.
    public func promptForCurrentMode() -> String {
        if selectedDictationMode == .custom {
            return customPrompt
        }
        return selectedDictationMode.defaultPrompt
    }
}
