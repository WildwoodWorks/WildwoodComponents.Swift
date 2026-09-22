// AIService session/config/TTS behavior mirrored from the JS aiService tests.
// (sendMessage/proxy paths are covered indirectly; here we exercise the CRUD
// and Bool-returning session methods that don't need an AIChatRequest fixture.)

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct AIServiceTests {
    private func makeService(appId: String? = nil) -> (AIService, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        return (AIService(http: http, appId: appId), backend)
    }

    private func jsonBody(_ req: RecordedRequest) throws -> [String: Any] {
        let data = try #require(req.body)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func getConfigurationsReturnsTheList() async throws {
        let (service, backend) = makeService(appId: "app-9")
        backend.stub("GET", "/api/ai/configurations", .init(json: #"[{"id":"cfg-1"}]"#))

        let configs = try await service.getConfigurations(configurationType: "chat")

        #expect(configs.count == 1)
        #expect(backend.requests().contains { $0.method == "GET" && $0.path == "/api/ai/configurations" })
    }

    @Test func getConfigurationReturnsNilOnError() async {
        let (service, _) = makeService() // no stub
        #expect(await service.getConfiguration(configurationId: "missing") == nil)
    }

    @Test func createSessionPostsDefaultSessionName() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/ai/sessions", .init(json: #"{"id":"sess-1"}"#))

        _ = await service.createSession(configurationId: "c1")

        let req = try #require(backend.requests().first { $0.method == "POST" && $0.path == "/api/ai/sessions" })
        let body = try jsonBody(req)
        #expect(body["configurationId"] as? String == "c1")
        #expect(body["sessionName"] as? String == "New Session")
    }

    @Test func renameSessionPutsNewName() async throws {
        let (service, backend) = makeService()
        backend.stub("PUT", "/api/ai/sessions/s1/name", .init(statusCode: 200))

        let ok = await service.renameSession(sessionId: "s1", newName: "Renamed")

        #expect(ok == true)
        let req = try #require(backend.requests().first { $0.method == "PUT" && $0.path == "/api/ai/sessions/s1/name" })
        let body = try jsonBody(req)
        #expect(body["newName"] as? String == "Renamed")
    }

    @Test func endSessionReturnsTrueThenFalse() async {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/ai/sessions/s1/end", .init(statusCode: 200))
        #expect(await service.endSession(sessionId: "s1") == true)

        let (service2, _) = makeService() // no stub -> false
        #expect(await service2.endSession(sessionId: "s1") == false)
    }

    @Test func deleteSessionIssuesDelete() async {
        let (service, backend) = makeService()
        backend.stub("DELETE", "/api/ai/sessions/s1", .init(statusCode: 200))

        #expect(await service.deleteSession(sessionId: "s1") == true)
        #expect(backend.requests().contains { $0.method == "DELETE" && $0.path == "/api/ai/sessions/s1" })
    }

    @Test func getTTSVoicesReturnsEmptyOnError() async {
        let (service, _) = makeService() // no stub -> []
        #expect(await service.getTTSVoices().isEmpty)
    }
}

// Ported from the JS `AIService.transcribeAudio` tests (packages/wildwood-core/src/__tests__/
// aiService.test.ts), which are themselves the contract Blazor's TranscribeAudioAsync writes: the
// multipart shape is what the server's STT endpoint reads, and the method reports every business
// failure as a result rather than throwing.
@MainActor
struct AITranscribeTests {
    private let clip = Data("RIFFfake".utf8)

    private func makeService() -> (AIService, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        return (AIService(http: http), backend)
    }

    /// The one multipart POST the call made, as text — the parts are asserted the way
    /// `DocumentServiceTests` asserts an upload.
    private func sentForm(_ backend: MockBackend) throws -> String {
        let requests = backend.requests().filter { $0.method == "POST" && $0.path == "/api/stt/transcribe" }
        #expect(requests.count == 1)
        let req = try #require(requests.first)
        // Case-insensitive, as DocumentServiceTests reads it: URLSession is free to normalize
        // header names on their way through the protocol stub.
        let contentType = try #require(
            req.headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
        )
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        return String(decoding: try #require(req.body), as: UTF8.self)
    }

    @Test func postsMultipartFormDataToSttTranscribe() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/stt/transcribe", .init(json: #"{"success":true,"text":"hello there"}"#))

        let result = try await service.transcribeAudio(
            audioData: clip,
            contentType: "audio/webm;codecs=opus",
            configurationId: "cfg-1",
            language: "en-US"
        )

        let form = try sentForm(backend)
        #expect(form.contains("name=\"file\""))
        #expect(form.contains("name=\"configurationId\"\r\n\r\ncfg-1\r\n"))
        #expect(form.contains("name=\"language\"\r\n\r\nen-US\r\n"))
        #expect(result == SpeechTranscriptionResult(success: true, text: "hello there"))
    }

    @Test func namesTheFilePartFileWithASpeechFileNameAndTheBareMediaType() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/stt/transcribe", .init(json: #"{"success":true,"text":""}"#))

        _ = try await service.transcribeAudio(audioData: clip, contentType: "audio/webm;codecs=opus")

        let form = try sentForm(backend)
        #expect(form.contains("name=\"file\"; filename=\"speech.webm\""))
        // "audio/webm;codecs=opus" -> "audio/webm": the codec parameters are stripped off the part.
        #expect(form.contains("Content-Type: audio/webm\r\n"))
        #expect(!form.contains("codecs=opus"))
    }

    @Test func mapsEachRecordedFormatToItsUploadFileName() async throws {
        let cases: [(contentType: String, fileName: String)] = [
            ("audio/webm", "speech.webm"),
            ("audio/ogg;codecs=opus", "speech.ogg"),
            ("audio/mp4", "speech.mp4"),
            ("audio/x-m4a", "speech.m4a"),
            ("audio/m4a", "speech.m4a"),
            ("audio/mpeg", "speech.mp3"),
            ("audio/mp3", "speech.mp3"),
            ("audio/wav", "speech.wav"),
            ("audio/x-wav", "speech.wav"),
            ("audio/wave", "speech.wav"),
            // Not a format this library names: the server is left to sniff the container.
            ("audio/aiff", "speech"),
        ]

        for testCase in cases {
            let (service, backend) = makeService()
            backend.stub("POST", "/api/stt/transcribe", .init(json: #"{"success":true,"text":""}"#))

            _ = try await service.transcribeAudio(audioData: clip, contentType: testCase.contentType)

            let form = try sentForm(backend)
            #expect(form.contains("filename=\"\(testCase.fileName)\""))
        }
    }

    @Test func omitsConfigurationIdAndLanguageWhenEmpty() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/stt/transcribe", .init(json: #"{"success":true,"text":""}"#))

        _ = try await service.transcribeAudio(
            audioData: clip,
            contentType: "audio/webm",
            configurationId: "",
            language: ""
        )

        let form = try sentForm(backend)
        #expect(!form.contains("name=\"configurationId\""))
        #expect(!form.contains("name=\"language\""))
    }

    @Test func reportsNoAudioWithoutCallingTheServer() async throws {
        let (service, backend) = makeService()

        let result = try await service.transcribeAudio(audioData: Data(), contentType: "audio/webm")

        #expect(result == SpeechTranscriptionResult(success: false, text: "", errorMessage: "No audio was recorded."))
        #expect(backend.requests().isEmpty)
    }

    @Test func neverThrowsOnANon2xxAndKeepsTheServerMessage() async throws {
        let (service, backend) = makeService()
        backend.stub(
            "POST",
            "/api/stt/transcribe",
            .init(statusCode: 400, json: #"{"errorMessage":"Audio format not supported."}"#)
        )

        let result = try await service.transcribeAudio(audioData: clip, contentType: "audio/webm")

        #expect(result == SpeechTranscriptionResult(
            success: false,
            text: "",
            errorMessage: "Audio format not supported."
        ))
    }

    @Test func fallsBackToTheStatusCodeWhenTheFailureCarriesNoMessage() async throws {
        let (service, backend) = makeService()
        // A 413 from the web server, whose body is HTML rather than the result JSON.
        backend.stub("POST", "/api/stt/transcribe", .init(statusCode: 413, json: "<html/>"))

        let result = try await service.transcribeAudio(audioData: clip, contentType: "audio/webm")

        #expect(result == SpeechTranscriptionResult(
            success: false,
            text: "",
            errorMessage: "Transcription failed (413)."
        ))
    }

    @Test func neverThrowsOnANetworkError() async throws {
        let (service, backend) = makeService()
        backend.stubError("POST", "/api/stt/transcribe", .notConnectedToInternet)

        let result = try await service.transcribeAudio(audioData: clip, contentType: "audio/webm")

        #expect(result == SpeechTranscriptionResult(
            success: false,
            text: "",
            errorMessage: "Transcription failed. Please try again."
        ))
    }

    @Test func treatsA200CarryingSuccessFalseAsAFailure() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/stt/transcribe", .init(json: #"{"success":false,"errorMessage":"No speech detected."}"#))

        let result = try await service.transcribeAudio(audioData: clip, contentType: "audio/webm")

        #expect(result == SpeechTranscriptionResult(success: false, text: "", errorMessage: "No speech detected."))
    }

    @Test func reportsTheGenericFailureWhenA2xxBodyIsUnusable() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/stt/transcribe", .init(statusCode: 200))

        let result = try await service.transcribeAudio(audioData: clip, contentType: "audio/webm")

        #expect(result == SpeechTranscriptionResult(
            success: false,
            text: "",
            errorMessage: "Transcription failed. Please try again."
        ))
    }

    @Test func normalizesASuccessWithNoTextToAnEmptyString() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/stt/transcribe", .init(json: #"{"success":true}"#))

        let result = try await service.transcribeAudio(audioData: clip, contentType: "audio/webm")

        #expect(result == SpeechTranscriptionResult(success: true, text: ""))
    }
}
