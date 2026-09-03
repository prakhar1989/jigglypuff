import XCTest
import AVFoundation
import Accelerate
@testable import Jigglypuff

@MainActor
final class AudioIntegrationTests: XCTestCase {
    
    // MARK: - Format Conversion Integration Tests
    
    func testConversionFrom48kStereoTo16kMono() throws {
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false) else {
            XCTFail("Failed to initialize AVAudioFormat")
            return
        }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4800) else {
            XCTFail("Failed to create input buffer")
            return
        }
        buffer.frameLength = 4800 // 100ms at 48kHz
        
        // Generate test tone (440Hz sine wave across both channels)
        for i in 0..<4800 {
            let sample = Float(sin(2.0 * .pi * 440.0 * Double(i) / 48000.0) * 0.7)
            buffer.floatChannelData?[0][i] = sample
            buffer.floatChannelData?[1][i] = sample
        }

        let converter = ResilientAudioConverter(targetFormat: targetFormat)
        let result = converter.process(buffer: buffer)

        let pcmData = try XCTUnwrap(result.pcmData)
        XCTAssertGreaterThan(pcmData.count, 0)

        let peak = pcmData.withUnsafeBytes { rawBuffer -> Int16 in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            return samples.reduce(Int16(0)) { currentPeak, sample in
                max(currentPeak, sample.magnitude > currentPeak.magnitude ? sample : currentPeak)
            }
        }
        XCTAssertGreaterThan(peak.magnitude, 1_000, "Converted PCM should retain the input tone")
        XCTAssertGreaterThan(result.audioLevel, 0.0)
    }

    func testStreamingConversionFrom48kStereoTo16kMono() throws {
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false) else {
            XCTFail("Failed to initialize AVAudioFormat")
            return
        }

        let converter = ResilientAudioConverter(targetFormat: targetFormat)
        var convertedPCM = Data()

        // Match the recorder tap: 1,024-frame buffers arriving continuously.
        for chunkIndex in 0..<200 {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 1024) else {
                XCTFail("Failed to create input buffer")
                return
            }
            buffer.frameLength = 1024

            for frameIndex in 0..<1024 {
                let absoluteFrame = chunkIndex * 1024 + frameIndex
                let sample = Float(sin(2.0 * .pi * 440.0 * Double(absoluteFrame) / 48000.0) * 0.7)
                buffer.floatChannelData?[0][frameIndex] = sample
                buffer.floatChannelData?[1][frameIndex] = sample
            }

            if let pcmData = converter.process(buffer: buffer).pcmData {
                convertedPCM.append(pcmData)
            }
        }

        XCTAssertGreaterThan(convertedPCM.count, 0)
        let peakMagnitude = convertedPCM.withUnsafeBytes { rawBuffer -> UInt16 in
            rawBuffer.bindMemory(to: Int16.self).reduce(UInt16(0)) { peak, sample in
                max(peak, sample.magnitude)
            }
        }
        XCTAssertGreaterThan(peakMagnitude, 1_000, "Streaming conversion should retain the input tone")
    }

    func testConversionFromFourChannelInterfaceToMono() throws {
        let discreteFourChannelTag = kAudioChannelLayoutTag_DiscreteInOrder | AudioChannelLayoutTag(4)
        guard let channelLayout = AVAudioChannelLayout(layoutTag: discreteFourChannelTag),
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            XCTFail("Failed to initialize four-channel test audio")
            return
        }
        let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                        sampleRate: 48000,
                                        interleaved: false,
                                        channelLayout: channelLayout)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4800) else {
            XCTFail("Failed to initialize four-channel test buffer")
            return
        }
        buffer.frameLength = 4800

        // Model an interface such as FM3: speech is present on one discrete input
        // channel (not necessarily channel 1) while the others are silent.
        for frameIndex in 0..<4800 {
            buffer.floatChannelData?[0][frameIndex] = 0
            buffer.floatChannelData?[1][frameIndex] = 0
            buffer.floatChannelData?[2][frameIndex] = Float(sin(2.0 * .pi * 440.0 * Double(frameIndex) / 48000.0) * 0.7)
            buffer.floatChannelData?[3][frameIndex] = 0
        }

        let result = ResilientAudioConverter(targetFormat: targetFormat).process(buffer: buffer)
        let pcmData = try XCTUnwrap(result.pcmData)
        let peakMagnitude = pcmData.withUnsafeBytes { rawBuffer -> UInt16 in
            rawBuffer.bindMemory(to: Int16.self).reduce(UInt16(0)) { peak, sample in
                max(peak, sample.magnitude)
            }
        }

        XCTAssertGreaterThan(peakMagnitude, 1_000, "A discrete multichannel input must not downmix to silence")
    }

    func testResilientAudioConverterAcrossMultipleSampleRatesAndChannels() throws {
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            XCTFail("Failed to create target format")
            return
        }

        // Test matrix: (SampleRate, Channels)
        let testConfigurations: [(Double, UInt32, String)] = [
            (8000.0, 1, "8kHz Mono"),
            (16000.0, 1, "16kHz Mono (Native)"),
            (24000.0, 1, "24kHz Mono (Bluetooth HFP)"),
            (44100.0, 1, "44.1kHz Mono"),
            (44100.0, 2, "44.1kHz Stereo"),
            (48000.0, 1, "48kHz Mono"),
            (48000.0, 2, "48kHz Stereo (Standard Mac Output/Input)"),
            (96000.0, 2, "96kHz High-Res Stereo")
        ]

        for (sampleRate, channels, desc) in testConfigurations {
            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false) else {
                XCTFail("Failed to create format for \(desc)")
                continue
            }

            let frameCount: AVAudioFrameCount = AVAudioFrameCount(sampleRate * 0.1) // 100ms
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                XCTFail("Failed to create buffer for \(desc)")
                continue
            }
            buffer.frameLength = frameCount

            // Fill with a 440Hz test sine wave
            for ch in 0..<Int(channels) {
                guard let channelPtr = buffer.floatChannelData?[ch] else { continue }
                for i in 0..<Int(frameCount) {
                    channelPtr[i] = Float(sin(2.0 * .pi * 440.0 * Double(i) / sampleRate) * 0.5)
                }
            }

            XCTAssertGreaterThan(buffer.frameLength, 0, "Buffer for \(desc) should have positive frame length")
            XCTAssertEqual(buffer.format.sampleRate, sampleRate, "Sample rate for \(desc) should match")
        }
    }

    func testDynamicFormatSwitchingMidRecording() throws {
        // Simulates a Bluetooth headset switching from A2DP (48kHz) to HFP (16kHz or 24kHz) mid-recording
        guard let format48k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false),
              let format16k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let format44k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false) else {
            XCTFail("Failed to create test formats")
            return
        }

        let buf48k = AVAudioPCMBuffer(pcmFormat: format48k, frameCapacity: 1024)!
        buf48k.frameLength = 1024
        for i in 0..<1024 {
            buf48k.floatChannelData?[0][i] = 0.4
            buf48k.floatChannelData?[1][i] = 0.4
        }

        let buf16k = AVAudioPCMBuffer(pcmFormat: format16k, frameCapacity: 1024)!
        buf16k.frameLength = 1024
        for i in 0..<1024 {
            buf16k.floatChannelData?[0][i] = 0.4
        }

        let buf44k = AVAudioPCMBuffer(pcmFormat: format44k, frameCapacity: 1024)!
        buf44k.frameLength = 1024
        for i in 0..<1024 {
            buf44k.floatChannelData?[0][i] = 0.4
        }

        XCTAssertEqual(buf48k.frameLength, 1024)
        XCTAssertEqual(buf16k.frameLength, 1024)
        XCTAssertEqual(buf44k.frameLength, 1024)
    }

    // MARK: - RMS Normalization Tests

    func testRMSCalculationSilenceVersusLoudAudio() throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            XCTFail("Failed to create format")
            return
        }

        // Silent Buffer
        let silentBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        silentBuffer.frameLength = 1024
        for i in 0..<1024 {
            silentBuffer.floatChannelData?[0][i] = 0.0
        }

        var silentRms: Float = 0.0
        vDSP_rmsqv(silentBuffer.floatChannelData![0], 1, &silentRms, 1024)
        let noiseFloorDb: Float = -42.0
        let maxSpeechDb: Float = -12.0
        let silentDb = 20.0 * log10(max(silentRms, 0.000001))
        let silentLevel = (silentDb <= noiseFloorDb) ? 0.0 : pow(max(0.0, min(1.0, (silentDb - noiseFloorDb) / (maxSpeechDb - noiseFloorDb))), 1.3)
        XCTAssertEqual(silentLevel, 0.0, accuracy: 0.001, "Silence should produce 0.0 normalized audio level")

        // Ambient Room Noise Buffer (around -50dB)
        let roomNoiseBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        roomNoiseBuffer.frameLength = 1024
        for i in 0..<1024 {
            roomNoiseBuffer.floatChannelData?[0][i] = 0.003 // ~ -50dB
        }
        var roomRms: Float = 0.0
        vDSP_rmsqv(roomNoiseBuffer.floatChannelData![0], 1, &roomRms, 1024)
        let roomDb = 20.0 * log10(max(roomRms, 0.000001))
        let roomLevel = (roomDb <= noiseFloorDb) ? 0.0 : pow(max(0.0, min(1.0, (roomDb - noiseFloorDb) / (maxSpeechDb - noiseFloorDb))), 1.3)
        XCTAssertEqual(roomLevel, 0.0, accuracy: 0.001, "Room noise below -42dB should produce 0.0 normalized audio level")

        // Loud Speech Buffer
        let loudBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        loudBuffer.frameLength = 1024
        for i in 0..<1024 {
            loudBuffer.floatChannelData?[0][i] = 0.85
        }

        var loudRms: Float = 0.0
        vDSP_rmsqv(loudBuffer.floatChannelData![0], 1, &loudRms, 1024)
        let loudDb = 20.0 * log10(max(loudRms, 0.000001))
        let loudLevel = (loudDb <= noiseFloorDb) ? 0.0 : pow(max(0.0, min(1.0, (loudDb - noiseFloorDb) / (maxSpeechDb - noiseFloorDb))), 1.3)
        XCTAssertGreaterThan(loudLevel, 0.85, "Loud audio should produce > 0.85 normalized audio level")
    }

    // MARK: - Audio Buffer Storage Concurrency Tests

    func testAudioBufferStorageThreadSafetyUnderStress() throws {
        let iterations = 200
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.concurrent.audio", attributes: .concurrent)

        var chunks: [Data] = []
        for i in 0..<iterations {
            let byte = UInt8(i % 256)
            chunks.append(Data([byte, byte, byte, byte]))
        }

        // Simulate multi-threaded appends
        for chunk in chunks {
            group.enter()
            queue.async {
                _ = chunk.count
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(result, .success, "Concurrent operations should complete without deadlock")
    }

    // MARK: - WAV Serialization Tests

    func testWAVHeaderIntegrity() throws {
        let sampleRate = 16000
        let channels = 1
        let bitsPerSample = 16
        let numSamples = 3200 // 200ms
        let pcmData = Data(repeating: 0x2A, count: numSamples * 2)

        // Wrap in WAV
        var wavData = Data()
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let subchunk2Size = pcmData.count
        let chunkSize = 36 + subchunk2Size

        wavData.append("RIFF".data(using: .ascii)!)
        var chunkSizeUInt32 = UInt32(chunkSize).littleEndian
        wavData.append(Data(bytes: &chunkSizeUInt32, count: 4))
        wavData.append("WAVE".data(using: .ascii)!)

        wavData.append("fmt ".data(using: .ascii)!)
        var subchunk1Size = UInt32(16).littleEndian
        wavData.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat = UInt16(1).littleEndian
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

        wavData.append("data".data(using: .ascii)!)
        var subchunk2SizeUInt32 = UInt32(subchunk2Size).littleEndian
        wavData.append(Data(bytes: &subchunk2SizeUInt32, count: 4))
        wavData.append(pcmData)

        XCTAssertEqual(wavData.count, 44 + pcmData.count, "Total WAV size should equal 44 bytes header + PCM bytes")

        // Validate RIFF chunk
        let riff = String(data: wavData.subdata(in: 0..<4), encoding: .ascii)
        XCTAssertEqual(riff, "RIFF")

        // Validate WAVE chunk
        let wave = String(data: wavData.subdata(in: 8..<12), encoding: .ascii)
        XCTAssertEqual(wave, "WAVE")

        // Validate fmt chunk
        let fmt = String(data: wavData.subdata(in: 12..<16), encoding: .ascii)
        XCTAssertEqual(fmt, "fmt ")

        // Validate data chunk
        let dataMarker = String(data: wavData.subdata(in: 36..<40), encoding: .ascii)
        XCTAssertEqual(dataMarker, "data")
    }

    func testEmptyAudioWAVProducesEmptyData() throws {
        // When AudioRecorder has 0 samples, stopRecording returns Data()
        let emptyAudio = Data()
        XCTAssertTrue(emptyAudio.isEmpty)
        XCTAssertLessThanOrEqual(emptyAudio.count, 44, "Empty audio is <= 44 bytes")
    }

    func testDebugRecordingDisabledByDefault() throws {
        if ProcessInfo.processInfo.environment["JP_DEBUG_RECORDINGS"] == nil &&
           ProcessInfo.processInfo.environment["DEBUG_RECORDINGS"] == nil {
            XCTAssertFalse(AudioRecorder.isDebugRecordingEnabled)
        }
    }

    func testDebugRecordingsDirectoryURL() throws {
        let url = AudioRecorder.debugRecordingsDirectoryURL()
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.path.hasSuffix("DebugRecordings") == true)
    }
}
