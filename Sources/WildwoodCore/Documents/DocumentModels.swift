// Tenant document models ported from
// @wildwood/core/src/documents/types.ts (mirrors WildwoodAPI's
// AppDocumentsController DTOs). Date fields are raw ISO strings from the wire.

import Foundation

/// Server-side lifecycle of an uploaded document. String constants (not an enum)
/// to match the API payload verbatim and mirror the JS union.
public enum AppDocumentStatus {
    public static let uploaded = "uploaded"
    public static let parsing = "parsing"
    public static let parsed = "parsed"
    public static let failed = "failed"
}

/// Metadata for one uploaded document (returned by api/documents surfaces).
public struct AppDocumentModel: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var fileName: String
    public var contentType: String
    public var sizeBytes: Int
    public var status: String
    public var parseError: String?
    public var pageCount: Int?
    public var parsedCharacters: Int
    public var companyClientId: String?
    /// ISO 8601 date string, mirroring the JS payload.
    public var createdAt: String
    public var parsedAt: String?

    public init(
        id: String = "",
        fileName: String = "",
        contentType: String = "",
        sizeBytes: Int = 0,
        status: String = AppDocumentStatus.uploaded,
        parseError: String? = nil,
        pageCount: Int? = nil,
        parsedCharacters: Int = 0,
        companyClientId: String? = nil,
        createdAt: String = "",
        parsedAt: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.status = status
        self.parseError = parseError
        self.pageCount = pageCount
        self.parsedCharacters = parsedCharacters
        self.companyClientId = companyClientId
        self.createdAt = createdAt
        self.parsedAt = parsedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType) ?? ""
        sizeBytes = try c.decodeIfPresent(Int.self, forKey: .sizeBytes) ?? 0
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? AppDocumentStatus.uploaded
        parseError = try c.decodeIfPresent(String.self, forKey: .parseError)
        pageCount = try c.decodeIfPresent(Int.self, forKey: .pageCount)
        parsedCharacters = try c.decodeIfPresent(Int.self, forKey: .parsedCharacters) ?? 0
        companyClientId = try c.decodeIfPresent(String.self, forKey: .companyClientId)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        parsedAt = try c.decodeIfPresent(String.self, forKey: .parsedAt)
    }
}

/// Result of GET /documents/{id}/text. `text` is null until parsing succeeds.
public struct AppDocumentTextResult: Codable, Sendable, Equatable {
    public var id: String
    public var status: String
    public var characters: Int
    public var text: String?
    /// Parse error / not-ready detail when text is unavailable.
    public var error: String?

    public init(
        id: String = "",
        status: String = "",
        characters: Int = 0,
        text: String? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.status = status
        self.characters = characters
        self.text = text
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        characters = try c.decodeIfPresent(Int.self, forKey: .characters) ?? 0
        text = try c.decodeIfPresent(String.self, forKey: .text)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }

    /// Maps a 409 "still parsing" response into a text-less result so callers can
    /// poll without special-casing. Mirrors the JS `status: body.status ?? 'parsing'`
    /// / `error: body.error ?? null` fallbacks, reading them from the error body.
    static func notReady(id: String, body: Data?) -> AppDocumentTextResult {
        var status = AppDocumentStatus.parsing
        var error: String?
        if let body,
           let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let s = object["status"] as? String { status = s }
            if let e = object["error"] as? String { error = e }
        }
        return AppDocumentTextResult(id: id, status: status, characters: 0, text: nil, error: error)
    }
}
