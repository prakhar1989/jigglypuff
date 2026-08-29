import Foundation
import AVFoundation
import AppKit
import ApplicationServices

/// Manages system permissions for Microphone and Accessibility (auto typing)
@MainActor
public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()

    @Published public var isMicrophoneGranted: Bool = false
    @Published public var isAccessibilityGranted: Bool = false

    private var timer: Timer?

    private init() {
        checkPermissions()
        startPeriodicCheck()
    }

    /// Refresh current permission statuses
    public func checkPermissions() {
        // Check Microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            self.isMicrophoneGranted = true
        default:
            self.isMicrophoneGranted = false
        }

        // Check Accessibility permission
        self.isAccessibilityGranted = AXIsProcessTrusted()
    }

    /// Periodically poll permissions so the UI reflects changes when user updates macOS System Settings
    private func startPeriodicCheck() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermissions()
            }
        }
    }

    /// Request Microphone access
    public func requestMicrophoneAccess(completion: @escaping @Sendable (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                self.isMicrophoneGranted = granted
                completion(granted)
            }
        }
    }

    /// Request Accessibility permission prompt
    public func requestAccessibilityAccess() {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options: CFDictionary = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        checkPermissions()
    }

    /// Deep link to macOS System Settings -> Privacy & Security -> Microphone
    public func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Deep link to macOS System Settings -> Privacy & Security -> Accessibility
    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
