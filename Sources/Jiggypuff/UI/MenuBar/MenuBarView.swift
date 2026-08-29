import SwiftUI

/// SwiftUI popover menu for the menu bar status item.
public struct MenuBarView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var history = HistoryManager.shared

    var onOpenSettings: () -> Void
    var onOpenHistory: () -> Void
    var onQuit: () -> Void

    public init(onOpenSettings: @escaping () -> Void,
                onOpenHistory: @escaping () -> Void,
                onQuit: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        self.onOpenHistory = onOpenHistory
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Status & Quick Action
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jiggypuff")
                        .font(.headline)
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    appState.toggleRecording()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: appState.state.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 11))
                        Text(appState.state.isRecording ? "Stop" : "Record")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(appState.state.isRecording ? Color.red : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2)

            Divider()

            // Mode Selector
            VStack(alignment: .leading, spacing: 6) {
                Text("Dictation Mode")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(DictationMode.allCases) { mode in
                    Button(action: {
                        settings.selectedDictationMode = mode
                    }) {
                        HStack {
                            Image(systemName: mode.iconName)
                                .frame(width: 18)
                                .foregroundColor(settings.selectedDictationMode == mode ? .accentColor : .secondary)

                            Text(mode.displayName)
                                .font(.system(size: 12))

                            Spacer()

                            if settings.selectedDictationMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(settings.selectedDictationMode == mode ? Color.primary.opacity(0.06) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Recent Transcriptions
            if !history.items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Recent Transcriptions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("View All") {
                            onOpenHistory()
                        }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }

                    ForEach(history.items.prefix(3)) { item in
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.text, forType: .string)
                        }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .foregroundColor(.primary)

                                HStack {
                                    Text(item.mode)
                                    Text("•")
                                    Text(formattedTime(item.timestamp))
                                }
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .help("Click to copy to clipboard")
                    }
                }
                Divider()
            }

            // Bottom Actions
            HStack {
                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onOpenHistory) {
                    Label("History", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onQuit) {
                    Text("Quit")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private var statusSubtitle: String {
        switch appState.state {
        case .idle:
            return "Press ⌥ Space to dictate"
        case .recording(let d):
            return "Recording (\(Int(d))s)..."
        case .transcribing:
            return "Transcribing with Gemini..."
        case .success:
            return "Transcribed successfully"
        case .error(let msg):
            return msg
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
