// Messaging models ported from @wildwood/core/src/messaging/types.ts.

import Foundation

public enum MessageType: Int, Codable, Sendable {
    case text = 1
    case file = 2
    case image = 3
    case system = 4
}

public enum ThreadType: Int, Codable, Sendable {
    case direct = 1
    case group = 2
    case channel = 3
}

public enum ParticipantRole: Int, Codable, Sendable {
    case member = 1
    case admin = 2
    case owner = 3
}

public enum UserStatus: Int, Codable, Sendable {
    case available = 1
    case busy = 2
    case away = 3
    case doNotDisturb = 4
    case offline = 5
}

public struct SecureMessage: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var threadId: String
    public var senderId: String
    public var senderName: String
    public var senderAvatar: String?
    public var content: String
    public var messageType: MessageType
    public var createdAt: Date?
    public var updatedAt: Date?
    public var isEdited: Bool
    public var isDeleted: Bool
    public var replyToMessageId: String?
    public var attachments: [MessageAttachment]
    public var reactions: [MessageReaction]
    public var readReceipts: [MessageReadReceipt]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        threadId = try c.decodeIfPresent(String.self, forKey: .threadId) ?? ""
        senderId = try c.decodeIfPresent(String.self, forKey: .senderId) ?? ""
        senderName = try c.decodeIfPresent(String.self, forKey: .senderName) ?? ""
        senderAvatar = try c.decodeIfPresent(String.self, forKey: .senderAvatar)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        messageType = try c.decodeIfPresent(MessageType.self, forKey: .messageType) ?? .text
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        isEdited = try c.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        replyToMessageId = try c.decodeIfPresent(String.self, forKey: .replyToMessageId)
        attachments = try c.decodeIfPresent([MessageAttachment].self, forKey: .attachments) ?? []
        reactions = try c.decodeIfPresent([MessageReaction].self, forKey: .reactions) ?? []
        readReceipts = try c.decodeIfPresent([MessageReadReceipt].self, forKey: .readReceipts) ?? []
    }
}

public struct MessageThread: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var companyAppId: String
    public var subject: String
    public var threadType: ThreadType
    public var createdAt: Date?
    public var lastActivity: Date?
    public var isActive: Bool
    public var lastMessagePreview: String?
    public var unreadCount: Int
    public var participants: [ThreadParticipant]
    public var settings: ThreadSettings?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        companyAppId = try c.decodeIfPresent(String.self, forKey: .companyAppId) ?? ""
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        threadType = try c.decodeIfPresent(ThreadType.self, forKey: .threadType) ?? .direct
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        lastActivity = try c.decodeIfPresent(Date.self, forKey: .lastActivity)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        lastMessagePreview = try c.decodeIfPresent(String.self, forKey: .lastMessagePreview)
        unreadCount = try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        participants = try c.decodeIfPresent([ThreadParticipant].self, forKey: .participants) ?? []
        settings = try c.decodeIfPresent(ThreadSettings.self, forKey: .settings)
    }
}

public struct ThreadParticipant: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var threadId: String
    public var userId: String
    public var userName: String
    public var avatar: String?
    public var role: ParticipantRole
    public var joinedAt: Date?
    public var leftAt: Date?
    public var isActive: Bool

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        threadId = try c.decodeIfPresent(String.self, forKey: .threadId) ?? ""
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? ""
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        role = try c.decodeIfPresent(ParticipantRole.self, forKey: .role) ?? .member
        joinedAt = try c.decodeIfPresent(Date.self, forKey: .joinedAt)
        leftAt = try c.decodeIfPresent(Date.self, forKey: .leftAt)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }
}

