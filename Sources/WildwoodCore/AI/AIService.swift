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
