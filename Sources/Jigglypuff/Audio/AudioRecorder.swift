import Foundation
import AVFoundation
import Accelerate
import CoreAudio
import AudioUnit

private final class AudioBufferStorage: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var data: Data = Data()

    func append(_ chunk: Data) {
        os_unfair_lock_lock(&lock)
        data.append(chunk)
        os_unfair_lock_unlock(&lock)
    }

    func extractAndReset() -> Data {
        os_unfair_lock_lock(&lock)
        let result = data
        data = Data()
        os_unfair_lock_unlock(&lock)
        return result
    }

    func reset() {
        os_unfair_lock_lock(&lock)
        data = Data()
        os_unfair_lock_unlock(&lock)
    }

    var byteCount: Int {
        os_unfair_lock_lock(&lock)
        let count = data.count
        os_unfair_lock_unlock(&lock)
        return count
    }
}

private final class AudioConverterBufferProvider: @unchecked Sendable {
    var isExhausted: Bool = false
    let buffer: AVAudioPCMBuffer

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

private final class ResilientAudioConverter: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private var cachedInputFormat: AVAudioFormat?
    private let targetFormat: AVAudioFormat

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    func process(buffer: AVAudioPCMBuffer) -> (pcmData: Data?, audioLevel: Float) {
        let inputFormat = buffer.format
        guard inputFormat.sampleRate > 0, buffer.frameLength > 0 else {
            return (nil, 0.0)
        }

        // 1. Calculate RMS audio level with voice-activity noise gate
        // Ambient room noise sits around -55dB to -44dB; speech sits between -36dB and -10dB.
        var rawRms: Float = 0.0
        if let floatChannelData = buffer.floatChannelData {
            vDSP_rmsqv(floatChannelData[0], 1, &rawRms, vDSP_Length(buffer.frameLength))
        } else if let int16Data = buffer.int16ChannelData {
            var floatSamples = [Float](repeating: 0, count: Int(buffer.frameLength))
            vDSP_vflt16(int16Data[0], 1, &floatSamples, 1, vDSP_Length(buffer.frameLength))
            var scale: Float = 1.0 / 32768.0
            vDSP_vsmul(floatSamples, 1, &scale, &floatSamples, 1, vDSP_Length(buffer.frameLength))
            vDSP_rmsqv(floatSamples, 1, &rawRms, vDSP_Length(buffer.frameLength))
        }

        let noiseFloorDb: Float = -42.0 // Noise gate: ambient room noise below -42dB produces 0.0
        let maxSpeechDb: Float = -12.0
        let db = 20.0 * log10(max(rawRms, 0.000001))
        
        let normalizedLevel: Float
        if db <= noiseFloorDb {
            normalizedLevel = 0.0
        } else {
            let linear = (db - noiseFloorDb) / (maxSpeechDb - noiseFloorDb)
            let clamped = max(0.0, min(1.0, linear))
            normalizedLevel = pow(clamped, 1.3) // Exponential curve for punchy vocal response
        }

        // 2. Fast path: if incoming format already matches target format (16kHz 1ch Float32)
        if inputFormat == targetFormat, let floatData = buffer.floatChannelData {
            let frameLength = Int(buffer.frameLength)
            var int16Data = Data(capacity: frameLength * 2)
            for i in 0..<frameLength {
                let sample = max(-1.0, min(1.0, floatData[0][i]))
                var intSample = Int16(sample * 32767.0)
                withUnsafeBytes(of: &intSample) { int16Data.append(contentsOf: $0) }
            }
            return (int16Data, normalizedLevel)
        }

        // 3. Dynamic / cached converter lookup (adapts if sample rate or channel count changes mid-stream)
        if converter == nil || cachedInputFormat != inputFormat {
            guard let newConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                print("Jigglypuff Audio: Could not create audio converter from \(inputFormat) to \(targetFormat)")
                return (nil, normalizedLevel)
            }
            self.converter = newConverter
            self.cachedInputFormat = inputFormat
        }

        guard let conv = converter else {
            return (nil, normalizedLevel)
        }

        let sampleRateRatio = targetFormat.sampleRate / inputFormat.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRateRatio) + 1024
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return (nil, normalizedLevel)
        }

        var error: NSError?
        let provider = AudioConverterBufferProvider(buffer: buffer)
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if provider.isExhausted {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            provider.isExhausted = true
            return provider.buffer
        }

        let status = conv.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        if status == .error || error != nil {
            print("Jigglypuff Audio conversion error: \(error?.localizedDescription ?? "unknown error")")
            conv.reset()
            return (nil, normalizedLevel)
        }

        guard let floatChannelData = convertedBuffer.floatChannelData else {
            return (nil, normalizedLevel)
        }
        let frameLength = Int(convertedBuffer.frameLength)
        guard frameLength > 0 else {
            return (nil, normalizedLevel)
        }

        var int16Data = Data(capacity: frameLength * 2)
        for i in 0..<frameLength {
            let sample = max(-1.0, min(1.0, floatChannelData[0][i]))
            var intSample = Int16(sample * 32767.0)
            withUnsafeBytes(of: &intSample) { int16Data.append(contentsOf: $0) }
        }

        return (int16Data, normalizedLevel)
    }
}

/// An audio input device available on this Mac.
public struct AudioInputDevice: Identifiable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let isSystemDefault: Bool
}

/// Audio capture engine using AVAudioEngine, producing 16kHz Linear PCM WAV audio.
@MainActor
public final class AudioRecorder: ObservableObject {
    public static let shared = AudioRecorder()

    @Published public var isRecording: Bool = false
    @Published public var audioLevel: Float = 0.0 // 0.0 to 1.0 normalized for waveform

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private let bufferStorage = AudioBufferStorage()
    private let targetSampleRate: Double = 16000.0