public struct ThreadSettings: Codable, Sendable, Equatable {
    public var id: String
    public var threadId: String
    public var allowFileSharing: Bool
    public var allowReactions: Bool
    public var notificationsEnabled: Bool
    public var readReceiptsEnabled: Bool
    public var maxParticipants: Int
    public var allowedFileTypes: [String]
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        threadId = try c.decodeIfPresent(String.self, forKey: .threadId) ?? ""
        allowFileSharing = try c.decodeIfPresent(Bool.self, forKey: .allowFileSharing) ?? true
        allowReactions = try c.decodeIfPresent(Bool.self, forKey: .allowReactions) ?? true
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        readReceiptsEnabled = try c.decodeIfPresent(Bool.self, forKey: .readReceiptsEnabled) ?? true
        maxParticipants = try c.decodeIfPresent(Int.self, forKey: .maxParticipants) ?? 0
        allowedFileTypes = try c.decodeIfPresent([String].self, forKey: .allowedFileTypes) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

public struct MessageAttachment: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var messageId: String
    public var fileName: String
    public var contentType: String
    public var fileSize: Int
    public var storagePath: String?
    public var thumbnailUrl: String?
    public var createdAt: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        messageId = try c.decodeIfPresent(String.self, forKey: .messageId) ?? ""
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType) ?? ""
        fileSize = try c.decodeIfPresent(Int.self, forKey: .fileSize) ?? 0
        storagePath = try c.decodeIfPresent(String.self, forKey: .storagePath)
        thumbnailUrl = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

public struct MessageReaction: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var messageId: String
    public var userId: String
    public var userName: String
    public var emoji: String
    public var createdAt: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        messageId = try c.decodeIfPresent(String.self, forKey: .messageId) ?? ""
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? ""
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

public struct MessageReadReceipt: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var messageId: String
    public var userId: String
    public var readAt: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        messageId = try c.decodeIfPresent(String.self, forKey: .messageId) ?? ""
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        readAt = try c.decodeIfPresent(Date.self, forKey: .readAt)
    }
}

public struct CompanyAppUser: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var companyAppId: String
    public var userId: String
    public var userName: String
    public var email: String
    public var avatar: String?
    public var status: UserStatus
    public var isActive: Bool
    public var lastSeen: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        companyAppId = try c.decodeIfPresent(String.self, forKey: .companyAppId) ?? ""
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        status = try c.decodeIfPresent(UserStatus.self, forKey: .status) ?? .offline
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen)
    }
}

public struct OnlineStatus: Codable, Sendable, Equatable {
    public var userId: String
    public var isOnline: Bool
    public var status: UserStatus
    public var lastSeen: Date?
    public var statusMessage: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        isOnline = try c.decodeIfPresent(Bool.self, forKey: .isOnline) ?? false
        status = try c.decodeIfPresent(UserStatus.self, forKey: .status) ?? .offline
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen)
        statusMessage = try c.decodeIfPresent(String.self, forKey: .statusMessage)
    }
}

public struct TypingIndicator: Codable, Sendable, Equatable {
    public var userId: String
    public var threadId: String
    public var userName: String
    public var isVisible: Bool
    public var startedAt: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        threadId = try c.decodeIfPresent(String.self, forKey: .threadId) ?? ""
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? ""
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? false
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
    }
}

public struct MessageSearchResult: Codable, Sendable, Equatable {
    public var messageId: String
    public var threadId: String
    public var content: String
    public var senderName: String
    public var createdAt: Date?
    public var threadSubject: String

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messageId = try c.decodeIfPresent(String.self, forKey: .messageId) ?? ""
        threadId = try c.decodeIfPresent(String.self, forKey: .threadId) ?? ""
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        senderName = try c.decodeIfPresent(String.self, forKey: .senderName) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        threadSubject = try c.decodeIfPresent(String.self, forKey: .threadSubject) ?? ""
    }
}

public struct MessageDraft: Codable, Sendable, Equatable {
    public var threadId: String
    public var content: String
    public var replyToMessageId: String?
    public var lastModified: Date?

    public init(threadId: String, content: String, replyToMessageId: String? = nil, lastModified: Date? = nil) {
        self.threadId = threadId
        self.content = content
        self.replyToMessageId = replyToMessageId
        self.lastModified = lastModified
    }
}

public struct AttachmentUploadResult: Codable, Sendable, Equatable {
    public var attachmentId: String
    public var fileName: String
    public var fileSize: Int
    public var contentType: String
}
