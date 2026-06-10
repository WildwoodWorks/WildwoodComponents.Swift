// Messaging service ported from @wildwood/core/src/messaging/messagingService.ts
// (itself a port of WildwoodComponents.Blazor/Services/SecureMessagingService.cs).

import Foundation

public final class MessagingService: Sendable {
    private let http: WildwoodHttpClient
    private let storage: (any WildwoodStorageAdapter)?

    public init(http: WildwoodHttpClient, storage: (any WildwoodStorageAdapter)? = nil) {
        self.http = http
        self.storage = storage
    }

    // MARK: - Threads

    public func getThreads(companyAppId: String) async throws -> [MessageThread] {
        let encoded = companyAppId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? companyAppId
        return try await http.get("api/messaging/threads?companyAppId=\(encoded)")
    }

    public func getThread(threadId: String) async -> MessageThread? {
        try? await http.get("api/messaging/threads/\(threadId)")
    }

    public func createThread(
        companyAppId: String,
        subject: String,
        participantIds: [String],
        threadType: ThreadType = .direct
    ) async throws -> MessageThread {
        struct CreateThreadDto: Encodable {
            let companyAppId: String
            let subject: String
            let participantIds: [String]
            let threadType: ThreadType
        }
        return try await http.post(
            "api/messaging/threads",
            body: CreateThreadDto(companyAppId: companyAppId, subject: subject, participantIds: participantIds, threadType: threadType)
        )
    }

    // MARK: - Messages

    public func getMessages(threadId: String, page: Int = 1, pageSize: Int = 50) async throws -> [SecureMessage] {
        try await http.get("api/messaging/threads/\(threadId)/messages?page=\(page)&pageSize=\(pageSize)")
    }

    public func sendMessage(
        threadId: String,
        content: String,
        messageType: MessageType = .text,
        replyToMessageId: String? = nil
    ) async throws -> SecureMessage {
        struct SendMessageDto: Encodable {
            let threadId: String
            let content: String
            let messageType: MessageType
            let replyToMessageId: String?
        }
        let data: SecureMessage = try await http.post(
            "api/messaging/messages",
            body: SendMessageDto(threadId: threadId, content: content, messageType: messageType, replyToMessageId: replyToMessageId)
        )
        // Auto-clear draft after successful send (matches Blazor behavior).
        clearDraft(threadId: threadId)
        return data
    }

    public func editMessage(messageId: String, newContent: String) async throws -> SecureMessage {
        struct EditDto: Encodable {
            let content: String
        }
        return try await http.put("api/messaging/messages/\(messageId)", body: EditDto(content: newContent))
    }

    public func deleteMessage(messageId: String) async -> Bool {
        do {
            try await http.deleteVoid("api/messaging/messages/\(messageId)")
            return true
        } catch {
            return false
        }
    }

    // MARK: - Reactions

    public func reactToMessage(messageId: String, emoji: String) async -> Bool {
        struct ReactionDto: Encodable {
            let emoji: String
        }
        do {
            try await http.postVoid("api/messaging/messages/\(messageId)/reactions", body: ReactionDto(emoji: emoji))
            return true
        } catch {
            return false
        }
    }

    public func removeReaction(messageId: String, emoji: String) async -> Bool {
        let encoded = emoji.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? emoji
        do {
            try await http.deleteVoid("api/messaging/messages/\(messageId)/reactions/\(encoded)")
            return true
        } catch {
            return false
        }
    }

    // MARK: - Read receipts

    public func markMessageAsRead(messageId: String) async -> Bool {
        do {
            try await http.postVoid("api/messaging/messages/\(messageId)/read")
            return true
        } catch {
            return false
        }
    }

    public func markThreadAsRead(threadId: String) async -> Bool {
        do {
            try await http.postVoid("api/messaging/threads/\(threadId)/read")
            return true
        } catch {
            return false
        }
    }

    // MARK: - Users

    public func getCompanyAppUsers(companyAppId: String) async throws -> [CompanyAppUser] {
        let encoded = companyAppId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? companyAppId
        return try await http.get("api/messaging/users?companyAppId=\(encoded)")
    }

    public func searchUsers(companyAppId: String, searchTerm: String) async throws -> [CompanyAppUser] {
        let app = companyAppId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? companyAppId
        let term = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchTerm
        return try await http.get("api/messaging/users/search?companyAppId=\(app)&q=\(term)")
    }

    // MARK: - Typing indicators

    public func startTyping(threadId: String) async -> Bool {
        do {
            try await http.postVoid("api/messaging/threads/\(threadId)/typing/start")
            return true
        } catch {
            return false
        }
    }

    public func stopTyping(threadId: String) async -> Bool {
        do {
            try await http.postVoid("api/messaging/threads/\(threadId)/typing/stop")
            return true
        } catch {
            return false
        }
    }

    public func getTypingIndicators(threadId: String) async throws -> [TypingIndicator] {
        try await http.get("api/messaging/threads/\(threadId)/typing")
    }

    // MARK: - Attachments

    public func downloadAttachment(attachmentId: String) async throws -> Data {
        try await http.getData("api/messaging/attachments/\(attachmentId)")
    }

    public func uploadAttachment(threadId: String, fileData: Data, fileName: String, mimeType: String) async throws -> AttachmentUploadResult {
        try await http.postMultipart(
            "api/messaging/attachments",
            fileField: "file",
            fileName: fileName,
            fileData: fileData,
            mimeType: mimeType,
            fields: ["threadId": threadId]
        )
    }

    // MARK: - Search

    public func searchMessages(companyAppId: String, searchTerm: String, threadId: String? = nil) async throws -> [MessageSearchResult] {
        let app = companyAppId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? companyAppId
        let term = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchTerm
        var url = "api/messaging/search?companyAppId=\(app)&q=\(term)"
        if let threadId {
            url += "&threadId=\(threadId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? threadId)"
        }
        return try await http.get(url)
    }

    // MARK: - Online status

    public func updateOnlineStatus(companyAppId: String, status: UserStatus, statusMessage: String? = nil) async -> Bool {
        struct StatusDto: Encodable {
            let companyAppId: String
            let status: UserStatus
            let statusMessage: String?
        }
        do {
            try await http.postVoid(
                "api/messaging/status",
                body: StatusDto(companyAppId: companyAppId, status: status, statusMessage: statusMessage)
            )
            return true
        } catch {
            return false
        }
    }

    public func getOnlineStatuses(companyAppId: String) async throws -> [OnlineStatus] {
        let encoded = companyAppId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? companyAppId
        return try await http.get("api/messaging/status?companyAppId=\(encoded)")
    }

    // MARK: - Drafts (client-side, mirrors the JS localStorage drafts at ww_draft_{threadId})

    public func saveDraft(threadId: String, content: String, replyToMessageId: String? = nil) {
        guard let storage else { return }
        let draft = MessageDraft(threadId: threadId, content: content, replyToMessageId: replyToMessageId, lastModified: Date())
        if let data = try? WildwoodJSON.encoder().encode(draft), let json = String(data: data, encoding: .utf8) {
            storage.setItem(WildwoodStorageKeys.draft(threadId: threadId), json)
        }
    }

    public func getDraft(threadId: String) -> MessageDraft? {
        guard let storage,
              let raw = storage.getItem(WildwoodStorageKeys.draft(threadId: threadId)),
              let data = raw.data(using: .utf8) else { return nil }
        return try? WildwoodJSON.decoder().decode(MessageDraft.self, from: data)
    }

    public func clearDraft(threadId: String) {
        storage?.removeItem(WildwoodStorageKeys.draft(threadId: threadId))
    }
}
