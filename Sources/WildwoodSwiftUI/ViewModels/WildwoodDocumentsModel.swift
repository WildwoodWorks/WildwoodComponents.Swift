// Tenant document state — the SwiftUI analog of react-shared's useDocuments
// hook. Wraps WildwoodCore's DocumentService: list, upload, delete, and text
// retrieval, with automatic polling while any document is still uploaded/parsing
// (text extraction runs server-side on a background worker).
//
// DocumentService soft-fails (list -> [], get/text -> nil, delete -> Bool), so
// there is no per-lookup do/catch here; only `upload` throws, and its server
// error detail is surfaced via errorMessage.

import Foundation
import Observation
import WildwoodCore

@MainActor
@Observable
public final class WildwoodDocumentsModel {
    @ObservationIgnored private let service: DocumentService

    public private(set) var documents: [AppDocumentModel] = []
    public private(set) var isLoading = true
    /// True while an upload request is in flight.
    public private(set) var isUploading = false
    public var errorMessage: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    private static let parsingStatuses: Set<String> = [AppDocumentStatus.uploaded, AppDocumentStatus.parsing]

    public init(client: WildwoodClient, appId: String? = nil) {
        if let appId, !appId.isEmpty, appId != client.config.appId {
            self.service = DocumentService(http: client.http, appId: appId)
        } else {
            self.service = client.documents
        }
    }

    // MARK: - Polling lifecycle

    /// Refresh once, then poll ONLY while a document is still uploaded/parsing so
    /// statuses settle without manual refresh. Cancels any existing poll first, so
    /// repeated calls are safe. `pollIntervalSeconds <= 0` performs a single refresh.
    public func start(pollIntervalSeconds: Int = 3) {
        stop()
        isLoading = true
        pollTask = Task { [weak self] in
            await self?.refresh()
            guard pollIntervalSeconds > 0 else { return }
            while !Task.isCancelled {
                // Stop as soon as nothing is left parsing (or the model is gone).
                guard self?.hasParsing() == true else { return }
                try? await Task.sleep(for: .seconds(pollIntervalSeconds))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func hasParsing() -> Bool {
        documents.contains { Self.parsingStatuses.contains($0.status) }
    }

    // MARK: - Load

    public func refresh() async {
        documents = await service.list() // soft-fails to [] on any error
        isLoading = false
    }

    // MARK: - Mutations

    @discardableResult
    public func upload(
        fileData: Data,
        fileName: String,
        contentType: String = "application/octet-stream"
    ) async -> AppDocumentModel? {
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        do {
            let created = try await service.upload(fileData: fileData, fileName: fileName, contentType: contentType)
            await refresh()
            return created
        } catch {
            errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
            return nil
        }
    }

    @discardableResult
    public func remove(id: String) async -> Bool {
        let deleted = await service.delete(id)
        if deleted { await refresh() } else { errorMessage = "Couldn't delete the document." }
        return deleted
    }

    /// Extracted text (text nil while parsing / after failure — check status/error).
    public func text(id: String) async -> AppDocumentTextResult? {
        await service.getText(id)
    }
}
