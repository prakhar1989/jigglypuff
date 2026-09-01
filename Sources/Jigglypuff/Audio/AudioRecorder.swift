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

final class ResilientAudioConverter: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private var cachedInputFormat: AVAudioFormat?
    private let targetFormat: AVAudioFormat

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    func process(buffer: AVAudioPCMBuffer) -> (pcmData: Data?, audioLevel: Float) {
        let sourceBuffer = monoBufferSelectingLoudestChannel(from: buffer)
        let inputFormat = sourceBuffer.format
        guard inputFormat.sampleRate > 0, sourceBuffer.frameLength > 0 else {
            return (nil, 0.0)
        }

        // 1. Calculate RMS audio level with voice-activity noise gate
        // Ambient room noise sits around -55dB to -44dB; speech sits between -36dB and -10dB.
        var rawRms: Float = 0.0
        if let floatChannelData = sourceBuffer.floatChannelData {
            vDSP_rmsqv(floatChannelData[0], 1, &rawRms, vDSP_Length(sourceBuffer.frameLength))
        } else if let int16Data = sourceBuffer.int16ChannelData {
            var floatSamples = [Float](repeating: 0, count: Int(sourceBuffer.frameLength))
            vDSP_vflt16(int16Data[0], 1, &floatSamples, 1, vDSP_Length(sourceBuffer.frameLength))
            var scale: Float = 1.0 / 32768.0
            vDSP_vsmul(floatSamples, 1, &scale, &floatSamples, 1, vDSP_Length(sourceBuffer.frameLength))
            vDSP_rmsqv(floatSamples, 1, &rawRms, vDSP_Length(sourceBuffer.frameLength))
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
        if inputFormat == targetFormat, let floatData = sourceBuffer.floatChannelData {
            let frameLength = Int(sourceBuffer.frameLength)
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
            // Fall back to the first real input channel if an interleaved or non-Float32
            // multichannel buffer could not be normalized above. This overrides layout
            // remapping that may otherwise select a silent channel.
            if inputFormat.channelCount > targetFormat.channelCount {
                newConverter.channelMap = [0]
            }
            // Each tap callback supplies live audio that cannot be read ahead. Avoid
            // converter priming requirements intended for file-backed input.
            newConverter.primeMethod = .none
            self.converter = newConverter
            self.cachedInputFormat = inputFormat
        }

        guard let conv = converter else {
            return (nil, normalizedLevel)
        }

        let sampleRateRatio = targetFormat.sampleRate / inputFormat.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * sampleRateRatio) + 1024
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return (nil, normalizedLevel)
        }

        var error: NSError?
        let provider = AudioConverterBufferProvider(buffer: sourceBuffer)
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

    /// Audio interfaces often expose several unrelated discrete inputs. Channel-layout
    /// conversion can map such an interface to an absent mono channel and produce
    /// digital silence, so select the channel carrying the strongest signal first.
    private func monoBufferSelectingLoudestChannel(from buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let format = buffer.format
        let channelCount = Int(format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard channelCount > 1,
              frameCount > 0,
              !format.isInterleaved,
              let inputChannels = buffer.floatChannelData,
              let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                              sampleRate: format.sampleRate,
                                              channels: 1,
                                              interleaved: false),
              let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat,
                                                 frameCapacity: buffer.frameLength),
              let monoChannel = monoBuffer.floatChannelData?[0] else {
            return buffer
        }

        var loudestChannel = 0
        var loudestRms: Float = -1
        for channelIndex in 0..<channelCount {
            var rms: Float = 0
            vDSP_rmsqv(inputChannels[channelIndex],
                       1,
                       &rms,
                       vDSP_Length(buffer.frameLength))
            if rms > loudestRms {
                loudestRms = rms
                loudestChannel = channelIndex
            }
        }

        monoBuffer.frameLength = buffer.frameLength
        monoChannel.update(from: inputChannels[loudestChannel], count: frameCount)
        return monoBuffer
    }
}

