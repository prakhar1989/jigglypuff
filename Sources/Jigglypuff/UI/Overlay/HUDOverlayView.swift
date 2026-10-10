import SwiftUI

/// PreferenceKey to report the pill's current layout bounds in window coordinates.
struct PillFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Floating HUD Pill overlay inspired by Wispr Flow.
public struct HUDOverlayView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var permissions = PermissionManager.shared

    @State private var isPulsing = false

    public init() {}

    private var pillShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    /// Only show the live transcript inside the HUD pill when text is NOT already being
    /// auto-typed live into the focused application.
    private var shouldShowLivePreviewInHUD: Bool {
        guard !appState.liveStreamingText.isEmpty else { return false }
        let isAutoTypingIntoApp = settings.autoInsertText && permissions.isAccessibilityGranted
        return !isAutoTypingIntoApp
    }

    public var body: some View {
        HStack(spacing: 12) {
            contentForState()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            pillShape
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                .overlay(
                    pillShape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
        )
        .clipShape(pillShape)
        .overlay(
            // Subtle border
            pillShape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.15),
                            Color.primary.opacity(0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: PillFramePreferenceKey.self,
                    value: geo.frame(in: .global)
                )
            }
        )
        .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .fixedSize(horizontal: false, vertical: true)
        .onPreferenceChange(PillFramePreferenceKey.self) { frame in
            HUDOverlayWindow.shared.updatePillFrame(frame)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.state)
    }

    @ViewBuilder
    private func contentForState() -> some View {
        switch appState.state {
        case .idle:
            EmptyView()

        case .recording(let duration):
            let showLivePreview = shouldShowLivePreviewInHUD
            // Recording State
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    // Pulsing red mic indicator
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.3))
                            .frame(width: 20, height: 20)
                            .scaleEffect(isPulsing ? 1.3 : 0.9)
                            .opacity(isPulsing ? 0.0 : 0.8)

                        Circle()
                            .fill(Color.red)
                            .frame(width: 9, height: 9)
                    }
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }

                    // Live Audio Waveform
                    WaveformView(audioLevel: appState.audioLevel, barCount: 9)

                    // Recording Timer
                    Text(formatDuration(duration))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)

                    // Active Mode Badge
                    HStack(spacing: 4) {
                        Image(systemName: settings.selectedDictationMode.iconName)
                            .font(.system(size: 10))
                        Text(settings.selectedDictationMode.displayName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)

                    if showLivePreview {
                        Spacer(minLength: 8)
                    }

                    // Cancel Button
                    Button(action: {
                        appState.cancelRecording()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 18, height: 18)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if showLivePreview {
                    Text(tailLinesPreview(appState.liveStreamingText))
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundColor(.primary.opacity(0.88))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 340, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .frame(width: showLivePreview ? 340 : nil)

        case .transcribing:
            // Transcribing State
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.85)

                Text(
                    !appState.liveStreamingText.isEmpty
                        ? "Finalizing live transcript..."
                        : "Transcribing with \(settings.selectedModel.rawValue)..."
                )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }

        case .success(let text):
            // Success / Inserted State
            let showSnippetInSuccess = appState.lastInsertionResult == .copiedToClipboardOnly || !settings.enableLiveStreaming
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 15))

                VStack(alignment: .leading, spacing: 2) {
                    if appState.lastInsertionResult == .copiedToClipboardOnly {
                        Text("Copied to clipboard")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                    } else if let app = appState.activeAppName {
                        Text("Inserted into \(app)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                    } else {
                        Text("Transcribed")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                    }

                    if showSnippetInSuccess {
                        Text(text)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 240, alignment: .leading)
                    }
                }
            }

        case .error(let message):
            // Error State
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))

                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340, alignment: .leading)

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Copy error message to clipboard")

                Button(action: {
                    appState.state = .idle
                    HUDOverlayWindow.shared.hide()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Dismiss error")
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Returns a word-aligned trailing window of text so macOS SwiftUI can word-wrap
    /// across 2 lines (since `.truncationMode(.head)` forces single-line layout in AppKit).
    public static func tailLinesPreview(_ text: String, maxCharacters: Int = 96) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        let suffixStart = trimmed.index(trimmed.endIndex, offsetBy: -maxCharacters)
        let rawSuffix = String(trimmed[suffixStart...])
        if let firstSpace = rawSuffix.firstIndex(of: " ") {
            let wordAligned = String(rawSuffix[rawSuffix.index(after: firstSpace)...])
            if !wordAligned.isEmpty {
                return "…" + wordAligned
            }
        }
        return "…" + rawSuffix
    }

    private func tailLinesPreview(_ text: String, maxCharacters: Int = 96) -> String {
        Self.tailLinesPreview(text, maxCharacters: maxCharacters)
    }
}
