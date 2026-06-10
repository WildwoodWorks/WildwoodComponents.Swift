// Secure messaging state — view-model equivalent of react-shared's
// useMessaging. Real-time updates use foreground polling (the JS stacks use
// SignalR; the protocol seam in MessagingService keeps a future native
// SignalR adapter non-breaking). Typing indicators are sent on input with a
// 3-second inactivity stop, and drafts persist debounced — matching the React
// component's behavior.

import Foundation
import Observation
import WildwoodCore

@MainActor
@Observable
public final class WildwoodMessagingModel {
    @ObservationIgnored private let client: WildwoodClient
    @ObservationIgnored public let companyAppId: String
    @ObservationIgnored public var pollInterval: TimeInterval

    public private(set) var threads: [MessageThread] = []
    public private(set) var selectedThread: MessageThread?
    public private(set) var messages: [SecureMessage] = []
    public private(set) var typingIndicators: [TypingIndicator] = []
    public private(set) var isLoading = false
    public var draft = ""
    public var errorMessage = ""

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var draftSaveTask: Task<Void, Never>?
    @ObservationIgnored private var stopTypingTask: Task<Void, Never>?
    @ObservationIgnored private var isTyping = false

    public init(client: WildwoodClient, companyAppId: String, pollInterval: TimeInterval = 5) {
        self.client = client
        self.companyAppId = companyAppId
        self.pollInterval = pollInterval
    }

    public func loadThreads() async {
        isLoading = true
        defer { isLoading = false }
        do {
            threads = try await client.messaging.getThreads(companyAppId: companyAppId)
            // Keep the thread list fresh even before a conversation is opened.
            startPolling()
        } catch {
            errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
        }
    }

    public func selectThread(_ thread: MessageThread) async {
        // Persist the draft of the thread we're leaving.
        persistDraft()
        await stopTypingNow()

        selectedThread = thread
        do {
            messages = try await client.messaging.getMessages(threadId: thread.id)
        } catch {
            messages = []
            errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
        }
        draft = client.messaging.getDraft(threadId: thread.id)?.content ?? ""
        _ = await client.messaging.markThreadAsRead(threadId: thread.id)
        startPolling()
    }

    public func closeThread() {
        persistDraft()
        Task { await stopTypingNow() }
        stopPolling()
        draftSaveTask?.cancel()
        selectedThread = nil
        messages = []
        typingIndicators = []
        draft = ""
    }

    public func createThread(subject: String, participantIds: [String], threadType: ThreadType = .direct) async {
        do {
            let thread = try await client.messaging.createThread(
                companyAppId: companyAppId,
                subject: subject,
                participantIds: participantIds,
                threadType: threadType
            )
            threads.insert(thread, at: 0)
            await selectThread(thread)
        } catch {
            errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
        }
    }

    public func sendMessage() async {
        guard let thread = selectedThread else { return }
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        draft = ""
        draftSaveTask?.cancel()
        await stopTypingNow()
        do {
            let message = try await client.messaging.sendMessage(threadId: thread.id, content: content)
            messages.append(message)
        } catch {
            draft = content
            errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
        }
    }

    public func deleteMessage(_ message: SecureMessage) async {
        if await client.messaging.deleteMessage(messageId: message.id) {
            messages.removeAll { $0.id == message.id }
        }
    }

    public func react(to message: SecureMessage, emoji: String) async {
        let alreadyReacted = message.reactions.contains {
            $0.emoji == emoji && $0.userId == client.session.userId
        }
        let ok = alreadyReacted
            ? await client.messaging.removeReaction(messageId: message.id, emoji: emoji)
            : await client.messaging.reactToMessage(messageId: message.id, emoji: emoji)
        if ok {
            await refreshMessages()
        }
    }

    /// Call on every draft edit: debounces the persisted draft (1s) and sends a
    /// typing indicator with a 3s inactivity stop.
    public func onDraftChanged() {
        draftSaveTask?.cancel()
        draftSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.persistDraft()
        }

        guard selectedThread != nil, !draft.isEmpty else { return }
        if !isTyping {
            isTyping = true
            if let threadId = selectedThread?.id {
                Task { [client] in _ = await client.messaging.startTyping(threadId: threadId) }
            }
        }
        stopTypingTask?.cancel()
        stopTypingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.stopTypingNow()
        }
    }

    public var currentUserId: String? {
        client.session.userId
    }

    // MARK: - Typing

    private func stopTypingNow() async {
        stopTypingTask?.cancel()
        guard isTyping else { return }
        isTyping = false
        if let threadId = selectedThread?.id {
            _ = await client.messaging.stopTyping(threadId: threadId)
        }
    }

    // MARK: - Polling

    public func startPolling() {
        stopPolling()
        guard pollInterval > 0 else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 5))
                guard !Task.isCancelled else { return }
                await self?.poll()
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func poll() async {
        guard let thread = selectedThread else {
            // No conversation open — keep the thread list (previews, unread
            // counts) fresh, like the React component does on incoming messages.
            if let fresh = try? await client.messaging.getThreads(companyAppId: companyAppId) {
                threads = fresh
            }
            return
        }

        // Always take the fetched set: edits, reactions, and read receipts can
        // change without altering count or last-message id.
        if let fetched = try? await client.messaging.getMessages(threadId: thread.id) {
            let hadNewMessages = fetched.count != messages.count
            messages = fetched
            if hadNewMessages, let freshThreads = try? await client.messaging.getThreads(companyAppId: companyAppId) {
                threads = freshThreads
            }
        }
        if let typing = try? await client.messaging.getTypingIndicators(threadId: thread.id) {
            typingIndicators = typing.filter { $0.userId != client.session.userId && $0.isVisible }
        }
    }

    private func refreshMessages() async {
        guard let thread = selectedThread else { return }
        if let fetched = try? await client.messaging.getMessages(threadId: thread.id) {
            messages = fetched
        }
    }

    private func persistDraft() {
        guard let thread = selectedThread else { return }
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            client.messaging.clearDraft(threadId: thread.id)
        } else {
            client.messaging.saveDraft(threadId: thread.id, content: content)
        }
    }
}
