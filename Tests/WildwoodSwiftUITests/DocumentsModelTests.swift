// WildwoodDocumentsModel tests — the SwiftUI analog of the useDocuments hook.
// Covers refresh, upload (success flips isUploading + refreshes; failure surfaces
// the server error detail), delete refresh, and the 409 not-parsed-yet text
// mapping, over a stubbed backend (TestBackend).

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct DocumentsModelTests {
    private let docJSON = #"{"id":"doc-1","fileName":"rfp.pdf","contentType":"application/pdf","sizeBytes":1024,"status":"parsed","parsedCharacters":10,"createdAt":"2026-07-07T00:00:00Z"}"#

    private func makeModel(_ backend: TestBackend) -> WildwoodDocumentsModel {
        let client = WildwoodClient(
            config: WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false, storage: .memory),
            urlSession: backend.makeSession()
        )
        return WildwoodDocumentsModel(client: client)
    }

    @Test func refreshLoadsDocuments() async {
        let backend = TestBackend()
        backend.stub("GET", "/api/documents", .init(json: "[\(docJSON)]"))
        let model = makeModel(backend)

        await model.refresh()

        #expect(model.documents.count == 1)
        #expect(model.documents.first?.id == "doc-1")
        #expect(model.isLoading == false)
    }

    @Test func uploadRefreshesAndTogglesUploading() async {
        let backend = TestBackend()
        backend.stub("POST", "/api/documents", .init(json: docJSON))
        backend.stub("GET", "/api/documents", .init(json: "[\(docJSON)]"))
        let model = makeModel(backend)

        let created = await model.upload(fileData: Data("%PDF-1.7".utf8), fileName: "rfp.pdf", contentType: "application/pdf")

        #expect(created?.id == "doc-1")
        #expect(model.documents.count == 1) // refreshed
        #expect(model.isUploading == false) // reset after the upload settled
        #expect(model.errorMessage == nil)
    }

    @Test func uploadSurfacesTheServerErrorDetailOnFailure() async {
        let backend = TestBackend()
        backend.stub("POST", "/api/documents", .init(statusCode: 400, json: #"{"error":"Unsupported document type."}"#))
        let model = makeModel(backend)

        let created = await model.upload(fileData: Data("x".utf8), fileName: "x.exe")

        #expect(created == nil)
        #expect(model.errorMessage == "Unsupported document type.")
        #expect(model.isUploading == false)
    }

    @Test func removeRefreshesOnSuccess() async {
        let backend = TestBackend()
        backend.stub("DELETE", "/api/documents/doc-1", .init(statusCode: 200))
        backend.stub("GET", "/api/documents", .init(json: "[]"))
        let model = makeModel(backend)

        let ok = await model.remove(id: "doc-1")

        #expect(ok == true)
        #expect(model.documents.isEmpty) // refreshed
    }

    @Test func textMaps409ToANotReadyResult() async {
        let backend = TestBackend()
        backend.stub(
            "GET", "/api/documents/doc-1/text",
            .init(statusCode: 409, json: #"{"status":"parsing","error":"Text not available yet."}"#)
        )
        let model = makeModel(backend)

        let result = await model.text(id: "doc-1")

        #expect(result?.status == "parsing")
        #expect(result?.text == nil)
        #expect(result?.error == "Text not available yet.")
    }
}
