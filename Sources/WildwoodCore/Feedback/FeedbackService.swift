// Feedback models + service ported from @wildwood/core/src/feedback.
// Submit/vote work anonymously and authenticated (Bearer added automatically).

import Foundation

public struct FeedbackWidgetConfig: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var allowAnonymous: Bool
    public var feedbackTypes: [String]
    public var widgetColor: String?
    public var widgetPosition: String
    public var requireScreenshot: Bool
    public var screenshotMaxSizeKb: Int
    public var screenshotQuality: Int
    public var enableDuplicateDetection: Bool
    public var allowAttachments: Bool
    public var maxAttachmentSizeKb: Int
    public var allowedAttachmentTypes: String

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        allowAnonymous = try c.decodeIfPresent(Bool.self, forKey: .allowAnonymous) ?? false
        feedbackTypes = try c.decodeIfPresent([String].self, forKey: .feedbackTypes) ?? []
        widgetColor = try c.decodeIfPresent(String.self, forKey: .widgetColor)
        widgetPosition = try c.decodeIfPresent(String.self, forKey: .widgetPosition) ?? "bottom-right"
        requireScreenshot = try c.decodeIfPresent(Bool.self, forKey: .requireScreenshot) ?? false
        screenshotMaxSizeKb = try c.decodeIfPresent(Int.self, forKey: .screenshotMaxSizeKb) ?? 0
        screenshotQuality = try c.decodeIfPresent(Int.self, forKey: .screenshotQuality) ?? 80
        enableDuplicateDetection = try c.decodeIfPresent(Bool.self, forKey: .enableDuplicateDetection) ?? false
        allowAttachments = try c.decodeIfPresent(Bool.self, forKey: .allowAttachments) ?? false
        maxAttachmentSizeKb = try c.decodeIfPresent(Int.self, forKey: .maxAttachmentSizeKb) ?? 0
        allowedAttachmentTypes = try c.decodeIfPresent(String.self, forKey: .allowedAttachmentTypes) ?? ""
    }
}

public struct SubmitFeedbackInput: Sendable, Equatable {
    public var appId: String?
    public var title: String
    public var description: String
    public var feedbackType: String
    public var pageUrl: String?
    /// Base64 data URL of an optional screenshot.
    public var screenshotData: String?
    /// JSON string of attachments (matches the server contract).
    public var attachments: String?
    /// JSON string of diagnostic context (matches the server contract).
    public var browserContext: String?
    public var submitterEmail: String?
    public var submitterName: String?

    public init(
        appId: String? = nil,
        title: String,
        description: String,
        feedbackType: String,
        pageUrl: String? = nil,
        screenshotData: String? = nil,
        attachments: String? = nil,
        browserContext: String? = nil,
        submitterEmail: String? = nil,
        submitterName: String? = nil
    ) {
        self.appId = appId
        self.title = title
        self.description = description
        self.feedbackType = feedbackType
        self.pageUrl = pageUrl
        self.screenshotData = screenshotData
        self.attachments = attachments
        self.browserContext = browserContext
        self.submitterEmail = submitterEmail
        self.submitterName = submitterName
    }
}

public struct SystemFeedback: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var companyId: String
    public var appId: String?
    public var userId: String?
    public var userName: String?
    public var title: String
    public var description: String
    public var feedbackType: String
    public var status: String
    public var priority: String?
    public var pageUrl: String?
    public var submitterEmail: String?
    public var submitterName: String?
    public var voteCount: Int
    public var mergedIntoId: String?
    public var resolvedAt: Date?
    public var resolvedBy: String?
    public var resolvedByName: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        companyId = try c.decodeIfPresent(String.self, forKey: .companyId) ?? ""
        appId = try c.decodeIfPresent(String.self, forKey: .appId)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
        userName = try c.decodeIfPresent(String.self, forKey: .userName)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        feedbackType = try c.decodeIfPresent(String.self, forKey: .feedbackType) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        priority = try c.decodeIfPresent(String.self, forKey: .priority)
        pageUrl = try c.decodeIfPresent(String.self, forKey: .pageUrl)
        submitterEmail = try c.decodeIfPresent(String.self, forKey: .submitterEmail)
        submitterName = try c.decodeIfPresent(String.self, forKey: .submitterName)
        voteCount = try c.decodeIfPresent(Int.self, forKey: .voteCount) ?? 0
        mergedIntoId = try c.decodeIfPresent(String.self, forKey: .mergedIntoId)
        resolvedAt = try c.decodeIfPresent(Date.self, forKey: .resolvedAt)
        resolvedBy = try c.decodeIfPresent(String.self, forKey: .resolvedBy)
        resolvedByName = try c.decodeIfPresent(String.self, forKey: .resolvedByName)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

