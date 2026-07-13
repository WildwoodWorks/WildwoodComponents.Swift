// DocumentService behavior mirrored from the JS documentService tests:
// list soft-fails to [], multipart upload (field "file", multipart Content-Type),
// upload throwing the server's error detail, get -> nil on failure, the 409
// not-parsed-yet mapping on getText, download bytes, delete reporting ok, and
// the api-key/bearer auth headers.

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct DocumentServiceTests {
    private let docJSON = #"{"id":"doc-1","fileName":"rfp.pdf","contentType":"application/pdf","sizeBytes":1024,"status":"uploaded","parsedCharacters":0,"createdAt":"2026-07-07T00:00:00Z"}"#

    private func makeService(appId: String? = "app-1") -> (DocumentService, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, apiKey: "pk-1", appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        return (DocumentService(http: http, appId: appId), backend)
    }

    private func header(_ req: RecordedRequest, _ name: String) -> String? {
        req.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    // MARK: - List

    @Test func listParsesDocuments() async throws {
        let (service, backend) = makeService()
        backend.stub("GET", "/api/documents", .init(json: "[\(docJSON)]"))

        let docs = await service.list()
        #expect(docs.count == 1)
        #expect(docs[0].id == "doc-1")
        #expect(docs[0].fileName == "rfp.pdf")
        #expect(docs[0].sizeBytes == 1024)
        #expect(docs[0].status == "uploaded")
    }

    @Test func listReturnsEmptyOnFailure() async {
        let (service, _) = makeService() // no stub -> 404
        #expect(await service.list().isEmpty)

        let (service403, backend403) = makeService()
        backend403.stub("GET", "/api/documents", .init(statusCode: 403, json: #"{"message":"no access"}"#))
        #expect(await service403.list().isEmpty)
    }

    // MARK: - Upload

    @Test func uploadSendsMultipartFormDataWithFileField() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/documents", .init(json: docJSON))

        let created = try await service.upload(fileData: Data("%PDF-1.7".utf8), fileName: "rfp.pdf", contentType: "application/pdf")
        #expect(created.id == "doc-1")

        let req = try #require(backend.requests().first { $0.method == "POST" && $0.path == "/api/documents" })
        let contentType = try #require(header(req, "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        let bodyText = String(decoding: try #require(req.body), as: UTF8.self)
        #expect(bodyText.contains("name=\"file\""))
        #expect(bodyText.contains("filename=\"rfp.pdf\""))
        #expect(bodyText.contains("Content-Type: application/pdf"))
        #expect(bodyText.contains("%PDF-1.7"))
    }

    @Test func uploadThrowsTheServerErrorDetailOnFailure() async {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/documents", .init(statusCode: 400, json: #"{"error":"Unsupported document type."}"#))

        do {
            _ = try await service.upload(fileData: Data("x".utf8), fileName: "x.exe")
            Issue.record("Expected upload to throw")
        } catch let error as WildwoodError {
            // WildwoodError.fromResponse maps the body's `error` to the message.
            #expect(error.status == 400)
            #expect(error.message == "Unsupported document type.")
        } catch {
            Issue.record("Expected WildwoodError, got \(error)")
        }
    }

    // MARK: - Get

    @Test func getReturnsTheDocument() async throws {
        let (service, backend) = makeService()
        backend.stub("GET", "/api/documents/doc-1", .init(json: docJSON))
        let doc = try #require(await service.get("doc-1"))
        #expect(doc.id == "doc-1")
        #expect(doc.contentType == "application/pdf")
    }

    @Test func getReturnsNilOnFailure() async {
        let (service, _) = makeService() // no stub -> 404
        #expect(await service.get("missing") == nil)
    }

    // MARK: - Text

    @Test func getTextReturnsParsedText() async throws {
        let (service, backend) = makeService()
        backend.stub("GET", "/api/documents/doc-1/text", .init(json: #"{"id":"doc-1","status":"parsed","characters":5,"text":"hello"}"#))

        let result = try #require(await service.getText("doc-1"))
        #expect(result.text == "hello")
        #expect(result.status == "parsed")
        #expect(result.characters == 5)
    }

    @Test func getTextMaps409ToANotReadyResult() async throws {
        let (service, backend) = makeService()
        backend.stub("GET", "/api/documents/doc-1/text", .init(statusCode: 409, json: #"{"status":"parsing","error":"Text not available yet."}"#))

        let result = try #require(await service.getText("doc-1"))
        #expect(result.id == "doc-1")
        #expect(result.status == "parsing")
        #expect(result.characters == 0)
        #expect(result.text == nil)
        #expect(result.error == "Text not available yet.")
    }

    @Test func getTextDefaultsStatusToParsingOn409WithoutBody() async throws {
        let (service, backend) = makeService()
        backend.stub("GET", "/api/documents/doc-1/text", .init(statusCode: 409, body: Data()))

        let result = try #require(await service.getText("doc-1"))
        #expect(result.status == "parsing")
        #expect(result.text == nil)
        #expect(result.error == nil)
    }

    @Test func getTextReturnsNilOnOtherFailures() async {
        let (service, backend) = makeService()
        backend.stub("GET", "/api/documents/doc-1/text", .init(statusCode: 500, json: #"{"message":"boom"}"#))
        #expect(await service.getText("doc-1") == nil)
    }

    // MARK: - Download

    @Test func downloadReturnsBytes() async throws {
        let (service, backend) = makeService()
        let pdf = Data([0x25, 0x50, 0x44, 0x46]) // %PDF
        backend.stub("GET", "/api/documents/doc-1/download", .init(statusCode: 200, body: pdf, headers: ["Content-Type": "application/pdf"]))

        let data = try #require(await service.download("doc-1"))
        #expect(data == pdf)
    }

    @Test func downloadReturnsNilOnFailure() async {
        let (service, _) = makeService() // no stub -> 404
        #expect(await service.download("missing") == nil)
    }

    // MARK: - Delete

    @Test func deleteReportsSuccess() async throws {
        let (service, backend) = makeService()
        backend.stub("DELETE", "/api/documents/doc-1", .init(statusCode: 200))
        #expect(await service.delete("doc-1") == true)
        #expect(backend.requests().contains { $0.method == "DELETE" && $0.path == "/api/documents/doc-1" })
    }

    @Test func deleteReportsFailure() async {
        let (service, _) = makeService() // no stub -> 404
        #expect(await service.delete("doc-1") == false)
    }

    // MARK: - Headers

    @Test func requestsSendApiKeyAndBearerToken() async throws {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, apiKey: "pk-1", appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        await http.setTokenProvider { "jwt-1" }
        let service = DocumentService(http: http, appId: "app-1")
        backend.stub("GET", "/api/documents", .init(json: "[]"))

        _ = await service.list()

        let req = try #require(backend.requests().first { $0.path == "/api/documents" })
        #expect(header(req, "Authorization") == "Bearer jwt-1")
        #expect(header(req, "X-API-Key") == "pk-1")
    }
}
