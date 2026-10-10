import Foundation

/// Events emitted during a live transcription WebSocket session.
public enum LiveTranscriptEvent: Equatable, Sendable {
    /// Speculative partial hypothesis for the currently active utterance.
    case interim(String)
    /// Authoritative finalized transcript for the completed utterance/segment.
    case final(String)
    /// WebSocket setup completed and ready to stream audio.
    case setupComplete
    /// Server signaled that the current turn is complete.
    case turnComplete
}

/// Manages a real-time bidirectional streaming transcription session with `gemini-3.5-transcribe-live`
/// over the Gemini Live API (`BidiGenerateContent` WebSocket).
public actor GeminiLiveTranscribeSession {
    private static let wsEndpoint = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    private let apiKey: String
    private let mode: DictationMode
    private let customVocabulary: String?
    private let urlSession: URLSession

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var isSetupComplete: Bool = false
    private var isFinishing: Bool = false
    private var isClosed: Bool = false
    private var hasPendingUtterance: Bool = false
    private var hasReceivedFinal: Bool = false
    private var preSetupAudioQueue: [Data] = []

    private var eventContinuation: AsyncThrowingStream<LiveTranscriptEvent, Error>.Continuation?
    private var finishContinuation: CheckedContinuation<Void, Never>?

    public init(apiKey: String,
                mode: DictationMode,
                customVocabulary: String? = nil,
                urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.mode = mode
        self.customVocabulary = customVocabulary
        self.urlSession = urlSession
    }

    /// Starts the WebSocket connection, sends the initial setup configuration,
    /// and returns an async stream of `LiveTranscriptEvent`s.
    public func start() throws -> AsyncThrowingStream<LiveTranscriptEvent, Error> {
        guard !apiKey.isEmpty else {
            throw TranscribeError.missingAPIKey
        }

        var components = URLComponents(string: Self.wsEndpoint)
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else {
            throw TranscribeError.invalidResponse
        }

        let task = urlSession.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        let stream = AsyncThrowingStream<LiveTranscriptEvent, Error> { continuation in
            self.eventContinuation = continuation
        }

        // Send initial setup message immediately after opening the WebSocket task
        Task {
            await self.sendSetupMessage()
        }

        // Start background receive loop
        self.receiveTask = Task {
            await self.receiveLoop()
        }

        return stream
    }

    /// Enqueues or immediately sends a 16kHz 16-bit mono PCM audio chunk.
    public func sendAudioChunk(_ pcmData: Data) async {
        guard !isClosed, !isFinishing, !pcmData.isEmpty else { return }

        if !isSetupComplete {
            preSetupAudioQueue.append(pcmData)
            return
        }

        await sendAudioPayload(pcmData)
    }

    /// Signals end of speech (`audioStreamEnd: true`), flushes any buffered audio,
    /// and waits briefly for the server to emit the finalized transcript before closing.
    public func finishAudioStream(timeoutSeconds: TimeInterval = 2.0) async {
        guard !isClosed, !isFinishing else { return }
        isFinishing = true

        // If setup hasn't completed yet, wait briefly for it so queued audio can flush
        if !isSetupComplete {
            for _ in 0..<15 {
                if isSetupComplete || isClosed { break }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }

        // Flush any remaining queued chunks
        if isSetupComplete && !preSetupAudioQueue.isEmpty {
            let queued = preSetupAudioQueue
            preSetupAudioQueue.removeAll()
            for chunk in queued {
                await sendAudioPayload(chunk)
            }
        }

        // Send audioStreamEnd signal for Hybrid VAD fast finalization
        if let task = webSocketTask, !isClosed {
            if let data = try? JSONSerialization.data(withJSONObject: Self.buildAudioStreamEndPayload()),
               let jsonString = String(data: data, encoding: .utf8) {
                try? await task.send(.string(jsonString))
            }
        }

        // Wait for the final inputTranscription / turnComplete or until timeout elapses.
        // If an utterance was already finalized by server VAD during a pause before stopRecording()
        // and no new interim speech is pending, use a short grace window instead of waiting the full timeout.
        if !isClosed {
            let effectiveTimeout = (hasReceivedFinal && !hasPendingUtterance)
                ? min(timeoutSeconds, 0.3)
                : timeoutSeconds
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self.waitForFinalTurn()
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(effectiveTimeout * 1_000_000_000))
                    await self.resumeFinishWaitIfNeeded()
                }
                await group.next()
                group.cancelAll()
            }
        }

        close()
    }

    /// Cancels and closes the WebSocket session immediately.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        preSetupAudioQueue.removeAll()
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        resumeFinishWaitIfNeeded()
        eventContinuation?.finish()
        eventContinuation = nil
    }

    // MARK: - Internal WebSocket Mechanics

    private func waitForFinalTurn() async {
        if isClosed { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if isClosed {
                continuation.resume()
            } else {
                self.finishContinuation = continuation
            }
        }
    }

    private func resumeFinishWaitIfNeeded() {
        if let cont = finishContinuation {
            finishContinuation = nil
            cont.resume()
        }
    }

    private func sendSetupMessage() async {
        guard let task = webSocketTask, !isClosed else { return }
        let payload = Self.buildSetupPayload(mode: mode, customVocabulary: customVocabulary)
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let jsonString = String(data: data, encoding: .utf8) else { return }
            try await task.send(.string(jsonString))
        } catch {
            if !isClosed {
                eventContinuation?.finish(throwing: TranscribeError.networkError(error.localizedDescription))
                close()
            }
        }
    }

    private func sendAudioPayload(_ pcmData: Data) async {
        guard let task = webSocketTask, !isClosed else { return }
        let payload = Self.buildAudioChunkPayload(pcmData: pcmData)
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let jsonString = String(data: data, encoding: .utf8) else { return }
            try await task.send(.string(jsonString))
        } catch {
            print("[DEBUG-LIVE] Failed to send audio chunk: \(error.localizedDescription)")
        }
    }

    private func markSetupCompleteAndFlushQueue() async {
        guard !isSetupComplete else { return }
        isSetupComplete = true
        eventContinuation?.yield(.setupComplete)

        guard !preSetupAudioQueue.isEmpty else { return }
        let queued = preSetupAudioQueue
        preSetupAudioQueue.removeAll()
        for chunk in queued {
            if isClosed { break }
            await sendAudioPayload(chunk)
        }
    }

    private func receiveLoop() async {
        while !isClosed, let task = webSocketTask {
            do {
                let message = try await task.receive()
                let rawData: Data?
                switch message {
                case .string(let text):
                    rawData = text.data(using: .utf8)
                case .data(let data):
                    rawData = data
                @unknown default:
                    rawData = nil
                }

                guard let data = rawData else { continue }
                let events = try Self.parseServerEvents(from: data)

                for event in events {
                    switch event {
                    case .setupComplete:
                        await markSetupCompleteAndFlushQueue()
                    case .interim(let text):
                        hasPendingUtterance = true
                        eventContinuation?.yield(.interim(text))
                    case .final(let text):
                        hasPendingUtterance = false
                        hasReceivedFinal = true
                        eventContinuation?.yield(.final(text))
                        if isFinishing {
                            // Give a tiny window for any trailing events, then complete
                            resumeFinishWaitIfNeeded()
                        }
                    case .turnComplete:
                        hasPendingUtterance = false
                        eventContinuation?.yield(.turnComplete)
                        if isFinishing {
                            resumeFinishWaitIfNeeded()
                        }
                    }
                }
            } catch {
                if !isClosed && !isFinishing {
                    eventContinuation?.finish(throwing: TranscribeError.networkError(error.localizedDescription))
                }
                close()
                break
            }
        }
    }

    // MARK: - Pure Protocol Builders & Parsers (Testable)

    /// Builds the `BidiGenerateContentSetup` payload for `gemini-3.5-transcribe-live`.
    public static func buildSetupPayload(mode: DictationMode, customVocabulary: String?) -> [String: Any] {
        let modeString = (mode == .rawVerbatim) ? "VERBATIM" : "SMART"
        var transcriptionConfig: [String: Any] = [
            "languageCodes": [String](),
            "mode": modeString
        ]

        let vocabulary = parseVocabulary(customVocabulary)
        if !vocabulary.isEmpty {
            transcriptionConfig["customVocabulary"] = vocabulary
        }

        return [
            "setup": [
                "model": "models/\(TranscribeModel.gemini35TranscribeLive.rawValue)",
                "generationConfig": [
                    "responseModalities": ["TEXT"]
                ],
                "inputAudioTranscription": transcriptionConfig
            ]
        ]
    }

    /// Builds a `BidiGenerateContentRealtimeInput` message containing base64 16kHz PCM audio.
    public static func buildAudioChunkPayload(pcmData: Data) -> [String: Any] {
        return [
            "realtimeInput": [
                "audio": [
                    "data": pcmData.base64EncodedString(),
                    "mimeType": "audio/pcm;rate=16000"
                ]
            ]
        ]
    }

    /// Builds the `audioStreamEnd` signal for Hybrid VAD fast turn finalization.
    public static func buildAudioStreamEndPayload() -> [String: Any] {
        return [
            "realtimeInput": [
                "audioStreamEnd": true
            ]
        ]
    }

    /// Parses a JSON server message from `BidiGenerateContentServerMessage` into structured `LiveTranscriptEvent`s.
    public static func parseServerEvents(from data: Data) throws -> [LiveTranscriptEvent] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscribeError.invalidResponse
        }

        // Check for API error frame
        if let errorObj = json["error"] as? [String: Any] {
            let code = errorObj["code"] as? Int ?? 0
            let message = errorObj["message"] as? String ?? "Unknown Live API error"
            throw TranscribeError.apiError(statusCode: code, message: message)
        }

        var events: [LiveTranscriptEvent] = []

        // 1. Setup completion acknowledgement
        if json["setupComplete"] != nil || json["setup_complete"] != nil {
            events.append(.setupComplete)
        }

        // 2. Server content (camelCase or snake_case)
        if let serverContent = (json["serverContent"] as? [String: Any]) ?? (json["server_content"] as? [String: Any]) {
            // 2a. Interim partial hypothesis
            if let interimObj = (serverContent["interimInputTranscription"] as? [String: Any])
                ?? (serverContent["interim_input_transcription"] as? [String: Any]),
               let interimText = interimObj["text"] as? String,
               !interimText.isEmpty {
                events.append(.interim(interimText))
            }

            // 2b. Finalized authoritative utterance transcript
            if let finalObj = (serverContent["inputTranscription"] as? [String: Any])
                ?? (serverContent["input_transcription"] as? [String: Any]),
               let finalText = finalObj["text"] as? String,
               !finalText.isEmpty {
                events.append(.final(finalText))
            }

            // 2c. Fallback: modelTurn text parts if emitted directly by the model
            if events.isEmpty,
               let modelTurn = (serverContent["modelTurn"] as? [String: Any]) ?? (serverContent["model_turn"] as? [String: Any]),
               let parts = modelTurn["parts"] as? [[String: Any]] {
                var combined = ""
                for part in parts {
                    if let text = part["text"] as? String {
                        combined += text
                    }
                }
                if !combined.isEmpty {
                    events.append(.final(combined))
                }
            }

            // 2d. Turn / generation completion signal
            let isTurnComplete = (serverContent["turnComplete"] as? Bool)
                ?? (serverContent["turn_complete"] as? Bool)
                ?? (serverContent["generationComplete"] as? Bool)
                ?? (serverContent["generation_complete"] as? Bool)
                ?? false
            if isTurnComplete {
                events.append(.turnComplete)
            }
        }

        return events
    }

    private static func parseVocabulary(_ raw: String?) -> [String] {
        guard let raw = raw else { return [] }
        return raw
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
