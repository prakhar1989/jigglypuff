import Foundation
import Carbon
import AppKit

/// Protocol for hotkey event delegate
@MainActor
public protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyPressed()
    func hotkeyReleased()
}

/// Global Hotkey Manager supporting Push-to-Talk and Toggle triggers using Carbon Event HotKeys.
@MainActor
public final class HotkeyManager {
    public static let shared = HotkeyManager()

    public weak var delegate: HotkeyManagerDelegate?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private init() {}

    /// Registers the global hotkey with given keycode and Carbon modifier flags
    public func register(keyCode: UInt32 = 49, modifiers: UInt32 = UInt32(optionKey)) {
        unregister()

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(1416787301) // "TRAN"
        hotKeyID.id = 1

        var eventType = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                GetEventParameter(theEvent,
                                  EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID),
                                  nil,
                                  MemoryLayout<EventHotKeyID>.size,
                                  nil,
                                  &hotKeyID)

                let eventKind = GetEventKind(theEvent)
                if eventKind == UInt32(kEventHotKeyPressed) {
                    Task { @MainActor in
                        manager.delegate?.hotkeyPressed()
                    }
                } else if eventKind == UInt32(kEventHotKeyReleased) {
                    Task { @MainActor in
                        manager.delegate?.hotkeyReleased()
                    }
                }

                return noErr
            },
            2,
            &eventType,
            selfPointer,
            &eventHandler
        )

        if status == noErr {
            let regStatus = RegisterEventHotKey(
                keyCode,
                modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if regStatus != noErr {
                print("Failed to register Carbon HotKey. Status: \(regStatus)")
            }
        }
    }

    /// Unregisters the current hotkey
    public func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
