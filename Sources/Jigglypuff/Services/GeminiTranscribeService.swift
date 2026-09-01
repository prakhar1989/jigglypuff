import Foundation

/// Errors that can occur during Gemini transcription
public enum TranscribeError: LocalizedError, Sendable {
    case missingAPIKey
    case emptyAudio
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API Key is missing. Please add your key in Settings or set GEMINI_API_KEY."
        case .emptyAudio:
            return "No audio was captured from the microphone. Please check your mic settings."
        case .invalidResponse:
            return "Failed to parse transcription response from Gemini."
        case .apiError(let code, let msg):
            return "Gemini API Error (\(code)): \(msg)"
        case .networkError(let errorMsg):
            return "Network Error: \(errorMsg)"
        }
    }
}

/// Service handling transcription requests with Gemini.
///
/// Two API paths are supported:
/// - `gemini-3.5-transcribe`: Google's dedicated speech-to-text model, exposed via the
///   Interactions API (`POST /v1beta/interactions`). Audio is uploaded through the Files API
///   (resumable upload) and referenced by URI. Smart transcription (disfluency removal,
///   self-correction resolution, formatting) and custom vocabulary are first-class
///   configuration options of this model.
/// - `gemini-2.5-flash`: general multimodal model via `:generateContent` with inline base64
///   audio. This path is prompt-driven, so the rewriting dictation modes (Email,
///   Bullet Points, Code, Custom) only take effect here.
public final class GeminiTranscribeService: Sendable {
    public static let shared = GeminiTranscribeService()

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    private let filesUploadURL = "https://generativelanguage.googleapis.com/upload/v1beta/files"

    private init() {}

    /// Transcribes audio data using the selected model.
    public func transcribe(audioData: Data,
                           model: TranscribeModel,
                           mode: DictationMode,
                           customPrompt: String? = nil,
                           customVocabulary: String? = nil) async throws -> String {
        // Standard WAV header is 44 bytes; require at least some PCM sample payload
        guard audioData.count > 44 else {
            throw TranscribeError.emptyAudio
        }

        guard let apiKey = KeychainHelper.shared.getAPIKey(), !apiKey.isEmpty else {
            throw TranscribeError.missingAPIKey
        }

        switch model {
        case .gemini35Transcribe:
            do {
                let result = try await transcribeWithInteractionsAPI(audioData: audioData,
                                                                     apiKey: apiKey,
                                                                     mode: mode,
                                                                     customVocabulary: customVocabulary)
                if !result.isEmpty {
                    return result
                }
                print("Jigglypuff: Interactions API returned empty transcript. Trying fallback to generateContent...")
            } catch {
                print("Jigglypuff: Interactions API error (\(error.localizedDescription)). Trying fallback to generateContent...")
            }
            return try await transcribeWithGenerateContent(audioData: audioData,
                                                           apiKey: apiKey,
                                                           model: .gemini25Flash,
                                                           mode: mode,
                                                           customPrompt: customPrompt,
                                                           customVocabulary: customVocabulary)

        case .gemini25Flash:
            return try await transcribeWithGenerateContent(audioData: audioData,
                                                           apiKey: apiKey,
                                                           model: model,
                                                           mode: mode,
                                                           customPrompt: customPrompt,
                                                           customVocabulary: customVocabulary)
        }
    }

    // MARK: - Gemini 3.5 Transcribe (Interactions API)

    private func transcribeWithInteractionsAPI(audioData: Data,
                                               apiKey: String,
                                               mode: DictationMode,
                                               customVocabulary: String?) async throws -> String {
        let file = try await uploadFile(audioData: audioData, apiKey: apiKey)
        // Best-effort cleanup; uploaded files otherwise persist for ~48 hours.
        defer { Task { try? await self.deleteFile(name: file.name, apiKey: apiKey) } }

        return try await createTranscriptionInteraction(fileURI: file.uri,
                                                        apiKey: apiKey,
                                                        mode: mode,
                                                        customVocabulary: customVocabulary)
    }

