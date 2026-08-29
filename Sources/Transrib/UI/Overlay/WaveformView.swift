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
        let factor = max(0.2, 1.0 - (distFromCenter * 0.5))

        // Dynamic height computation
        let baseHeight: CGFloat = 4.0
        let variableHeight: CGFloat = CGFloat(level) * 20.0 * CGFloat(factor)
        let finalHeight = max(baseHeight, min(24.0, baseHeight + variableHeight))

        RoundedRectangle(cornerRadius: 2)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.26, green: 0.52, blue: 0.96), // Gemini Blue
                        Color(red: 0.65, green: 0.35, blue: 0.98), // Purple
                        Color(red: 0.95, green: 0.35, blue: 0.65)  // Pink Accent
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 3.5, height: finalHeight)
            .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.6), value: finalHeight)
    }
}
