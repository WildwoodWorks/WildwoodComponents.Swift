// AI service ported from @wildwood/core/src/ai/aiService.ts.

import Foundation

public final class AIService: Sendable {
    private let http: WildwoodHttpClient
    private let appId: String?

    public init(http: WildwoodHttpClient, appId: String? = nil) {
        self.http = http
        self.appId = appId
    }

    /// `timeout` overrides the default request timeout (seconds) for
    /// long-running generations — mirrors the JS RequestOptions.timeout.
    public func sendMessage(_ request: AIChatRequest, timeout: TimeInterval? = nil) async -> AIChatResponse {
        await postChat("api/ai/chat", request: request, timeout: timeout)
    }

    /// Send a message via the AI proxy endpoint — identical backing handler to
    /// `api/ai/chat`, but the canonical endpoint for AIProxyComponent usage.
    public func sendProxyMessage(_ request: AIChatRequest, timeout: TimeInterval? = nil) async -> AIChatResponse {
        await postChat("api/ai/proxy", request: request, timeout: timeout)
    }

    private func postChat(_ endpoint: String, request: AIChatRequest, timeout: TimeInterval? = nil) async -> AIChatResponse {
        do {
            // Endpoint arrives as a literal from the two callers above (parity-scanned there).
            return try await http.post(endpoint, body: request, timeout: timeout)
        } catch {
            return Self.parseErrorResponse(error)
        }
    }

    /// Send a message with a file attachment (Base64-encoded in the request body).
    public func sendMessageWithFile(_ request: AIChatRequest, fileData: Data, fileName: String, timeout: TimeInterval? = nil) async -> AIChatResponse {
        await sendMessage(Self.attachFile(to: request, fileData: fileData, fileName: fileName), timeout: timeout)
    }

    public func sendProxyMessageWithFile(_ request: AIChatRequest, fileData: Data, fileName: String, timeout: TimeInterval? = nil) async -> AIChatResponse {
        await sendProxyMessage(Self.attachFile(to: request, fileData: fileData, fileName: fileName), timeout: timeout)
    }

    private static func attachFile(to request: AIChatRequest, fileData: Data, fileName: String) -> AIChatRequest {
        var withFile = request
        withFile.fileBase64 = fileData.base64EncodedString()
        withFile.fileMediaType = mediaType(forFileName: fileName)
        withFile.fileName = fileName
        return withFile
    }

    /// Parse a structured API error body ({ error, limitCode, currentUsage, maxValue,
    /// unit, periodEnd, ... }) into a user-facing AIChatResponse, mirroring the JS SDK.
    static func parseErrorResponse(_ error: any Error) -> AIChatResponse {
        var response = AIChatResponse(createdAt: Date(), isError: true)

        let fallbackMessage = (error as? WildwoodError)?.message ?? error.localizedDescription

        guard let details = (error as? WildwoodError)?.details,
              let body = try? JSONSerialization.jsonObject(with: details) as? [String: Any] else {
            response.errorMessage = fallbackMessage.isEmpty
                ? "An error occurred while sending the message"
                : fallbackMessage
            return response
        }

        if let limitCode = body["limitCode"] as? String {
            response.errorCode = limitCode
        }

        if let errorText = body["error"] as? String {
            var message = errorText

            if let currentUsage = body["currentUsage"] as? NSNumber, let maxValue = body["maxValue"] as? NSNumber {
                let unit = body["unit"] as? String ?? "units"
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                let current = formatter.string(from: currentUsage) ?? currentUsage.stringValue
                let max = formatter.string(from: maxValue) ?? maxValue.stringValue
                message += " (\(current)/\(max) \(unit))"
            }

            if let periodEnd = body["periodEnd"] as? String, let periodEndDate = WildwoodJSON.parseDate(periodEnd) {
                message += ". Resets \(periodEndDate.formatted(date: .abbreviated, time: .omitted))"
            }

            response.errorMessage = message
            return response
        }

        if let statusMessage = body["statusMessage"] as? String {
            response.errorMessage = statusMessage
            return response
        }
        if let message = body["message"] as? String {
            response.errorMessage = message
            return response
        }

        response.errorMessage = fallbackMessage.isEmpty
            ? "An error occurred while sending the message"
            : fallbackMessage
        return response
    }

    // MARK: - Configurations

    public func getConfigurations(configurationType: String? = nil) async throws -> [AIConfiguration] {
        var query: [String] = []
        if let configurationType {
            query.append("configurationType=\(configurationType.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? configurationType)")
        }
        if let appId {
            query.append("requestedAppId=\(appId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? appId)")
        }
        let suffix = query.isEmpty ? "" : "?\(query.joined(separator: "&"))"
        return try await http.get("api/ai/configurations\(suffix)")
    }

