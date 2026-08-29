import Foundation
import AppKit
import AVFoundation

/// Provides audio feedback tones for dictation state transitions.
@MainActor
public final class SoundEffects {
    public static let shared = SoundEffects()

    private init() {}

    /// Plays a soft start listening chime
    public func playStart() {
        guard SettingsStore.shared.playSoundEffects else { return }
        NSSound(named: "Tink")?.play()
    }

    /// Plays a stop recording cue
    public func playStop() {
        guard SettingsStore.shared.playSoundEffects else { return }
        NSSound(named: "Pop")?.play()
    }

    /// Plays a success confirmation sound
    public func playSuccess() {
        guard SettingsStore.shared.playSoundEffects else { return }
        NSSound(named: "Hero")?.play()
    }

    /// Plays an error alert sound
    public func playError() {
        guard SettingsStore.shared.playSoundEffects else { return }
        NSSound(named: "Basso")?.play()
    }
}
