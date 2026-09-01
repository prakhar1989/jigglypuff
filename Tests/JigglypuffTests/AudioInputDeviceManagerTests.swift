import XCTest
import CoreAudio
@testable import Jigglypuff

@MainActor
final class AudioInputDeviceManagerTests: XCTestCase {
    private func device(id: AudioDeviceID,
                        uid: String,
                        modelUID: String? = nil,
                        manufacturer: String? = nil,
                        name: String) -> AudioInputDevice {
        AudioInputDevice(id: id,
                         uid: uid,
                         modelUID: modelUID,
                         manufacturer: manufacturer,
                         name: name,
                         isSystemDefault: false)
    }

    func testExactUIDMatchWins() {
        let selected = AudioInputDeviceSelection(uid: "uid.external",
                                                  modelUID: "model.external",
                                                  manufacturer: "Acme",
                                                  name: "External Microphone")
        let expected = device(id: 17,
                              uid: "uid.external",
                              modelUID: "model.external",
                              manufacturer: "Acme",
                              name: "External Microphone")

        let result = AudioInputDeviceManager.resolve(selected, from: [expected])

        XCTAssertEqual(result.device, expected)
        XCTAssertEqual(result.reason, "matched persisted device UID")
        XCTAssertFalse(result.usesSystemDefault)
    }

    func testModelUIDMatchesAReconnectedDeviceWithNewDeviceUID() {
        let selected = AudioInputDeviceSelection(uid: "old.device.uid",
                                                  modelUID: "model.external",
                                                  manufacturer: "Acme",
                                                  name: "External Microphone")
        let reconnected = device(id: 42,
                                 uid: "new.device.uid",
                                 modelUID: "model.external",
                                 manufacturer: "Acme",
                                 name: "External Microphone")

        let result = AudioInputDeviceManager.resolve(selected, from: [reconnected])

        XCTAssertEqual(result.device, reconnected)
        XCTAssertEqual(result.reason, "matched persisted model UID")
    }

    func testUnavailableDeviceFallsBackWithoutChangingSavedSelection() {
        let selected = AudioInputDeviceSelection(uid: "missing.device.uid",
                                                  modelUID: "missing.model",
                                                  manufacturer: "Acme",
                                                  name: "Removed Microphone")

        let result = AudioInputDeviceManager.resolve(selected, from: [])

        XCTAssertTrue(result.usesSystemDefault)
        XCTAssertEqual(result.requested, selected)
        XCTAssertEqual(result.reason, "saved device is unavailable or ambiguous; using system default")
    }

    func testAmbiguousNameDoesNotSilentlyChooseWrongDevice() {
        let selected = AudioInputDeviceSelection(uid: "missing.device.uid",
                                                  name: "USB Microphone")
        let first = device(id: 10, uid: "first.uid", name: "USB Microphone")
        let second = device(id: 11, uid: "second.uid", name: "USB Microphone")

        let result = AudioInputDeviceManager.resolve(selected, from: [first, second])

        XCTAssertTrue(result.usesSystemDefault)
        XCTAssertEqual(result.requested, selected)
    }
}