    public func getConfiguration(configurationId: String) async -> AIConfiguration? {
        try? await http.get("api/ai/configurations/\(configurationId)")
    }

    // MARK: - Sessions

    public func createSession(configurationId: String, sessionName: String? = nil) async -> AISession? {
        struct CreateSessionDto: Encodable {
            let configurationId: String
            let sessionName: String
        }
        return try? await http.post(
            "api/ai/sessions",
            body: CreateSessionDto(configurationId: configurationId, sessionName: sessionName ?? "New Session")
        )
    }

    public func getSession(sessionId: String) async -> AISession? {
        try? await http.get("api/ai/sessions/\(sessionId)")
    }

    public func getSessions(configurationId: String? = nil) async -> [AISessionSummary] {
        let suffix = configurationId.map {
            "?configurationId=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0)"
        } ?? ""
        let data: [AISessionSummary]? = try? await http.get("api/ai/sessions\(suffix)")
        return data ?? []
    }

    public func endSession(sessionId: String) async -> Bool {
        do {
            try await http.postVoid("api/ai/sessions/\(sessionId)/end")
            return true
        } catch {
            return false
        }
    }

    public func deleteSession(sessionId: String) async -> Bool {
        do {
            try await http.deleteVoid("api/ai/sessions/\(sessionId)")
            return true
        } catch {
            return false
        }
    }

    public func renameSession(sessionId: String, newName: String) async -> Bool {
        struct RenameDto: Encodable {
            let newName: String
        }
        do {
            try await http.putVoid("api/ai/sessions/\(sessionId)/name", body: RenameDto(newName: newName))
            return true
        } catch {
            return false
        }
    }

    // MARK: - TTS

    public func getTTSVoices() async -> [TTSVoice] {
        let data: [TTSVoice]? = try? await http.get("api/tts/voices")
        return data ?? []
    }

    public func getTTSVoicesForConfiguration(configurationId: String) async -> [TTSVoice] {
        let data: [TTSVoice]? = try? await http.get("api/tts/voices/configuration/\(configurationId)")
        return data ?? []
    }

    public func synthesizeSpeech(
        text: String,
        voice: String,
        speed: Double = 1.0,
        configurationId: String? = nil
    ) async -> TTSSynthesisResult? {
        struct SynthesizeDto: Encodable {
            let text: String
            let voice: String
            let speed: Double
            let configurationId: String?
        }
        return try? await http.post(
            "api/tts/synthesize/base64",
            body: SynthesizeDto(text: text, voice: voice, speed: speed, configurationId: configurationId)
        )
    }

    // MARK: - Speech-to-text

    /// Transcribe a recorded clip server-side.
    ///
    /// The UI-free half of voice input: this package records nothing and asks for no microphone
    /// permission — the HOST captures the audio (`AVAudioRecorder`, typically `audio/m4a`) and
    /// hands the bytes over, so the usage strings stay in the host's Info.plist where the App
    /// Store expects them. iOS also offers on-device dictation in every text field for free, which
    /// is why `AIChatComponent` ships no microphone button; see the README's "Speech-to-text".
    ///
    /// Ported from `@wildwood/core`'s `AIService.transcribeAudio` and Blazor's
    /// `AIService.TranscribeAudioAsync`: multipart with the file part named `file` and a
    /// `speech.<ext>` filename, the part carrying the BARE media type (`audio/webm;codecs=opus`
    /// becomes `audio/webm` — a parameter is enough to make a strict media-type parser refuse the
    /// header, and the server ignores codecs anyway), and `configurationId`/`language` omitted
    /// when empty.
    ///
    /// IDIOM NOTE — a business failure is DATA, never a throw: no audio, a non-2xx, a refused
    /// format and a dead network all come back as a result whose `success` is false and whose
    /// `errorMessage` can be shown to the customer as it stands. The `throws` is there for ONE
    /// thing: task cancellation, which must not be flattened into "transcription failed" when the
    /// customer simply left the screen. Same shape as ``AppTierService/completeTierChange(appId:pendingChangeId:)``.
    ///
    /// - Parameters:
    ///   - audioData: The recorded bytes. Empty fails without a request.
    ///   - contentType: The recording's media type, with or without codec parameters.
    ///   - configurationId: The AI configuration to transcribe with; omitted from the form when
    ///     nil or empty.
    ///   - language: A BCP-47 hint (`en-US`); omitted from the form when nil or empty.
    /// - Throws: `CancellationError` only.
    public func transcribeAudio(
        audioData: Data,
        contentType: String,
        configurationId: String? = nil,
        language: String? = nil
    ) async throws -> SpeechTranscriptionResult {
        guard !audioData.isEmpty else {
            return SpeechTranscriptionResult(success: false, text: "", errorMessage: Self.noAudioMessage)
        }

        let bareType = Self.bareMediaType(contentType)
        var fields: [String: String] = [:]
        if let configurationId, !configurationId.isEmpty {
            fields["configurationId"] = configurationId
        }
        if let language, !language.isEmpty {
            fields["language"] = language
        }

        do {
            let result: SpeechTranscriptionResult? = try await http.postMultipart(
                "api/stt/transcribe",
                fileField: "file",
                fileName: Self.speechFileName(forBareMediaType: bareType),
                fileData: audioData,
                mimeType: bareType.isEmpty ? "application/octet-stream" : bareType,
                fields: fields
            )
            // An empty or unusable 2xx body is not a transcription. JS names the status here; the
            // Swift client does not surface a SUCCESS status to its callers, so the generic copy
            // stands in.
            guard let result else {
                return SpeechTranscriptionResult(success: false, text: "", errorMessage: Self.genericFailureMessage)
            }
            if result.success {
                return SpeechTranscriptionResult(success: true, text: result.text)
            }
            if let serverMessage = result.errorMessage, !serverMessage.isEmpty {
                return SpeechTranscriptionResult(success: false, text: "", errorMessage: serverMessage)
            }
            return SpeechTranscriptionResult(success: false, text: "", errorMessage: Self.genericFailureMessage)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return SpeechTranscriptionResult(success: false, text: "", errorMessage: Self.transcriptionErrorMessage(error))
        }
    }

