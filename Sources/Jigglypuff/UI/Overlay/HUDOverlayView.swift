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

    @State private var isPulsing = false

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            contentForState()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            // Subtle glowing border
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
        .frame(minWidth: 180, maxWidth: 460)
        .fixedSize(horizontal: true, vertical: true)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: PillFramePreferenceKey.self,
                    value: geo.frame(in: .global)
                )
            }
        )
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
            // Recording State
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

        case .transcribing:
            // Transcribing State
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.85)

                Text("Transcribing with \(settings.selectedModel.rawValue)...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }

        case .success(let text):
            // Success / Inserted State
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

                    Text(text)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 240, alignment: .leading)
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
}
