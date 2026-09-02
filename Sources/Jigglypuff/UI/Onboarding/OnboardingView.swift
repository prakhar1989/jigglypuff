import SwiftUI
import AppKit

/// Landing page-themed cartoon color palette
private enum CandyTheme {
    static let plumDark = Color(red: 0.176, green: 0.094, blue: 0.278) // #2D1847
    static let pinkCandy = Color(red: 1.0, green: 0.396, blue: 0.639) // #FF65A3
    static let pinkGradStart = Color(red: 1.0, green: 0.467, blue: 0.678) // #FF77AD
    static let pinkGradEnd = Color(red: 1.0, green: 0.294, blue: 0.545) // #FF4B8B
    static let pinkPastel = Color(red: 1.0, green: 0.761, blue: 0.875) // #FFC2DF
    static let pinkSoft = Color(red: 1.0, green: 0.941, blue: 0.969) // #FFF0F7
    static let cyanPastel = Color(red: 0.729, green: 0.902, blue: 0.992) // #BAE6FD
    static let cyanDeep = Color(red: 0.008, green: 0.518, blue: 0.780) // #0284C7
    static let yellowPastel = Color(red: 0.996, green: 0.941, blue: 0.541) // #FEF08A
    static let yellowCandy = Color(red: 0.992, green: 0.878, blue: 0.278) // #FDE047
    static let greenPastel = Color(red: 0.733, green: 0.969, blue: 0.816) // #BBF7D0
    static let greenDeep = Color(red: 0.086, green: 0.639, blue: 0.290) // #16A34A
    static let bgCanvas = Color(red: 0.992, green: 0.973, blue: 1.0) // #FDF8FF
    static let textMuted = Color(red: 0.392, green: 0.333, blue: 0.475) // #645579
}

/// First-launch onboarding view styled after the Jigglypuff landing page aesthetic
public struct OnboardingView: View {
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var permissions = PermissionManager.shared

    @State private var apiKeyInput: String = ""
    @State private var showAPIKey: Bool = false
    @State private var isTestingAPI: Bool = false
    @State private var testStatus: String? = nil
    @State private var isSuccess: Bool = false

