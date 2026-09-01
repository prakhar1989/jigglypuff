import XCTest
import AVFoundation
@testable import Jigglypuff

@MainActor
final class EndToEndSmokeTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()
        AppState.shared.state = .idle
        KeychainHelper.shared.saveAPIKey("test_smoke_api_key")
    }

    override func tearDown() async throws {
        AppState.shared.state = .idle
        MockURLProtocol.reset()
        try await super.tearDown()
    }

    func testFullDictationPipelineEndToEndSmokeTest() async throws {
        let appState = AppState.shared
        let settings = SettingsStore.shared
        settings.selectedModel = .gemini35Transcribe
        settings.selectedDictationMode = .smartFlow

        let expectedTranscribedText = "This is an end-to-end smoke test transcription."

        // 1. Mock Gemini file upload and Interactions API responses
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("upload") == true {
                if request.value(forHTTPHeaderField: "X-Goog-Upload-Command") == "start" {
                    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["x-goog-upload-url": "https://generativelanguage.googleapis.com/upload/session/123"])!
                    return (response, Data())
                }

                let fileJSON: [String: Any] = ["file": ["uri": "https://generativelanguage.googleapis.com/v1beta/files/test123", "name": "files/test123", "state": "ACTIVE"]]
                let data = try! JSONSerialization.data(withJSONObject: fileJSON)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                return (response, data)
            }

            let responseJSON: [String: Any] = [
                "id": "interactions/abc",
                "status": "completed",
                "output_text": expectedTranscribedText
            ]
            let data = try! JSONSerialization.data(withJSONObject: responseJSON)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, data)
        }

        // 2. Generate a valid 200ms audio sample
        let sampleRate = 16000
        let channels = 1
        let bitsPerSample = 16
        let numSamples = 3200
        let pcmData = Data(repeating: 0x30, count: numSamples * 2)

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

        // 3. Transcribe via GeminiTranscribeService
        let transcribed = try await GeminiTranscribeService.shared.transcribe(
            audioData: wavData,
            model: settings.selectedModel,
            mode: settings.selectedDictationMode
        )

        XCTAssertEqual(transcribed, expectedTranscribedText)

        // 4. Test Text Insertion and History Log
        let insertResult = TextInsertionService.shared.insertText(
            transcribed,
            autoInsert: false,
            copyToClipboardAlways: true
        )
        XCTAssertEqual(insertResult, .copiedToClipboardOnly)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), expectedTranscribedText)

        let historyItem = TranscriptionItem(
            text: transcribed,
            duration: 0.2,
            model: settings.selectedModel.displayName,
            mode: settings.selectedDictationMode.displayName,
            targetAppName: "TestRunner"
        )
        HistoryManager.shared.add(item: historyItem)
        XCTAssertEqual(HistoryManager.shared.items.first?.text, expectedTranscribedText)

        // 5. Update State
        appState.state = .success(text: transcribed)
        if case .success(let text) = appState.state {
            XCTAssertEqual(text, expectedTranscribedText)
        } else {
            XCTFail("Expected .success state")
        }
    }

    func testErrorHandlingEndToEndSmokeTest() async {
        let appState = AppState.shared

        // Test API Error handling
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("upload") == true,
               request.value(forHTTPHeaderField: "X-Goog-Upload-Command") == "start" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["x-goog-upload-url": "https://generativelanguage.googleapis.com/upload/session/123"])!
                return (response, Data())
            }

            let errorJSON: [String: Any] = [
                "error": [
                    "code": 400,
                    "message": "Invalid audio encoding: expected WAV PCM",
                    "status": "INVALID_ARGUMENT"
                ]
            ]
            let data = try! JSONSerialization.data(withJSONObject: errorJSON)
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, data)
        }

        let validWAV = Data(repeating: 0x01, count: 100) // Valid length > 44
        do {
            _ = try await GeminiTranscribeService.shared.transcribe(
                audioData: validWAV,
                model: .gemini35Transcribe,
                mode: .smartFlow
            )
            XCTFail("Expected API error")
        } catch let error as TranscribeError {
            if case .apiError(let code, let msg) = error {
                XCTAssertEqual(code, 400)
                XCTAssertTrue(msg.contains("Invalid audio encoding"))
                appState.state = .error(message: error.localizedDescription)
                if case .error(let stateMsg) = appState.state {
                    XCTAssertTrue(stateMsg.contains("Gemini API Error (400)"))
                }
            } else {
                XCTFail("Wrong TranscribeError type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
