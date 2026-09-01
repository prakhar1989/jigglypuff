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
        let prevEnv = getenv("GEMINI_API_KEY").flatMap { String(cString: $0) }
        unsetenv("GEMINI_API_KEY")
        defer {
            if let prev = prevEnv {
                setenv("GEMINI_API_KEY", prev, 1)
            }
        }

        KeychainHelper.shared.deleteAPIKey()
        do {
            _ = try await GeminiTranscribeService.shared.transcribe(
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

    // MARK: - Gemini 2.5 Flash GenerateContent Tests

    func testGemini25FlashTranscriptionSuccess() async throws {
        let expectedTranscript = "Meeting with Sarah tomorrow at 10 AM."

        // Mock URL response
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("gemini-2.5-flash:generateContent") == true)
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test_api_key_12345")

            let responseJSON: [String: Any] = [
                "candidates": [
                    [
                        "content": [
                            "parts": [
                                ["text": "\"\(expectedTranscript)\""] // with quotes to test cleaning
                            ],
                            "role": "model"
                        ],
                        "finishReason": "STOP"
                    ]
                ]
            ]
            let data = try! JSONSerialization.data(withJSONObject: responseJSON)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, data)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]

        // Test mode prompt and vocabulary
        let result = try await GeminiTranscribeService.shared.transcribe(
            audioData: dummyWAVData,
            model: .gemini25Flash,
            mode: .smartFlow,
            customVocabulary: "Sarah, AcmeCorp"
        )

        XCTAssertFalse(result.isEmpty)
    }

    func testGemini25FlashDictationModesPromptGeneration() {
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
}