public struct FeedbackDuplicateCheck: Codable, Sendable, Equatable {
    public var hasPotentialDuplicate: Bool
    public var duplicateTitle: String?
    public var duplicateId: String?
    public var duplicateVoteCount: Int
    public var duplicateCreatedAt: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasPotentialDuplicate = try c.decodeIfPresent(Bool.self, forKey: .hasPotentialDuplicate) ?? false
        duplicateTitle = try c.decodeIfPresent(String.self, forKey: .duplicateTitle)
        duplicateId = try c.decodeIfPresent(String.self, forKey: .duplicateId)
        duplicateVoteCount = try c.decodeIfPresent(Int.self, forKey: .duplicateVoteCount) ?? 0
        duplicateCreatedAt = try c.decodeIfPresent(Date.self, forKey: .duplicateCreatedAt)
    }
}

public struct FeedbackVoteResult: Codable, Sendable, Equatable {
    public var voteCount: Int

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        voteCount = try c.decodeIfPresent(Int.self, forKey: .voteCount) ?? 0
    }
}

public final class FeedbackService: Sendable {
    private let http: WildwoodHttpClient
    private let defaultAppId: String

    public init(http: WildwoodHttpClient, defaultAppId: String) {
        self.http = http
        self.defaultAppId = defaultAppId
    }

    /// Effective appId, treating blank as "not provided" so it never overrides
    /// the configured default or reaches the server as an empty string.
    private func resolveAppId(_ appId: String?) -> String {
        let provided = appId?.trimmingCharacters(in: .whitespaces) ?? ""
        if !provided.isEmpty { return provided }
        return defaultAppId.trimmingCharacters(in: .whitespaces)
    }

    /// Public widget configuration (anonymous-accessible).
    public func getWidgetConfig(appId: String? = nil) async throws -> FeedbackWidgetConfig {
        let targetAppId = resolveAppId(appId)
        return try await http.get("api/AppComponentConfigurations/\(targetAppId)/feedback/widget")
    }

    /// Submit feedback; returns the created record.
    public func submitFeedback(_ input: SubmitFeedbackInput) async throws -> SystemFeedback {
        struct SubmitDto: Encodable {
            let appId: String?
            let title: String
            let description: String
            let feedbackType: String
            let pageUrl: String?
            let screenshotData: String?
            let attachments: String?
            let browserContext: String?
            let submitterEmail: String?
            let submitterName: String?
        }
        let resolved = resolveAppId(input.appId)
        return try await http.post(
            "api/SystemFeedback",
            body: SubmitDto(
                appId: resolved.isEmpty ? nil : resolved,
                title: input.title,
                description: input.description,
                feedbackType: input.feedbackType,
                pageUrl: input.pageUrl,
                screenshotData: input.screenshotData,
                attachments: input.attachments,
                browserContext: input.browserContext,
                submitterEmail: input.submitterEmail,
                submitterName: input.submitterName
            )
        )
    }

    /// Check for a potential duplicate title submitted in the last hour.
    public func checkDuplicate(title: String, appId: String? = nil) async throws -> FeedbackDuplicateCheck {
        let targetAppId = resolveAppId(appId)
        var url = "api/SystemFeedback/duplicate-check?title=\(title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title)"
        if !targetAppId.isEmpty {
            url += "&appId=\(targetAppId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? targetAppId)"
        }
        return try await http.get(url)
    }

    /// Upvote an existing feedback item ("me too").
    public func voteFeedback(id: String) async throws -> FeedbackVoteResult {
        try await http.post("api/SystemFeedback/\(id)/vote")
    }
}
