import Foundation
import Combine
import CoreAudio

/// A currently available audio input and the stable identity used to persist it.
public struct AudioInputDevice: Identifiable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let modelUID: String?
    public let manufacturer: String?
    public let name: String
    public let isSystemDefault: Bool

    public var identity: AudioInputDeviceSelection {
        AudioInputDeviceSelection(uid: uid,
                                   modelUID: modelUID,
                                   manufacturer: manufacturer,
                                   name: name)
    }
}

/// Result of resolving a persisted selection against currently available devices.
public struct AudioDeviceRouteResolution: Sendable {
    public let requested: AudioInputDeviceSelection
    public let device: AudioInputDevice?
    public let reason: String

    public var usesSystemDefault: Bool {
        device == nil
    }
}

/// Owns audio-device discovery, persistence resolution, and hot-plug observation.
///
/// Callers use a small interface: enumerate/resolve a route and observe the current
/// device list. Core Audio details and recovery policy stay local to this module.
@MainActor
public final class AudioInputDeviceManager: ObservableObject {
    public static let shared = AudioInputDeviceManager()

    @Published public private(set) var devices: [AudioInputDevice]

    private var deviceListListener: AudioObjectPropertyListenerBlock?
    private var defaultInputListener: AudioObjectPropertyListenerBlock?

    private init() {
        self.devices = Self.enumerateInputDevices()
        installHardwareListeners()
    }

    public func refresh() {
        devices = Self.enumerateInputDevices()
    }

    /// Resolves a saved selection. Exact UID wins; metadata fallbacks are only used
    /// when they identify one unambiguous current device. Otherwise System Default is
    /// used without overwriting the saved preference, so a reconnected device can be
    /// selected automatically on the next recording.
    public static func resolve(_ selection: AudioInputDeviceSelection,
                               from devices: [AudioInputDevice]? = nil) -> AudioDeviceRouteResolution {
        let available = devices ?? enumerateInputDevices()

        if selection.isSystemDefault {
            return AudioDeviceRouteResolution(requested: selection,
                                              device: nil,
                                              reason: "system default requested")
        }

        if let uid = selection.uid,
           let exactMatch = available.first(where: { $0.uid == uid }) {
            return AudioDeviceRouteResolution(requested: selection,
                                              device: exactMatch,
                                              reason: "matched persisted device UID")
        }

        if let modelUID = selection.modelUID, !modelUID.isEmpty {
            let modelMatches = available.filter { device in
                device.modelUID == modelUID &&
                (selection.manufacturer == nil || device.manufacturer == selection.manufacturer)
            }
            if modelMatches.count == 1, let match = modelMatches.first {
                return AudioDeviceRouteResolution(requested: selection,
                                                  device: match,
                                                  reason: "matched persisted model UID")
            }
        }

        if let name = selection.name, !name.isEmpty {
            let nameMatches = available.filter { device in
                device.name == name &&
                (selection.manufacturer == nil || device.manufacturer == selection.manufacturer)
            }
            if nameMatches.count == 1, let match = nameMatches.first {
                return AudioDeviceRouteResolution(requested: selection,
                                                  device: match,
                                                  reason: "matched unique persisted name")
            }
        }

        return AudioDeviceRouteResolution(requested: selection,
                                          device: nil,
                                          reason: "saved device is unavailable or ambiguous; using system default")
    }

    /// Lists all currently available input-capable devices.
    nonisolated public static func enumerateInputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )

        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize) == noErr else { return [] }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: Int(dataSize) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &deviceIDs) == noErr else { return [] }

        let defaultID = defaultInputDeviceID()
        return deviceIDs.compactMap { deviceID in
            guard inputChannelCount(of: deviceID) > 0,
                  let uid = stringProperty(of: deviceID, selector: kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(of: deviceID, selector: kAudioObjectPropertyName) else {
                return nil
            }

            return AudioInputDevice(
                id: deviceID,
                uid: uid,
                modelUID: stringProperty(of: deviceID, selector: kAudioDevicePropertyModelUID),
                manufacturer: stringProperty(of: deviceID, selector: kAudioObjectPropertyManufacturer),
                name: name,
                isSystemDefault: deviceID == defaultID
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated public static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID) == noErr,
              deviceID != 0 else { return nil }
        return deviceID
    }

    private func installHardwareListeners() {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        let queue = DispatchQueue.main

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        let deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        deviceListListener = deviceListener
        AudioObjectAddPropertyListenerBlock(systemObject, &devicesAddress, queue, deviceListener)

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        let defaultListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        defaultInputListener = defaultListener
        AudioObjectAddPropertyListenerBlock(systemObject, &defaultInputAddress, queue, defaultListener)
    }

    nonisolated private static func inputChannelCount(of deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else { return 0 }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferList) == noErr else { return 0 }

        return UnsafeMutableAudioBufferListPointer(bufferList).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    nonisolated private static func stringProperty(of deviceID: AudioDeviceID,
                                                   selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var value: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr else { return nil }
        return value as String
    }
}
