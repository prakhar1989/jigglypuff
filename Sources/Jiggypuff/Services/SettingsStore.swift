import Foundation
import SwiftUI
import Combine

/// Supported Gemini transcription models
public enum TranscribeModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case gemini35Transcribe = "gemini-3.5-transcribe"
    case gemini25Flash = "gemini-2.5-flash"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gemini35Transcribe:
            return "Gemini 3.5 Transcribe (Recommended)"
        case .gemini25Flash:
            return "Gemini 2.5 Flash"
        }
    }

    public var description: String {
        switch self {
        case .gemini35Transcribe:
            return "Google's dedicated speech-to-text model with native smart self-correction, disfluency cleanup, and custom vocabulary support (Interactions API)."
        case .gemini25Flash:
            return "Fast multimodal model transcribing via generateContent. Required for the rewriting dictation modes (Email, Bullet Points, Code, Custom)."
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
            return "Push to Talk (Hold key to record, release to type)"
        case .toggle:
            return "Toggle (Press to start, press again to stop)"
        }
    }
}

/// Global App Settings Store
@MainActor
public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

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

    /// UID of the selected CoreAudio input device; empty string means "use the system default input".
    @Published public var audioInputDeviceUID: String {
        didSet {
            UserDefaults.standard.set(audioInputDeviceUID, forKey: "audioInputDeviceUID")
        }
    }

    private init() {
        self.apiKey = KeychainHelper.shared.getAPIKey() ?? ""

        let modelRaw = UserDefaults.standard.string(forKey: "selectedModel") ?? TranscribeModel.gemini35Transcribe.rawValue
        self.selectedModel = TranscribeModel(rawValue: modelRaw) ?? .gemini35Transcribe

        let modeRaw = UserDefaults.standard.string(forKey: "selectedDictationMode") ?? DictationMode.smartFlow.rawValue
        self.selectedDictationMode = DictationMode(rawValue: modeRaw) ?? .smartFlow

        self.customPrompt = UserDefaults.standard.string(forKey: "customPrompt") ?? DictationMode.custom.defaultPrompt
        self.customVocabulary = UserDefaults.standard.string(forKey: "customVocabulary") ?? ""

        let hotkeyRaw = UserDefaults.standard.string(forKey: "hotkeyBehavior") ?? HotkeyBehavior.toggle.rawValue
        self.hotkeyBehavior = HotkeyBehavior(rawValue: hotkeyRaw) ?? .toggle

        self.playSoundEffects = UserDefaults.standard.object(forKey: "playSoundEffects") as? Bool ?? true
        self.autoInsertText = UserDefaults.standard.object(forKey: "autoInsertText") as? Bool ?? true
        self.copyToClipboardAlways = UserDefaults.standard.object(forKey: "copyToClipboardAlways") as? Bool ?? true
        self.showFloatingHUD = UserDefaults.standard.object(forKey: "showFloatingHUD") as? Bool ?? true
        self.audioInputDeviceUID = UserDefaults.standard.string(forKey: "audioInputDeviceUID") ?? ""

        // Default shortcut: Option + Space (keyCode 49, optionKey 0x0800)
        self.hotkeyKeyCode = UInt32(UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int ?? 49) // 49 = Space
        self.hotkeyModifiers = UInt32(UserDefaults.standard.object(forKey: "hotkeyModifiers") as? Int ?? 0x0800) // optionKey
    }

    /// Returns prompt instructions for the currently selected dictation mode.
    public func promptForCurrentMode() -> String {
        if selectedDictationMode == .custom {
            return customPrompt
        }
        return selectedDictationMode.defaultPrompt
    }
}