    /// Shown when a stop produced no audio at all (`SpeechAudioFormats.NoAudioMessage`).
    static let noAudioMessage = "No audio was recorded."
    /// The generic failure, used when nothing more specific is known.
    static let genericFailureMessage = "Transcription failed. Please try again."

    /// Upload extension per recorded format, keyed by BARE media type. Mirrors the .NET
    /// `SpeechAudioFormats` table and the JS map, which mirror WildwoodAPI's `STTAudioFormats`.
    private static let audioExtensionByMediaType: [String: String] = [
        "audio/webm": ".webm",
        "audio/ogg": ".ogg",
        "audio/mp4": ".mp4",
        "audio/x-m4a": ".m4a",
        "audio/m4a": ".m4a",
        "audio/mpeg": ".mp3",
        "audio/mp3": ".mp3",
        "audio/wav": ".wav",
        "audio/x-wav": ".wav",
        "audio/wave": ".wav",
    ]

    /// `"audio/webm;codecs=opus"` becomes `"audio/webm"`. Empty string for a blank input.
    static func bareMediaType(_ contentType: String) -> String {
        let head: Substring
        if let separator = contentType.firstIndex(of: ";") {
            head = contentType[contentType.startIndex..<separator]
        } else {
            head = contentType[contentType.startIndex..<contentType.endIndex]
        }
        return head.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// `speech.webm`, `speech.m4a`, ... — or a bare `speech` for a format this library does not
    /// name, which the server reads as "let the provider sniff it".
    static func speechFileName(forBareMediaType bareMediaType: String) -> String {
        "speech\(audioExtensionByMediaType[bareMediaType] ?? "")"
    }

    /// The server answered, so prefer its own `errorMessage` and fall back to the status code —
    /// the two messages the .NET client reports. Anything else (network, timeout, a body that did
    /// not decode) carries no server message and gets the generic retry copy.
    private static func transcriptionErrorMessage(_ error: any Error) -> String {
        guard let wildwoodError = error as? WildwoodError, wildwoodError.status > 0 else {
            return genericFailureMessage
        }
        if let details = wildwoodError.details,
           let body = try? JSONSerialization.jsonObject(with: details) as? [String: Any],
           let fromBody = body["errorMessage"] as? String,
           !fromBody.isEmpty {
            return fromBody
        }
        return "Transcription failed (\(wildwoodError.status))."
    }

    /// Infer MIME type from a file extension when the platform type is unavailable.
    public static func mediaType(forFileName fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let map: [String: String] = [
            "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
            "webp": "image/webp", "bmp": "image/bmp", "svg": "image/svg+xml",
            "tif": "image/tiff", "tiff": "image/tiff", "pdf": "application/pdf",
            "txt": "text/plain", "csv": "text/csv", "html": "text/html", "htm": "text/html",
            "json": "application/json", "xml": "application/xml",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "mp3": "audio/mpeg", "wav": "audio/wav", "mp4": "video/mp4", "zip": "application/zip",
        ]
        return map[ext] ?? "application/octet-stream"
    }
}
