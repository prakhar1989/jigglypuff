import SwiftUI
import AppKit

/// Main Settings window, shown in a native Settings scene window with toolbar tabs.
public struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var permissions = PermissionManager.shared
    @ObservedObject var inputDeviceManager = AudioInputDeviceManager.shared

    @State private var selectedTab: SettingsTab = .general
    @State private var showAPIKey: Bool = false
    @State private var testStatus: String? = nil
    @State private var isTestingAPI: Bool = false
    @State private var newVocabularyTerm: String = ""

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case model = "Model & API"
        case modes = "Modes"
        case vocabulary = "Vocabulary"
        case permissions = "Permissions"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .general: return "gearshape"
            case .model: return "sparkles"
            case .modes: return "wand.and.stars"
            case .vocabulary: return "text.book.closed"
            case .permissions: return "hand.raised"
            }
        }
    }

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label(SettingsTab.general.rawValue, systemImage: SettingsTab.general.iconName) }
                .tag(SettingsTab.general)

            modelTab
                .tabItem { Label(SettingsTab.model.rawValue, systemImage: SettingsTab.model.iconName) }
                .tag(SettingsTab.model)

            modesTab
                .tabItem { Label(SettingsTab.modes.rawValue, systemImage: SettingsTab.modes.iconName) }
                .tag(SettingsTab.modes)

            vocabularyTab
                .tabItem { Label(SettingsTab.vocabulary.rawValue, systemImage: SettingsTab.vocabulary.iconName) }
                .tag(SettingsTab.vocabulary)

            permissionsTab
                .tabItem { Label(SettingsTab.permissions.rawValue, systemImage: SettingsTab.permissions.iconName) }
                .tag(SettingsTab.permissions)
        }
        .onAppear {
            inputDeviceManager.refresh()
            migrateSelectionMetadataIfNeeded()
        }
    }

    /// A grouped, System Settings-style form with a consistent window width.
    private func groupedForm<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Form(content: content)
            .formStyle(.grouped)
            .frame(width: 520)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        groupedForm {
            Section {
                Picker("Trigger Mode", selection: $settings.hotkeyBehavior) {
                    ForEach(HotkeyBehavior.allCases) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }

                LabeledContent("Shortcut") {
                    HStack(spacing: 5) {
                        KeyCap("⌥ Option")
                        Text("+")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        KeyCap("Space")
                    }
                }
            } header: {
                Text("Global Hotkey")
            } footer: {
                Text(settings.hotkeyBehavior.explanation)
            }

            Section {
                Picker("Microphone", selection: $settings.audioInputDeviceSelection) {
                    Text("System Default").tag(AudioInputDeviceSelection.systemDefault)

                    if !settings.audioInputDeviceSelection.isSystemDefault,
                       !inputDeviceManager.devices.contains(where: { $0.identity == settings.audioInputDeviceSelection }) {
                        Text("\(settings.audioInputDeviceSelection.name ?? "Selected Microphone") (Unavailable — using System Default)")
                            .tag(settings.audioInputDeviceSelection)
                    }

                    ForEach(inputDeviceManager.devices) { device in
                        Text(device.isSystemDefault ? "\(device.name) (System Default)" : device.name)
                            .tag(device.identity)
                    }
                }
            } header: {
                Text("Audio Input")
            } footer: {
                Text("Which microphone Jigglypuff listens to. Applies when the next recording starts.")
            }

            Section {
                Toggle("Auto-insert transcript into focused app", isOn: $settings.autoInsertText)
                    .toggleStyle(.switch)
                Toggle("Always copy transcript to clipboard", isOn: $settings.copyToClipboardAlways)
                    .toggleStyle(.switch)
                Toggle("Show floating HUD while recording", isOn: $settings.showFloatingHUD)
                    .toggleStyle(.switch)
                Toggle("Play sound cues (start, stop, success)", isOn: $settings.playSoundEffects)
                    .toggleStyle(.switch)
            } header: {
                Text("Behavior & Feedback")
            }

            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Jigglypuff")
                            .font(.headline)
                        Text("Voice dictation for macOS, powered by Gemini.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Link("GitHub", destination: URL(string: "https://github.com/prakhar1989/jigglypuff")!)
                        .font(.callout)
                }

                LabeledContent("Version") {
                    Text("v\(appVersion)")
                        .foregroundColor(.secondary)
                        .font(.system(.callout, design: .monospaced))
                }

                LabeledContent("Powered by") {
                    Text("Google Gemini")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("About")
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2"
    }

    private func migrateSelectionMetadataIfNeeded() {
        guard let uid = settings.audioInputDeviceSelection.uid,
              let currentDevice = inputDeviceManager.devices.first(where: { $0.uid == uid }) else {
            return
        }

        if settings.audioInputDeviceSelection != currentDevice.identity {
            settings.audioInputDeviceSelection = currentDevice.identity
        }
    }

    // MARK: - Model & API Tab

    private var modelTab: some View {
        groupedForm {
            Section {
                HStack(spacing: 8) {
                    Group {
                        if showAPIKey {
                            TextField("Gemini API Key", text: $settings.apiKey)
                        } else {
                            SecureField("Gemini API Key", text: $settings.apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button(action: { showAPIKey.toggle() }) {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                    .help(showAPIKey ? "Hide API Key" : "Show API Key")
                }

                HStack {
                    Link("Get an API Key from Google AI Studio",
                         destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                        .font(.callout)

                    Spacer()

                    Button(action: testConnection) {
                        Text("Test Connection")
                    }
                    .disabled(settings.apiKey.isEmpty || isTestingAPI)
                }

                if isTestingAPI {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Testing connection…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let status = testStatus {
                    HStack(spacing: 4) {
                        Image(systemName: status.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill")
                        Text(status)
                    }
                    .font(.caption)
                    .foregroundColor(status.contains("Success") ? .green : .red)
                }
            } header: {
                Text("Gemini API")
            } footer: {
                Text("Your API key is stored securely in the macOS Keychain.")
            }

            Section {
                Picker("Model", selection: $settings.selectedModel) {
                    ForEach(TranscribeModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
            } header: {
                Text("Transcription Model")
            } footer: {
                Text(settings.selectedModel.description)
            }
        }
    }

    // MARK: - Modes Tab

    private var modesTab: some View {
        groupedForm {
            Section {
                ForEach(DictationMode.allCases) { mode in
                    Button(action: { settings.selectedDictationMode = mode }) {
                        HStack(spacing: 10) {
                            Image(systemName: mode.iconName)
                                .frame(width: 20)
                                .foregroundColor(settings.selectedDictationMode == mode ? .accentColor : .secondary)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(mode.displayName)
                                Text(mode.summary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if settings.selectedDictationMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Dictation Mode")
            } footer: {
                Text("How your speech is turned into text. You can also switch modes anytime from the menu bar popover.")
            }

            if settings.selectedDictationMode == .custom {
                Section {
                    TextEditor(text: $settings.customPrompt)
                        .font(.body)
                        .frame(height: 130)
                        .accessibilityLabel("Custom prompt")
                } header: {
                    Text("Custom Prompt")
                } footer: {
                    Text("Instructions sent to Gemini along with your audio.")
                }
            } else {
                Section {
                    DisclosureGroup("System Prompt") {
                        Text(settings.selectedDictationMode.defaultPrompt)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } header: {
                    Text("Mode Instructions")
                }
            }
        }
    }

    // MARK: - Vocabulary Tab

    private var vocabularyTerms: [String] {
        settings.customVocabulary
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func termBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { index < vocabularyTerms.count ? vocabularyTerms[index] : "" },
            set: { newValue in
                var terms = vocabularyTerms
                guard terms.indices.contains(index) else { return }
                terms[index] = newValue.trimmingCharacters(in: .whitespaces)
                settings.customVocabulary = terms.joined(separator: "\n")
            }
        )
    }

    private func addVocabularyTerm() {
        let term = newVocabularyTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        var terms = vocabularyTerms
        terms.append(term)
        settings.customVocabulary = terms.joined(separator: "\n")
        newVocabularyTerm = ""
    }

    private func removeVocabularyTerm(at index: Int) {
        var terms = vocabularyTerms
        guard terms.indices.contains(index) else { return }
        terms.remove(at: index)
        settings.customVocabulary = terms.joined(separator: "\n")
    }

    private var vocabularyTab: some View {
        groupedForm {
            Section {
                if vocabularyTerms.isEmpty {
                    Text("No custom terms yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ForEach(vocabularyTerms.indices, id: \.self) { index in
                    HStack(spacing: 6) {
                        TextField("Term", text: termBinding(at: index))
                            .textFieldStyle(.roundedBorder)

                        Button(action: { removeVocabularyTerm(at: index) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove term")
                    }
                }

                HStack(spacing: 6) {
                    TextField("Add a term…", text: $newVocabularyTerm)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addVocabularyTerm)

                    Button(action: addVocabularyTerm) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(newVocabularyTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Add term")
                }
            } header: {
                Text("Custom Vocabulary & Jargon")
            } footer: {
                Text("Domain-specific jargon, acronyms, company names, or unusual spellings that guide transcription. Example: Jigglypuff, Kubernetes, PyTorch, SwiftUI.")
            }
        }
    }

    // MARK: - Permissions Tab

    private var permissionsTab: some View {
        groupedForm {
            permissionSection(
                iconName: "mic.fill",
                title: "Microphone Access",
                detail: "Required to record your voice.",
                granted: permissions.isMicrophoneGranted,
                actionLabel: "Grant Access",
                action: { permissions.requestMicrophoneAccess { _ in } }
            )

            permissionSection(
                iconName: "hand.raised.fill",
                title: "Accessibility Access",
                detail: "Required to auto-type text into other applications.",
                granted: permissions.isAccessibilityGranted,
                actionLabel: "Open System Settings",
                action: {
                    permissions.requestAccessibilityAccess()
                    permissions.openAccessibilitySettings()
                },
                footer: "If Jigglypuff is already toggled on in System Settings but not detected, the entry is stale: remove it from the list (− button), then re-add /Applications/Jigglypuff.app and toggle it on."
            )
        }
    }

    private func permissionSection(iconName: String,
                                   title: String,
                                   detail: String,
                                   granted: Bool,
                                   actionLabel: String,
                                   action: @escaping () -> Void,
                                   footer: String? = nil) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 20))
                    .foregroundColor(granted ? .green : .orange)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if granted {
                    Label("Enabled", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundColor(.green)
                } else {
                    Button(actionLabel, action: action)
                }
            }
        } footer: {
            if let footer {
                Text(footer)
            }
        }
    }

    // MARK: - API Test

    private func testConnection() {
        isTestingAPI = true
        testStatus = nil

        Task {
            // Create a minimal 0.5s silence WAV buffer
            let dummyWav = createDummyTestWAV()
            do {
                _ = try await GeminiTranscribeService.shared.transcribe(
                    audioData: dummyWav,
                    model: settings.selectedModel,
                    mode: .smartFlow
                )
                testStatus = "✓ Success! Gemini API connected."
            } catch {
                testStatus = "✗ Error: \(error.localizedDescription)"
            }
            isTestingAPI = false
        }
    }

    private func createDummyTestWAV() -> Data {
        let sampleRate = 16000
        let numSamples = 8000 // 0.5 sec
        let pcmData = Data(count: numSamples * 2) // zeroed PCM
        var wavData = Data()
        wavData.append("RIFF".data(using: .ascii)!)
        var chunkSize = UInt32(36 + pcmData.count).littleEndian
        wavData.append(Data(bytes: &chunkSize, count: 4))
        wavData.append("WAVEfmt ".data(using: .ascii)!)
        var sub1 = UInt32(16).littleEndian
        wavData.append(Data(bytes: &sub1, count: 4))
        var format = UInt16(1).littleEndian
        wavData.append(Data(bytes: &format, count: 2))
        var channels = UInt16(1).littleEndian
        wavData.append(Data(bytes: &channels, count: 2))
        var sRate = UInt32(sampleRate).littleEndian
        wavData.append(Data(bytes: &sRate, count: 4))
        var byteRate = UInt32(sampleRate * 2).littleEndian
        wavData.append(Data(bytes: &byteRate, count: 4))
        var align = UInt16(2).littleEndian
        wavData.append(Data(bytes: &align, count: 2))
        var bits = UInt16(16).littleEndian
        wavData.append(Data(bytes: &bits, count: 2))
        wavData.append("data".data(using: .ascii)!)
        var sub2 = UInt32(pcmData.count).littleEndian
        wavData.append(Data(bytes: &sub2, count: 4))
        wavData.append(pcmData)
        return wavData
    }
}

/// A small keyboard key-cap badge.
private struct KeyCap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.primary.opacity(0.12))
            )
    }
}