/// Audio capture engine using AVAudioEngine, producing 16kHz Linear PCM WAV audio.
private enum AudioRecorderError: LocalizedError {
    case deviceUnavailable(String)
    case deviceRouteFailed(String)
    case inputUnavailable

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable(let reason):
            return "The selected microphone is unavailable. \(reason)"
        case .deviceRouteFailed(let reason):
            return "Could not route audio to the selected microphone. \(reason)"
        case .inputUnavailable:
            return "The microphone input is unavailable. Please check macOS microphone permissions and audio input settings."
        }
    }
}

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

    /// Location used by the temporary diagnostic build to preserve captured WAV files.
    public static func debugRecordingsDirectoryURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Jigglypuff", isDirectory: true)
            .appendingPathComponent("DebugRecordings", isDirectory: true)
    }

    /// Starts recording audio from default or configured input device.
    public func startRecording() throws {
        stopEngine()
        bufferStorage.reset()

        let engine = AVAudioEngine()
        let input = engine.inputNode

        // Resolve the persisted identity against the devices that exist now. If a
        // device was unplugged, keep the preference but explicitly use System Default
        // for this recording so a reconnect can restore it later.
        let selection = SettingsStore.shared.audioInputDeviceSelection
        let route = AudioInputDeviceManager.resolve(selection)
        var expectedDeviceID: AudioDeviceID?

        if let selectedDevice = route.device {
            expectedDeviceID = selectedDevice.id
            print("[DEBUG-AUDIO] Resolved \(route.reason): \(selectedDevice.name) [uid=\(selectedDevice.uid), id=\(selectedDevice.id)].")
        } else {
            print("[DEBUG-AUDIO] Using System Default (\(route.reason)).")
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

        let bufferSize: AVAudioFrameCount = 1024

        // AVAudioEngine enables input I/O only when its graph is active. Use a
        // temporary tap to initialize the audio unit, then remove it before changing
        // devices. A tap installed before the change retains the old device's channel
        // format (for example FM3's 4 channels when switching to a mono microphone),
        // which can make the eventual mono recording silent.
        if let selectedDevice = route.device {
            input.installTap(onBus: 0,
                             bufferSize: bufferSize,
                             format: nil,
                             block: { _, _ in })
            engine.prepare()
            do {
                try engine.start()
            } catch {
                input.removeTap(onBus: 0)
                throw error
            }

            engine.stop()
            input.removeTap(onBus: 0)

            guard let audioUnit = input.audioUnit else {
                throw AudioRecorderError.deviceRouteFailed("The input audio unit is unavailable.")
            }

            var deviceID = selectedDevice.id
            let setStatus = AudioUnitSetProperty(audioUnit,
                                                 kAudioOutputUnitProperty_CurrentDevice,
                                                 kAudioUnitScope_Global,
                                                 0,
                                                 &deviceID,
                                                 UInt32(MemoryLayout<AudioDeviceID>.size))
            guard setStatus == noErr else {
                throw AudioRecorderError.deviceRouteFailed("AudioUnitSetProperty returned status \(setStatus).")
            }

            engine.reset()
        }

        let routedHardwareFormat = input.inputFormat(forBus: 0)
        let routedTapFormat = input.outputFormat(forBus: 0)
        print("[DEBUG-AUDIO] Routed hardware format: \(routedHardwareFormat), tap format: \(routedTapFormat).")
        guard routedTapFormat.sampleRate > 0, routedTapFormat.channelCount > 0 else {
            throw AudioRecorderError.inputUnavailable
        }

        // Install the real tap only after routing and format negotiation. Handler must
        // come from a nonisolated factory because AVAudioEngine invokes it on a
        // realtime thread; inheriting MainActor isolation crashes there with SIGTRAP.
        input.installTap(onBus: 0,
                         bufferSize: bufferSize,
                         format: nil,
                         block: makeTapHandler(converter: converter, storage: storage))

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }

        if let audioUnit = input.audioUnit {
            let actualDeviceID = currentDeviceID(of: audioUnit)
            let actualDeviceDescription = actualDeviceID.map { String($0) } ?? "unknown"
            print("[DEBUG-AUDIO] Audio unit current device ID after engine start: \(actualDeviceDescription).")
            if let expectedDeviceID, actualDeviceID != expectedDeviceID {
                input.removeTap(onBus: 0)
                engine.stop()
                throw AudioRecorderError.deviceRouteFailed("Expected device \(expectedDeviceID), but the engine is using \(actualDeviceDescription).")
            }
        }
        let activeHardwareFormat = input.inputFormat(forBus: 0)
        let activeTapFormat = input.outputFormat(forBus: 0)
        print("[DEBUG-AUDIO] Audio engine started. Hardware format: \(activeHardwareFormat), tap format: \(activeTapFormat), target format: \(targetFormat).")
        guard activeTapFormat.sampleRate > 0, activeTapFormat.channelCount > 0 else {
            input.removeTap(onBus: 0)
            engine.stop()
            throw AudioRecorderError.inputUnavailable
        }

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

        let wavData = createWAVData(from: rawData, sampleRate: Int(targetSampleRate), channels: 1, bitsPerSample: 16)
        saveDebugRecording(wavData, pcmByteCount: rawData.count)
        print("[DEBUG-AUDIO] Capture stopped. Converted PCM bytes: \(rawData.count), WAV bytes: \(wavData.count).")

        // Keep the existing empty-audio behavior for transcription while preserving
        // the diagnostic WAV header when no samples were captured.
        return rawData.isEmpty ? Data() : wavData
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

    private func saveDebugRecording(_ wavData: Data, pcmByteCount: Int) {
        guard let directoryURL = Self.debugRecordingsDirectoryURL() else {
            print("[DEBUG-AUDIO] Could not determine the debug recordings directory.")
            return
        }

        do {
            try FileManager.default.createDirectory(at: directoryURL,
                                                     withIntermediateDirectories: true,
                                                     attributes: nil)
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let filename = "recording-\(timestamp)-\(UUID().uuidString.prefix(8)).wav"
            let fileURL = directoryURL.appendingPathComponent(filename)
            try wavData.write(to: fileURL, options: .atomic)
            print("[DEBUG-AUDIO] Saved capture (\(pcmByteCount) PCM bytes) to \(fileURL.path)")
        } catch {
            print("[DEBUG-AUDIO] Failed to save capture: \(error.localizedDescription)")
        }
    }

    private func currentDeviceID(of audioUnit: AudioUnit) -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(audioUnit,
                                          kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global,
                                          0,
                                          &deviceID,
                                          &dataSize)
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    // MARK: - Input device enumeration

    /// Lists all audio devices with at least one input channel (built-in, USB, Bluetooth, virtual).
    nonisolated public static func availableInputDevices() -> [AudioInputDevice] {
        AudioInputDeviceManager.enumerateInputDevices()
    }

    /// Resolves a persisted device UID to its current AudioDeviceID, if the device is still attached.
    nonisolated public static func inputDeviceID(forUID uid: String) -> AudioDeviceID? {
        availableInputDevices().first(where: { $0.uid == uid })?.id
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
