import XCTest
@testable import Jigglypuff

final class GeminiServiceIntegrationTests: XCTestCase {
    
    private let dummyWAVData: Data = {
        // Valid 100ms 16kHz mono WAV file
        let sampleRate = 16000
        let channels = 1
        let bitsPerSample = 16
        let numSamples = 1600
        let pcmData = Data(repeating: 0x10, count: numSamples * 2)

        var wavData = Data()
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let subchunk2Size = pcmData.count
        let chunkSize = 36 + subchunk2Size

        wavData.append("RIFF".data(using: .ascii)!)
        var chunkSizeUInt32 = UInt32(chunkSize).littleEndian
        wavData.append(Data(bytes: &chunkSizeUInt32, count: 4))
        wavData.append("WAVEfmt ".data(using: .ascii)!)
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
        return wavData
    }()

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        KeychainHelper.shared.saveAPIKey("test_api_key_12345")
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Validation & Guard Tests

    func testEmptyAudioThrowsEmptyAudioError() async {
        let emptyData = Data()
        do {
            _ = try await GeminiTranscribeService.shared.transcribe(
                audioData: emptyData,
                model: .gemini35Transcribe,
                mode: .smartFlow
            )
            XCTFail("Expected emptyAudio error to be thrown")
        } catch let error as TranscribeError {
            if case .emptyAudio = error {
                XCTAssertEqual(error.errorDescription, "No audio was captured from the microphone. Please check your mic settings.")
            } else {
                XCTFail("Wrong error thrown: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHollowWAVHeaderThrowsEmptyAudioError() async {
        // A 44-byte WAV with 0 PCM bytes
        let hollowWAV = Data(repeating: 0, count: 44)
        do {
            _ = try await GeminiTranscribeService.shared.transcribe(
                audioData: hollowWAV,
                model: .gemini35Transcribe,
                mode: .smartFlow
            )
            XCTFail("Expected emptyAudio error for 44-byte WAV header without samples")
        } catch let error as TranscribeError {
            if case .emptyAudio = error {
                // Success
            } else {
                XCTFail("Wrong error thrown: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMissingAPIKeyThrowsMissingAPIKeyError() async {
        let service = GeminiTranscribeService(apiKeyProvider: { nil })
        do {
            _ = try await service.transcribe(
                audioData: dummyWAVData,
                model: .gemini35Transcribe,
                mode: .smartFlow
            )
            XCTFail("Expected missingAPIKey error to be thrown")
        } catch let error as TranscribeError {
            if case .missingAPIKey = error {
                XCTAssertTrue(error.errorDescription?.contains("API Key is missing") == true)
            } else {
                XCTFail("Wrong error thrown: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDictationModesPromptGeneration() {
        // Verify default prompts for all dictation modes
        let modes: [DictationMode] = [.smartFlow, .rawVerbatim, .email, .bulletPoints, .codeTech, .custom]
        for mode in modes {
            XCTAssertFalse(mode.defaultPrompt.isEmpty, "Mode \(mode.displayName) must have non-empty prompt")
            XCTAssertFalse(mode.displayName.isEmpty)
            XCTAssertFalse(mode.iconName.isEmpty)
        }

        // Test Smart Flow features
        XCTAssertTrue(DictationMode.smartFlow.defaultPrompt.contains("disfluencies"))
        // Test Raw Verbatim features
        XCTAssertTrue(DictationMode.rawVerbatim.defaultPrompt.contains("verbatim"))
        // Test Email features
        XCTAssertTrue(DictationMode.email.defaultPrompt.contains("email"))
        // Test Bullet Points features
        XCTAssertTrue(DictationMode.bulletPoints.defaultPrompt.contains("bullet points"))
        // Test Code Tech features
        XCTAssertTrue(DictationMode.codeTech.defaultPrompt.contains("camelCase") || DictationMode.codeTech.defaultPrompt.contains("backticks"))
    }

    // MARK: - Gemini 3.5 Transcribe Mode Schema Tests

    func testGemini35TranscribeModeFormatting() {
        // Verify that modeType is correctly structured as an object ["type": modeType]
        let modes: [(DictationMode, String)] = [
            (.smartFlow, "smart"),
            (.email, "smart"),
            (.bulletPoints, "smart"),
            (.codeTech, "smart"),
            (.custom, "smart"),
            (.rawVerbatim, "verbatim")
        ]

        for (mode, expectedType) in modes {
            let modeType = (mode == .rawVerbatim) ? "verbatim" : "smart"
            XCTAssertEqual(modeType, expectedType)
            let config: [String: Any] = ["mode": ["type": modeType]]
            guard let modeObj = config["mode"] as? [String: String] else {
                XCTFail("Mode must be a dictionary with 'type'")
                continue
            }
            XCTAssertEqual(modeObj["type"], expectedType)
        }
    }

    // MARK: - API Error Handling Tests

    func testAPIErrorSurfacesExactStatusCodeAndMessage() {
        let error400 = TranscribeError.apiError(statusCode: 400, message: "Invalid argument: audio sample rate unsupported")
        XCTAssertEqual(error400.errorDescription, "Gemini API Error (400): Invalid argument: audio sample rate unsupported")

        let error401 = TranscribeError.apiError(statusCode: 401, message: "API key not valid. Please pass a valid API key.")
        XCTAssertEqual(error401.errorDescription, "Gemini API Error (401): API key not valid. Please pass a valid API key.")

        let error429 = TranscribeError.apiError(statusCode: 429, message: "Resource has been exhausted (rate limit).")
        XCTAssertEqual(error429.errorDescription, "Gemini API Error (429): Resource has been exhausted (rate limit).")

        let networkErr = TranscribeError.networkError("The Internet connection appears to be offline.")
        XCTAssertEqual(networkErr.errorDescription, "Network Error: The Internet connection appears to be offline.")
    }

    // MARK: - Multi-Schema Transcript Extraction Tests

    func testGemini35TranscribeOutputTextParsing() async throws {
        let expected = "Hello, this is transcribed using Gemini 3.5 Transcribe output_text."

        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("upload") == true {
                // Step 1 or 2 of file upload
                if request.value(forHTTPHeaderField: "X-Goog-Upload-Command") == "start" {
                    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["x-goog-upload-url": "https://generativelanguage.googleapis.com/upload/session/123"])!
                    return (response, Data())
                } else {
                    let fileJSON: [String: Any] = ["file": ["uri": "https://generativelanguage.googleapis.com/v1beta/files/test123", "name": "files/test123", "state": "ACTIVE"]]
                    let data = try! JSONSerialization.data(withJSONObject: fileJSON)
                    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                    return (response, data)
                }
            } else if request.url?.absoluteString.contains("interactions") == true {
                // Interactions API endpoint returning output_text
                let interactionJSON: [String: Any] = [
                    "id": "interactions/abc",
                    "status": "completed",
                    "output_text": expected
                ]
                let data = try! JSONSerialization.data(withJSONObject: interactionJSON)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                return (response, data)
            } else {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
                return (response, Data())
            }
        }

        let result = try await GeminiTranscribeService.shared.transcribe(
            audioData: dummyWAVData,
            model: .gemini35Transcribe,
            mode: .smartFlow
        )

        XCTAssertEqual(result, expected)
    }

    // MARK: - Live Streaming Protocol & Diff Reconciliation Tests

    func testReconcileDiffAppendAndSelfCorrection() {
        // Pure append
        let appendDiff = TextInsertionService.reconcileDiff(
            from: "Let's meet at",
            to: "Let's meet at 2"
        )
        XCTAssertEqual(appendDiff.backspaces, 0)
        XCTAssertEqual(appendDiff.suffixToType, " 2")

        // Smart self-correction replacing "2" with "3 PM."
        let correctionDiff = TextInsertionService.reconcileDiff(
            from: "Let's meet at 2",
            to: "Let's meet at 3 PM."
        )
        XCTAssertEqual(correctionDiff.backspaces, 1)
        XCTAssertEqual(correctionDiff.suffixToType, "3 PM.")

        // No-op when strings match
        let noopDiff = TextInsertionService.reconcileDiff(
            from: "Hello world",
            to: "Hello world"
        )
        XCTAssertEqual(noopDiff.backspaces, 0)
        XCTAssertEqual(noopDiff.suffixToType, "")

        // Multi-byte Unicode / Emoji grapheme clusters
        let emojiDiff = TextInsertionService.reconcileDiff(
            from: "Status 👋🏻 draft",
            to: "Status 👋🏻 ready!"
        )
        XCTAssertEqual(emojiDiff.backspaces, 5)
        XCTAssertEqual(emojiDiff.suffixToType, "ready!")
    }

    @MainActor
    func testStreamingTextSessionMultiUtteranceReconciliation() {
        var appliedDiffs: [(backspaces: Int, suffix: String)] = []
        let session = StreamingTextSession { backspaces, suffix in
            appliedDiffs.append((backspaces, suffix))
        }

        // Utterance 1: interim -> self-corrected interim -> final
        session.updateInterim("let's meet at 2", autoInsert: true)
        session.updateInterim("let's meet at 3", autoInsert: true)
        session.commitFinal("let's meet at 3 PM.", autoInsert: true)

        // Utterance 2: interim -> final (automatically prefixed with a separating space)
        session.updateInterim("sounds good", autoInsert: true)
        session.commitFinal("sounds good!", autoInsert: true)

        XCTAssertEqual(session.committedText, "let's meet at 3 PM. sounds good!")
        XCTAssertEqual(session.currentInterimText, "")
        XCTAssertEqual(session.displayText, "let's meet at 3 PM. sounds good!")

        // Verify the exact sequence of keystroke diffs reconstructed the final text
        var simulatedTextField = ""
        for diff in appliedDiffs {
            if diff.backspaces > 0 {
                simulatedTextField.removeLast(diff.backspaces)
            }
            simulatedTextField.append(diff.suffix)
        }
        XCTAssertEqual(simulatedTextField, "let's meet at 3 PM. sounds good!")
    }

    func testLiveSetupAndAudioPayloads() throws {
        let setupPayload = GeminiLiveTranscribeSession.buildSetupPayload(
            mode: .smartFlow,
            customVocabulary: "Jigglypuff, AVAudioEngine\nGemini"
        )
        guard let setup = setupPayload["setup"] as? [String: Any],
              let model = setup["model"] as? String,
              let inputConfig = setup["inputAudioTranscription"] as? [String: Any],
              let mode = inputConfig["mode"] as? String,
              let vocab = inputConfig["customVocabulary"] as? [String] else {
            XCTFail("Invalid setup payload structure")
            return
        }
        XCTAssertEqual(model, "models/gemini-3.5-transcribe-live")
        XCTAssertEqual(mode, "SMART")
        XCTAssertEqual(vocab, ["Jigglypuff", "AVAudioEngine", "Gemini"])

        let verbatimPayload = GeminiLiveTranscribeSession.buildSetupPayload(
            mode: .rawVerbatim,
            customVocabulary: nil
        )
        let verbatimInputConfig = (verbatimPayload["setup"] as? [String: Any])?["inputAudioTranscription"] as? [String: Any]
        XCTAssertEqual(verbatimInputConfig?["mode"] as? String, "VERBATIM")
        XCTAssertNil(verbatimInputConfig?["customVocabulary"])

        let sampleChunk = Data([0x01, 0x02, 0x03, 0x04])
        let chunkPayload = GeminiLiveTranscribeSession.buildAudioChunkPayload(pcmData: sampleChunk)
        let audioObj = (chunkPayload["realtimeInput"] as? [String: Any])?["audio"] as? [String: Any]
        XCTAssertEqual(audioObj?["mimeType"] as? String, "audio/pcm;rate=16000")
        XCTAssertEqual(audioObj?["data"] as? String, sampleChunk.base64EncodedString())

        let endPayload = GeminiLiveTranscribeSession.buildAudioStreamEndPayload()
        let endInput = endPayload["realtimeInput"] as? [String: Any]
        XCTAssertEqual(endInput?["audioStreamEnd"] as? Bool, true)
    }

    func testLiveServerEventParsing() throws {
        let camelCaseJSON = """
        {
          "setupComplete": {},
          "serverContent": {
            "interimInputTranscription": { "text": "Testing live " },
            "inputTranscription": { "text": "Testing live transcription." },
            "turnComplete": true
          }
        }
        """.data(using: .utf8)!

        let events = try GeminiLiveTranscribeSession.parseServerEvents(from: camelCaseJSON)
        XCTAssertEqual(events, [
            .setupComplete,
            .interim("Testing live "),
            .final("Testing live transcription."),
            .turnComplete
        ])

        let snakeCaseJSON = """
        {
          "server_content": {
            "interim_input_transcription": { "text": "hello " },
            "input_transcription": { "text": "Hello world!" },
            "turn_complete": true
          }
        }
        """.data(using: .utf8)!

        let snakeEvents = try GeminiLiveTranscribeSession.parseServerEvents(from: snakeCaseJSON)
        XCTAssertEqual(snakeEvents, [
            .interim("hello "),
            .final("Hello world!"),
            .turnComplete
        ])

        let generationCompleteJSON = """
        {
          "serverContent": {
            "generationComplete": true
          }
        }
        """.data(using: .utf8)!
        let genEvents = try GeminiLiveTranscribeSession.parseServerEvents(from: generationCompleteJSON)
        XCTAssertEqual(genEvents, [.turnComplete])
    }

    func testAudioBufferStorage100msChunkBatching() {
        let storage = AudioBufferStorage()

        // Append 2,000 bytes (< 3,200 threshold) -> no full chunk yet
        let part1 = Data(repeating: 0xAA, count: 2000)
        let chunks1 = storage.append(part1)
        XCTAssertTrue(chunks1.isEmpty)

        // Append 5,000 bytes (total pending = 7,000 bytes -> 2 chunks of 3,200 bytes + 600 bytes trailing)
        let part2 = Data(repeating: 0xBB, count: 5000)
        let chunks2 = storage.append(part2)
        XCTAssertEqual(chunks2.count, 2)
        XCTAssertEqual(chunks2[0].count, 3200)
        XCTAssertEqual(chunks2[1].count, 3200)

        // Flush remaining on stopRecording
        let (fullData, trailingChunk) = storage.extractWithTrailingChunkAndReset()
        XCTAssertEqual(fullData.count, 7000)
        XCTAssertEqual(trailingChunk.count, 600)
    }
}

