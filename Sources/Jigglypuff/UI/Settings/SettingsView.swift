import SwiftUI

/// Main Tabbed Settings View
public struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var permissions = PermissionManager.shared

    @State private var selectedTab: SettingsTab = .general
    @State private var inputDevices: [AudioInputDevice] = AudioRecorder.availableInputDevices()
    @State private var showAPIKey: Bool = false
    @State private var testStatus: String? = nil
    @State private var isTestingAPI: Bool = false

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case model = "Model & API"
        case modes = "Dictation Modes"
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
                .tabItem {
                    Label("General", systemImage: SettingsTab.general.iconName)
                }
                .tag(SettingsTab.general)

            modelTab
                .tabItem {
                    Label("Model & API", systemImage: SettingsTab.model.iconName)
                }
                .tag(SettingsTab.model)

            modesTab
                .tabItem {
                    Label("Modes", systemImage: SettingsTab.modes.iconName)
                }
                .tag(SettingsTab.modes)

            vocabularyTab
                .tabItem {
                    Label("Vocabulary", systemImage: SettingsTab.vocabulary.iconName)
                }
                .tag(SettingsTab.vocabulary)

            permissionsTab
                .tabItem {
                    Label("Permissions", systemImage: SettingsTab.permissions.iconName)
                }
                .tag(SettingsTab.permissions)
        }
        .padding(20)
        .frame(width: 540, height: 480)
        .onAppear {
            inputDevices = AudioRecorder.availableInputDevices()
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section(header: Text("Global Hotkey").font(.headline)) {
                Picker("Trigger Mode", selection: $settings.hotkeyBehavior) {
                    ForEach(HotkeyBehavior.allCases) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }

                HStack {
                    Text("Shortcut:")
                    Spacer()
                    Text("⌥ Space (Option + Space)")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(6)
                        .font(.system(.body, design: .monospaced))
                }
            }

            Section(header: Text("Audio Input").font(.headline)) {
                Picker("Microphone", selection: $settings.audioInputDeviceUID) {
                    Text("System Default").tag("")
                    ForEach(inputDevices) { device in
                        Text(device.isSystemDefault ? "\(device.name) (System Default)" : device.name).tag(device.uid)
                    }
                }

                Text("Which microphone Jigglypuff listens to. Applies when the next recording starts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Behavior & Feedback").font(.headline)) {
                Toggle("Auto-insert transcribed text into focused app", isOn: $settings.autoInsertText)
                Toggle("Always copy transcript to clipboard", isOn: $settings.copyToClipboardAlways)
                Toggle("Show floating HUD pill during recording", isOn: $settings.showFloatingHUD)
                Toggle("Play sound cues (start, stop, success)", isOn: $settings.playSoundEffects)
            }

            Section(header: Text("About").font(.headline)) {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2")")
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("Powered by")
                    Spacer()
                    Text("Google Gemini")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Model & API Tab

    private var modelTab: some View {
        Form {
            Section(header: Text("Gemini API Configuration").font(.headline)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Google AI Studio API Key")
                        .font(.subheadline)

                    HStack {
                        if showAPIKey {
                            TextField("Enter Gemini API Key", text: $settings.apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Enter Gemini API Key", text: $settings.apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        }
                    }

                    HStack {
                        Button("Get API Key from Google AI Studio") {
                            if let url = URL(string: "https://aistudio.google.com/app/apikey") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.link)

                        Spacer()

                        Button(action: testConnection) {
                            if isTestingAPI {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Test Connection")
                            }
                        }
                        .disabled(settings.apiKey.isEmpty || isTestingAPI)
                    }

                    if let status = testStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(status.contains("Success") ? .green : .red)
                    }
                }
            }

            Section(header: Text("Transcription Model").font(.headline)) {
                Picker("Model", selection: $settings.selectedModel) {
                    ForEach(TranscribeModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }

                Text(settings.selectedModel.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Dictation Modes Tab

    private var modesTab: some View {
        Form {
            Section(header: Text("Active Dictation Mode").font(.headline)) {
                Picker("Selected Mode", selection: $settings.selectedDictationMode) {
                    ForEach(DictationMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.iconName).tag(mode)
                    }
                }
            }

            Section(header: Text("Mode Instructions").font(.headline)) {
                if settings.selectedDictationMode == .custom {
                    TextEditor(text: $settings.customPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 140)
                        .border(Color.secondary.opacity(0.2), width: 1)
                } else {
                    ScrollView {
                        Text(settings.selectedDictationMode.defaultPrompt)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                }
            }
        }
    }

    // MARK: - Vocabulary Tab

    private var vocabularyTab: some View {
        Form {
            Section(header: Text("Custom Vocabulary & Jargon").font(.headline)) {
                Text("Add domain-specific jargon, acronyms, company names, or unusual spellings to guide Gemini 3.5 Transcribe.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextEditor(text: $settings.customVocabulary)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 180)
                    .border(Color.secondary.opacity(0.2), width: 1)

                Text("Example: Jigglypuff, Wispr Flow, Kubernetes, PyTorch, SwiftUI, GraphQL")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Permissions Tab

    private var permissionsTab: some View {
        VStack(spacing: 16) {
            // Microphone Permission Card
            HStack {
                Image(systemName: "mic.fill")
                    .font(.system(size: 24))
                    .foregroundColor(permissions.isMicrophoneGranted ? .green : .orange)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Microphone Access")
                        .font(.headline)
                    Text(permissions.isMicrophoneGranted ? "Microphone access is enabled." : "Required for voice recording.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if permissions.isMicrophoneGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Button("Grant Access") {
                        permissions.requestMicrophoneAccess { _ in }
                    }
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)

            // Accessibility Permission Card
            HStack {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 24))
                    .foregroundColor(permissions.isAccessibilityGranted ? .green : .orange)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Accessibility Access")
                        .font(.headline)
                    Text(permissions.isAccessibilityGranted ? "Accessibility access is enabled." : "Required to auto-type text into other applications.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if permissions.isAccessibilityGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Button("Open System Settings") {
                        permissions.requestAccessibilityAccess()
                        permissions.openAccessibilitySettings()
                    }
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)

            Spacer()
        }
    }

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
                DispatchQueue.main.async {
                    self.isTestingAPI = false
                    self.testStatus = "✓ Success! Gemini API connected."
                }
            } catch {
                DispatchQueue.main.async {
                    self.isTestingAPI = false
                    self.testStatus = "✗ Error: \(error.localizedDescription)"
                }
            }
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
