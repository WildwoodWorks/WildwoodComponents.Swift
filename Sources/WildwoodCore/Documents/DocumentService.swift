// Tenant document service ported from
// @wildwood/core/src/documents/documentService.ts (the JS stack is the reference
// implementation; there is no visual component — service only). Client for
// WildwoodAPI's api/documents surface: upload, list, metadata, extracted text,
// download, delete. Documents are tenant-scoped server-side via the caller's
// company_client_id claim.
//
// Failure idiom mirrors the JS soft/hard split: `list` returns [] on any
// failure, `get`/`download` return nil, `getText` maps a 409 ("still parsing")
// to a text-less result and returns nil on other failures, `delete` reports the
// boolean outcome, and `upload` THROWS (surfacing the server's error detail).
//
// Auth semantics live in the shared HTTP client: a 401 triggers a single
// refresh + replay whose refresh flow emits the session-expired signal (once per
// token); a 403 (tier lacks DOCUMENTS) is a permission denial with no session
// signal. Uploads use the client's multipart verb (field name "file", no manual
// Content-Type beyond the multipart boundary); downloads use the raw-bytes GET.
//
// PARITY: endpoint paths are passed as double-quoted string literals to the HTTP
// verb methods so the Sync parity script can extract them.

import Foundation

public final class DocumentService: Sendable {
    private let http: WildwoodHttpClient
    private let appId: String?

    public init(http: WildwoodHttpClient, appId: String? = nil) {
        self.http = http
        self.appId = appId
    }

    /// All documents for the current tenant. Soft-fails to an empty array on any
    /// error (auth deny, non-ok, or transport), matching the JS contract.
    public func list() async -> [AppDocumentModel] {
        do {
            return try await http.get("api/documents\(appQuery())")
        } catch {
            return []
        }
    }

    /// Uploads one file as multipart form data (field name "file"). Returns the
    /// created document (status "uploaded"; text extraction runs server-side).
    /// THROWS on failure, surfacing the server's error detail.
    public func upload(fileData: Data, fileName: String, contentType: String = "application/octet-stream") async throws -> AppDocumentModel {
        try await http.postMultipart(
            "api/documents\(appQuery())",
            fileField: "file",
            fileName: fileName,
            fileData: fileData,
            mimeType: contentType
        )
    }

    /// One document's metadata, or nil on any failure (auth deny / non-ok / transport).
    public func get(_ documentId: String) async -> AppDocumentModel? {
        do {
            let document: AppDocumentModel = try await http.get("api/documents/\(encodePath(documentId))\(appQuery())")
            return document
        } catch {
            return nil
        }
    }

    /// Extracted text. While parsing is pending/running (or failed) the server
    /// responds 409, mapped here to a result with `text == nil` plus the status
    /// and error detail so callers can poll. Returns nil on other failures.
    public func getText(_ documentId: String) async -> AppDocumentTextResult? {
        do {
            let result: AppDocumentTextResult = try await http.get("api/documents/\(encodePath(documentId))/text\(appQuery())")
            return result
        } catch let error as WildwoodError where error.status == 409 {
            return AppDocumentTextResult.notReady(id: documentId, body: error.details)
        } catch {
            return nil
        }
    }

    /// Original file bytes, or nil when unavailable (auth deny / non-ok / transport).
    public func download(_ documentId: String) async -> Data? {
        try? await http.getData("api/documents/\(encodePath(documentId))/download\(appQuery())")
    }

    /// Deletes the document. Returns whether the request succeeded (the response's
    /// ok status), matching the .NET/JS boolean contract.
    public func delete(_ documentId: String) async -> Bool {
        do {
            try await http.deleteVoid("api/documents/\(encodePath(documentId))\(appQuery())")
            return true
        } catch {
            return false
        }
    }

    // ------------------------------------------------------------------

    private func encodePath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func appQuery() -> String {
        guard let appId, !appId.isEmpty else { return "" }
        return "?requestedAppId=\(appId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? appId)"
    }
}