    private init() {}

    /// Starts recording audio from default or configured input device.
    public func startRecording() throws {
        stopEngine()
        bufferStorage.reset()

        let engine = AVAudioEngine()
        let input = engine.inputNode

        // Route capture to the input device selected in Settings (empty = system default)
        let selectedDeviceUID = SettingsStore.shared.audioInputDeviceUID
        if !selectedDeviceUID.isEmpty,
           let selectedDeviceID = AudioRecorder.inputDeviceID(forUID: selectedDeviceUID),
           let audioUnit = input.audioUnit {
            var deviceID = selectedDeviceID
            AudioUnitSetProperty(audioUnit,
                                 kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global,
                                 0,
                                 &deviceID,
                                 UInt32(MemoryLayout<AudioDeviceID>.size))
        }

        // Target format: 16kHz Mono Float32 for engine conversion
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: targetSampleRate,
                                               channels: 1,
                                               interleaved: false) else {
            throw NSError(domain: "JigglypuffAudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create target audio format."])
        }

        let converter = ResilientAudioConverter(targetFormat: targetFormat)
        let storage = self.bufferStorage

        // Install audio tap. Handler must come from a nonisolated factory —
        // the tap runs on AVAudioEngine's realtime thread, and a closure inheriting
        // MainActor isolation crashes there with SIGTRAP.
        let bufferSize: AVAudioFrameCount = 1024
        input.installTap(onBus: 0,
                         bufferSize: bufferSize,
                         format: nil,
                         block: makeTapHandler(converter: converter, storage: storage))

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.inputNode = input

        self.isRecording = true
        self.audioLevel = 0.0
    }

    /// Builds the audio tap callback in a nonisolated context so the returned closure
    /// does not inherit MainActor isolation (see note at call site).
    nonisolated private func makeTapHandler(converter: ResilientAudioConverter,
                                            storage: AudioBufferStorage) -> AVAudioNodeTapBlock {
        return { [weak self] buffer, _ in
            let (pcmData, level) = converter.process(buffer: buffer)
            if let pcmData = pcmData {
                storage.append(pcmData)
            }
            Task { @MainActor [weak self] in
                self?.audioLevel = level
            }
        }
    }

    /// Stops recording and returns WAV formatted audio data.
    public func stopRecording() -> Data {
        stopEngine()

        let rawData = bufferStorage.extractAndReset()

        self.isRecording = false
        self.audioLevel = 0.0

        guard !rawData.isEmpty else {
            return Data()
        }

        return createWAVData(from: rawData, sampleRate: Int(targetSampleRate), channels: 1, bitsPerSample: 16)
    }

    /// Cancels recording and discards audio buffer.
    public func cancelRecording() {
        stopEngine()
        bufferStorage.reset()
        self.isRecording = false
        self.audioLevel = 0.0
    }

    private func stopEngine() {
        if let input = inputNode {
            input.removeTap(onBus: 0)
        }
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }
        audioEngine = nil
        inputNode = nil
    }

    // MARK: - Input device enumeration

    /// Lists all audio devices with at least one input channel (built-in, USB, Bluetooth, virtual).
    nonisolated public static func availableInputDevices() -> [AudioInputDevice] {
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
            return AudioInputDevice(id: deviceID, uid: uid, name: name, isSystemDefault: deviceID == defaultID)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Resolves a persisted device UID to its current AudioDeviceID, if the device is still attached.
    nonisolated public static func inputDeviceID(forUID uid: String) -> AudioDeviceID? {
        availableInputDevices().first(where: { $0.uid == uid })?.id
    }

    nonisolated private static func defaultInputDeviceID() -> AudioDeviceID? {
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

    /// Total number of input channels a device exposes (0 for output-only devices).
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

    /// Reads a CFString property (name, UID, ...) from an audio device.
    nonisolated private static func stringProperty(of deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
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

    /// Wraps raw 16-bit PCM data in a standard RIFF/WAV header
    nonisolated private func createWAVData(from pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        var wavData = Data()
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let subchunk2Size = pcmData.count
        let chunkSize = 36 + subchunk2Size

        // RIFF chunk descriptor
        wavData.append("RIFF".data(using: .ascii)!)
        var chunkSizeUInt32 = UInt32(chunkSize).littleEndian
        wavData.append(Data(bytes: &chunkSizeUInt32, count: 4))
        wavData.append("WAVE".data(using: .ascii)!)

        // "fmt " sub-chunk
        wavData.append("fmt ".data(using: .ascii)!)
        var subchunk1Size = UInt32(16).littleEndian // PCM size = 16
        wavData.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat = UInt16(1).littleEndian // 1 = PCM
        wavData.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = UInt16(channels).littleEndian
        wavData.append(Data(bytes: &numChannels, count: 2))
        var sampleRateUInt32 = UInt32(sampleRate).littleEndian
        wavData.append(Data(bytes: &sampleRateUInt32, count: 4))
        var byteRateUInt32 = UInt32(byteRate).littleEndian
        wavData.append(Data(bytes: &byteRateUInt32, count: 4))
        var blockAlignUInt16 = UInt16(blockAlign).littleEndian
        wavData.append(Data(bytes: &blockAlignUInt16, count: 2))
        var bitsPerSampleUInt16 = UInt16(bitsPerSample).littleEndian
        wavData.append(Data(bytes: &bitsPerSampleUInt16, count: 2))

        // "data" sub-chunk
        wavData.append("data".data(using: .ascii)!)
        var subchunk2SizeUInt32 = UInt32(subchunk2Size).littleEndian
        wavData.append(Data(bytes: &subchunk2SizeUInt32, count: 4))
        wavData.append(pcmData)

        return wavData
    }
}