    /// Uploads WAV data via the Files API resumable upload protocol.
    /// Returns the file URI (used as interaction input) and its resource name (used for deletion).
    private func uploadFile(audioData: Data, apiKey: String) async throws -> (uri: String, name: String) {
        guard let startURL = URL(string: filesUploadURL) else {
            throw TranscribeError.invalidResponse
        }

        // 1. Start the resumable upload session; the session URL comes back in a header.
        var startRequest = URLRequest(url: startURL)
        startRequest.httpMethod = "POST"
        startRequest.timeoutInterval = 30
        startRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        startRequest.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        startRequest.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        startRequest.setValue("\(audioData.count)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        startRequest.setValue("audio/wav", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        startRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        startRequest.httpBody = try JSONSerialization.data(withJSONObject: ["file": ["display_name": "jiggypuff-dictation"]])

        let (_, startResponse) = try await URLSession.shared.data(for: startRequest)
        guard let startHTTP = startResponse as? HTTPURLResponse,
              (200...299).contains(startHTTP.statusCode),
              let sessionURLString = startHTTP.value(forHTTPHeaderField: "x-goog-upload-url"),
              let sessionURL = URL(string: sessionURLString) else {
            throw TranscribeError.invalidResponse
        }

        // 2. Upload the raw bytes and finalize the session.
        var uploadRequest = URLRequest(url: sessionURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.timeoutInterval = 120
        uploadRequest.setValue("\(audioData.count)", forHTTPHeaderField: "Content-Length")
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadRequest.httpBody = audioData

        let (uploadData, uploadResponse) = try await URLSession.shared.data(for: uploadRequest)
        guard let uploadHTTP = uploadResponse as? HTTPURLResponse else {
            throw TranscribeError.invalidResponse
        }
        guard (200...299).contains(uploadHTTP.statusCode) else {
            let msg = parseErrorMessage(data: uploadData) ?? "HTTP \(uploadHTTP.statusCode)"
            throw TranscribeError.apiError(statusCode: uploadHTTP.statusCode, message: msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: uploadData) as? [String: Any],
              let file = json["file"] as? [String: Any],
              let uri = file["uri"] as? String,
              let name = file["name"] as? String else {
            throw TranscribeError.invalidResponse
        }

        // 3. Small audio files are ACTIVE immediately; poll briefly if still processing.
        if (file["state"] as? String) == "PROCESSING" {
            try await waitForFileActive(name: name, apiKey: apiKey)
        }

        return (uri, name)
    }

    /// Polls the Files API until the uploaded file leaves the PROCESSING state.
    private func waitForFileActive(name: String, apiKey: String) async throws {
        guard let url = URL(string: "\(baseURL)/\(name)") else {
            throw TranscribeError.invalidResponse
        }

        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (json["state"] as? String) == "ACTIVE" {
                return
            }
        }

        throw TranscribeError.apiError(statusCode: 0, message: "Uploaded audio is still processing. Please try again.")
    }

    /// Runs interactions.create against the uploaded audio and returns the transcript text.
    private func createTranscriptionInteraction(fileURI: String,
                                                apiKey: String,
                                                mode: DictationMode,
                                                customVocabulary: String?) async throws -> String {
        guard let url = URL(string: "\(baseURL)/interactions") else {
            throw TranscribeError.invalidResponse
        }

        // "smart" applies disfluency removal/self-corrections/formatting;
        // verbatim preserves raw speech.
        let modeType = (mode == .rawVerbatim) ? "verbatim" : "smart"
        var transcriptionConfig: [String: Any] = ["mode": ["type": modeType]]

        let vocabulary = parseVocabulary(customVocabulary)
        if !vocabulary.isEmpty {
            transcriptionConfig["custom_vocabulary"] = vocabulary
        }

        let requestBody: [String: Any] = [
            "model": TranscribeModel.gemini35Transcribe.rawValue,
            "input": [
                [
                    "type": "audio",
                    "uri": fileURI,
                    "mime_type": "audio/wav"
                ]
            ],
            "generation_config": [
                "transcription_config": transcriptionConfig
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscribeError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = parseErrorMessage(data: data) ?? "HTTP \(httpResponse.statusCode)"
            throw TranscribeError.apiError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        // Response shape:
        // { "id": "interactions/...", "status": "completed",
        //   "steps": [ { "type": "model_output",
        //                "content": [ { "type": "text", "text": "...", "annotations": [...] } ] } ] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscribeError.invalidResponse
        }

        if let status = json["status"] as? String, status != "completed" {
            throw TranscribeError.apiError(statusCode: 0, message: "Transcription did not complete (status: \(status)).")
        }

        let transcript = extractTranscript(from: json)
        if transcript.isEmpty {
            print("Jigglypuff: Interaction response had empty transcript. JSON keys: \(json.keys.joined(separator: ", "))")
        }

        return cleanTranscriptionOutput(transcript)
    }

    /// Recursively and resiliently extracts transcribed text from any Gemini REST schema.
    private func extractTranscript(from json: [String: Any]) -> String {
        // 1. Direct output_text field (Gemini 3.5 Transcribe Interactions API standard)
        if let outputText = json["output_text"] as? String, !outputText.isEmpty {
            return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 2. Direct text / transcript / transcription fields
        if let text = json["text"] as? String, !text.isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let transcript = json["transcript"] as? String, !transcript.isEmpty {
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let transcription = json["transcription"] as? String, !transcription.isEmpty {
            return transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 3. Outputs array
        if let outputs = json["outputs"] as? [Any] {
            var combined = ""
            for output in outputs {
                if let str = output as? String {
                    combined += str
                } else if let dict = output as? [String: Any] {
                    if let text = dict["text"] as? String {
                        combined += text
                    } else if let content = dict["content"] as? String {
                        combined += content
                    }
                }
            }
            if !combined.isEmpty {
                return combined.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 4. Steps array
        if let steps = json["steps"] as? [[String: Any]] {
            var combined = ""
            for step in steps {
                if let contentList = step["content"] as? [[String: Any]] {
                    for part in contentList {
                        if let partText = part["text"] as? String {
                            combined += partText
                        }
                    }
                } else if let text = step["text"] as? String {
                    combined += text
                } else if let contentStr = step["content"] as? String {
                    combined += contentStr
                } else if let outputStr = step["output"] as? String {
                    combined += outputStr
                } else if let outputText = step["output_text"] as? String {
                    combined += outputText
                }
            }
            if !combined.isEmpty {
                return combined.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 5. Candidates array (generateContent style fallback)
        if let candidates = json["candidates"] as? [[String: Any]],
           let firstCandidate = candidates.first,
           let content = firstCandidate["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]] {
            var combined = ""
            for part in parts {
                if let text = part["text"] as? String {
                    combined += text
                }
            }
            if !combined.isEmpty {
                return combined.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return ""
    }

    /// Deletes an uploaded file from the Files API (best effort).
    private func deleteFile(name: String, apiKey: String) async throws {
        guard let url = URL(string: "\(baseURL)/\(name)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        _ = try await URLSession.shared.data(for: request)
    }

    // MARK: - Gemini 2.5 Flash (generateContent with inline audio)

    private func transcribeWithGenerateContent(audioData: Data,
                                               apiKey: String,
                                               model: TranscribeModel,
                                               mode: DictationMode,
                                               customPrompt: String?,
                                               customVocabulary: String?) async throws -> String {
        // Build prompt instructions
        let promptText = buildPrompt(mode: mode, customPrompt: customPrompt, customVocabulary: customVocabulary)
        let base64Audio = audioData.base64EncodedString()

        let urlString = "\(baseURL)/models/\(model.rawValue):generateContent"
        guard let url = URL(string: urlString) else {
            throw TranscribeError.invalidResponse
        }

        // Construct Gemini REST Payload
        let contentsParts: [[String: Any]] = [
            [
                "inline_data": [
                    "mime_type": "audio/wav",
                    "data": base64Audio
                ]
            ],
            [
                "text": promptText
            ]
        ]

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": contentsParts
                ]
            ],
            "generationConfig": [
                "temperature": 0.0,
                "maxOutputTokens": 2048
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscribeError.invalidResponse
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let errorMsg = parseErrorMessage(data: data) ?? "HTTP \(httpResponse.statusCode)"
            throw TranscribeError.apiError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        return try parseTranscriptionResponse(data: data)
    }

    // MARK: - Shared helpers

    /// Splits a free-form vocabulary string (comma- or newline-separated) into individual terms.
    private func parseVocabulary(_ raw: String?) -> [String] {
        guard let raw = raw else { return [] }
        return raw
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Constructs the prompt instruction combining dictation mode instructions and custom vocabulary
    private func buildPrompt(mode: DictationMode, customPrompt: String?, customVocabulary: String?) -> String {
        var baseInstruction = ""
        if mode == .custom, let custom = customPrompt, !custom.isEmpty {
            baseInstruction = custom
        } else {
            baseInstruction = mode.defaultPrompt
        }

        if let vocab = customVocabulary, !vocab.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseInstruction += "\n\nImportant specialized vocabulary and terminology: \(vocab)"
        }

        return baseInstruction
    }

    /// Parses Gemini generateContent JSON response
    private func parseTranscriptionResponse(data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscribeError.invalidResponse
        }

        let transcript = extractTranscript(from: json)
        guard !transcript.isEmpty else {
            // If candidates exists but was empty
            if json["candidates"] != nil {
                return ""
            }
            throw TranscribeError.invalidResponse
        }

        return cleanTranscriptionOutput(transcript)
    }

    /// Cleans up any surrounding markdown block quotes or accidental meta responses
    private func cleanTranscriptionOutput(_ text: String) -> String {
        var cleaned = text
        // If output is enclosed in quotes, strip them
        if (cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"")) ||
           (cleaned.hasPrefix("“") && cleaned.hasSuffix("”")) {
            cleaned = String(cleaned.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    /// Parses error message from Gemini API response
    private func parseErrorMessage(data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return String(data: data, encoding: .utf8)
        }
        return message
    }
}
