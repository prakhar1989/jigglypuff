import SwiftUI

/// Animated audio waveform visualizer bars responding to microphone audio input level.
public struct WaveformView: View {
    var audioLevel: Float // 0.0 to 1.0
    var barCount: Int = 9

    @State private var phase: Double = 0

    public init(audioLevel: Float, barCount: Int = 9) {
        self.audioLevel = audioLevel
        self.barCount = barCount
    }

    public var body: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveBar(index: index, totalCount: barCount, level: audioLevel)
            }
        }
        .frame(height: 24)
    }
}

private struct WaveBar: View {
    let index: Int
    let totalCount: Int
    let level: Float

    var body: some View {
        let center = Double(totalCount - 1) / 2.0
        let distFromCenter = abs(Double(index) - center) / center
        // Center bars have highest dynamic amplitude; outer bars have lower amplitude
        let shapeFactor = max(0.35, 1.0 - (distFromCenter * 0.55))

        // Dynamic height computation:
        // When level == 0 (ambient room noise/silence), resting height is 3.0px.
        // When speech is detected (level > 0), height scales up to 24px.
        let baseHeight: CGFloat = 3.0
        let isVoiceActive = level > 0.01
        let variableHeight: CGFloat = CGFloat(level) * 21.0 * CGFloat(shapeFactor)
        let finalHeight = max(baseHeight, min(24.0, baseHeight + variableHeight))

        RoundedRectangle(cornerRadius: 1.5)
            .fill(
                LinearGradient(
                    colors: isVoiceActive ? [
                        Color(red: 0.26, green: 0.52, blue: 0.96), // Gemini Blue
                        Color(red: 0.65, green: 0.35, blue: 0.98), // Purple
                        Color(red: 0.95, green: 0.35, blue: 0.65)  // Pink Accent
                    ] : [
                        Color.secondary.opacity(0.35),
                        Color.secondary.opacity(0.35)
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 3.5, height: finalHeight)
            .opacity(isVoiceActive ? 1.0 : 0.45)
            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.65), value: finalHeight)
            .animation(.easeInOut(duration: 0.2), value: isVoiceActive)
    }
}