    var onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void = {}) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Dreamy pastel candy background
            CandyTheme.bgCanvas
                .ignoresSafeArea()

            // Subtle polka-dot or soft radial glow overlay
            RadialGradient(
                colors: [
                    CandyTheme.pinkPastel.opacity(0.35),
                    CandyTheme.cyanPastel.opacity(0.2),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 450
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header: Squishy Avatar & Welcome
                headerSection

                // Cards: Permissions & API Key
                VStack(spacing: 12) {
                    microphoneCard
                    accessibilityCard
                    apiKeyCard
                }

                Spacer(minLength: 4)

                // Bottom Action: Start Dictating CTA
                bottomCTASection
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .frame(width: 520, height: 650)
        .onAppear {
            apiKeyInput = settings.apiKey
            permissions.checkPermissions()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 10) {
            // Avatar frame with dark outline and offset shadow
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 56, height: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(CandyTheme.plumDark, lineWidth: 2.5)
                        )
                        .shadow(color: CandyTheme.plumDark, radius: 0, x: 2.5, y: 2.5)

                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 46, height: 46)
                        .cornerRadius(12)
                }

                // Playful sticker badge
                Text("v0.3 • macOS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(CandyTheme.plumDark)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(CandyTheme.yellowPastel)
                    .cornerRadius(999)
                    .overlay(
                        RoundedRectangle(cornerRadius: 999)
                            .stroke(CandyTheme.plumDark, lineWidth: 1.5)
                    )
                    .shadow(color: CandyTheme.plumDark, radius: 0, x: 1.5, y: 1.5)
                    .rotationEffect(.degrees(2))
            }

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text("Welcome to")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(CandyTheme.plumDark)
                    Text("Jigglypuff!")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(CandyTheme.pinkCandy)
                }

                Text("Sing your thoughts. Before you begin dictating, let's configure your permissions and Gemini API key.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(CandyTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Microphone Card

    private var microphoneCard: some View {
        cartoonCard {
            HStack(spacing: 12) {
                cardIcon(symbol: "mic.fill", bg: CandyTheme.pinkPastel)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Microphone Access")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(CandyTheme.plumDark)
                    Text("Required to capture your voice when you speak.")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundColor(CandyTheme.textMuted)
                }

                Spacer()

                if permissions.isMicrophoneGranted {
                    grantedBadge
                } else {
                    Button(action: {
                        permissions.requestMicrophoneAccess { _ in }
                    }) {
                        Text("Allow Access")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(CandyTheme.plumDark)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(CandyTheme.pinkPastel)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(CandyTheme.plumDark, lineWidth: 1.8)
                            )
                            .shadow(color: CandyTheme.plumDark, radius: 0, x: 2, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Accessibility Card

    private var accessibilityCard: some View {
        cartoonCard {
            HStack(spacing: 12) {
                cardIcon(symbol: "keyboard.fill", bg: CandyTheme.cyanPastel)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility Access")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(CandyTheme.plumDark)
                    Text("Required to auto-type text straight into your active app.")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundColor(CandyTheme.textMuted)
                }

                Spacer()

                if permissions.isAccessibilityGranted {
                    grantedBadge
                } else {
                    Button(action: {
                        permissions.requestAccessibilityAccess()
                        permissions.openAccessibilitySettings()
                    }) {
                        Text("Grant Access")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(CandyTheme.plumDark)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(CandyTheme.cyanPastel)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(CandyTheme.plumDark, lineWidth: 1.8)
                            )
                            .shadow(color: CandyTheme.plumDark, radius: 0, x: 2, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Gemini API Key Card

    private var apiKeyCard: some View {
        cartoonCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    cardIcon(symbol: "sparkles", bg: CandyTheme.yellowPastel)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gemini API Key")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(CandyTheme.plumDark)
                        Text("Powers speech-to-text. Stored safely in macOS Keychain.")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundColor(CandyTheme.textMuted)
                    }

                    Spacer()

                    Link("Get Key ↗", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundColor(CandyTheme.cyanDeep)
                }

                // Input Box with Eye Button
                HStack(spacing: 8) {
                    Group {
                        if showAPIKey {
                            TextField("Paste AI Studio API key (AIzaSy...)", text: $apiKeyInput)
                        } else {
                            SecureField("Paste AI Studio API key (AIzaSy...)", text: $apiKeyInput)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(CandyTheme.plumDark)
                    .onChange(of: apiKeyInput) { _, newValue in
                        settings.apiKey = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    Button(action: { showAPIKey.toggle() }) {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .font(.system(size: 11))
                            .foregroundColor(CandyTheme.plumDark.opacity(0.7))
                    }
                    .buttonStyle(.plain)

                    Button(action: testConnection) {
                        HStack(spacing: 4) {
                            if isTestingAPI {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Text(isTestingAPI ? "Testing…" : "Test")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(CandyTheme.plumDark)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(CandyTheme.yellowCandy)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(CandyTheme.plumDark, lineWidth: 1.2)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTestingAPI)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(CandyTheme.plumDark, lineWidth: 1.5)
                )

                if let status = testStatus {
                    HStack(spacing: 4) {
                        Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        Text(status)
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(isSuccess ? CandyTheme.greenDeep : .red)
                }
            }
        }
    }

    // MARK: - Bottom CTA Section

    private var bottomCTASection: some View {
        VStack(spacing: 8) {
            Button(action: finishOnboarding) {
                HStack(spacing: 8) {
                    Text("Start Dictating")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("🎵")
                        .font(.system(size: 16))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [CandyTheme.pinkGradStart, CandyTheme.pinkGradEnd],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(CandyTheme.plumDark, lineWidth: 2.5)
                )
                .shadow(color: CandyTheme.plumDark, radius: 0, x: 3, y: 3)
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Text("Press")
                    .foregroundColor(CandyTheme.textMuted)
                Text("⌥ Space")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(CandyTheme.yellowCandy)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(CandyTheme.plumDark, lineWidth: 1))
                Text("anywhere to dictate • Configurable in Settings")
                    .foregroundColor(CandyTheme.textMuted)
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
        }
    }

    // MARK: - Helper Views & Actions

    private func cartoonCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(CandyTheme.plumDark, lineWidth: 2)
            )
            .shadow(color: CandyTheme.plumDark, radius: 0, x: 2.5, y: 2.5)
    }

    private func cardIcon(symbol: String, bg: Color) -> some View {
        ZStack {
            Circle()
                .fill(bg)
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(CandyTheme.plumDark, lineWidth: 1.8))
                .shadow(color: CandyTheme.plumDark, radius: 0, x: 1.5, y: 1.5)

            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(CandyTheme.plumDark)
        }
    }

    private var grantedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .black))
            Text("Allowed")
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
        }
        .foregroundColor(CandyTheme.greenDeep)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(CandyTheme.greenPastel)
        .cornerRadius(999)
        .overlay(
            RoundedRectangle(cornerRadius: 999)
                .stroke(CandyTheme.plumDark, lineWidth: 1.5)
        )
        .shadow(color: CandyTheme.plumDark, radius: 0, x: 1.5, y: 1.5)
    }

    private func finishOnboarding() {
        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            settings.apiKey = trimmedKey
        }
        settings.hasCompletedOnboarding = true
        SoundEffects.shared.playSuccess()
        onDismiss()
    }

    private func testConnection() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        settings.apiKey = key

        isTestingAPI = true
        testStatus = nil
        isSuccess = false

        Task {
            let dummyWav = createDummyTestWAV()
            do {
                _ = try await GeminiTranscribeService.shared.transcribe(
                    audioData: dummyWav,
                    model: settings.selectedModel,
                    mode: .smartFlow
                )
                testStatus = "✓ Success! Gemini API connected."
                isSuccess = true
            } catch {
                testStatus = "✗ Error: \(error.localizedDescription)"
                isSuccess = false
            }
            isTestingAPI = false
        }
    }

    private func createDummyTestWAV() -> Data {
        let sampleRate = 16000
        let numSamples = 8000
        let pcmData = Data(count: numSamples * 2)
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
