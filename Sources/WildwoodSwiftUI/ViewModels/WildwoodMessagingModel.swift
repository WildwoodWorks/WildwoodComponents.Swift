// Secure messaging state — view-model equivalent of react-shared's
// useMessaging. Real-time updates use foreground polling (the JS stacks use
// SignalR; the protocol seam in MessagingService keeps a future native
// SignalR adapter non-breaking).

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

    public init(client: WildwoodClient, companyAppId: String, pollInterval: TimeInterval = 5) {
        self.client = client
        self.companyAppId = companyAppId
        self.pollInterval = pollInterval
    }

    public func loadThreads() async {
        isLoading = true
        defer { isLoading = false }
        threads = await client.messaging.getThreads(companyAppId: companyAppId)
    }

    public func selectThread(_ thread: MessageThread) async {
        // Persist the draft of the thread we're leaving.
        persistDraft()

        selectedThread = thread
        messages = await client.messaging.getMessages(threadId: thread.id)
        draft = client.messaging.getDraft(threadId: thread.id)?.content ?? ""
        _ = await client.messaging.markThreadAsRead(threadId: thread.id)
        startPolling()
    }

    public func closeThread() {
        persistDraft()
        stopPolling()
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

    public func saveDraft() {
        persistDraft()
    }

    public var currentUserId: String? {
        client.session.userId
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
        guard let thread = selectedThread else { return }
        async let newMessages = client.messaging.getMessages(threadId: thread.id)
        async let typing = client.messaging.getTypingIndicators(threadId: thread.id)
        let fetched = await newMessages
        if fetched.count != messages.count || fetched.last?.id != messages.last?.id {
            messages = fetched
        }
        typingIndicators = await typing.filter { $0.userId != client.session.userId && $0.isVisible }
    }

    private func refreshMessages() async {
        guard let thread = selectedThread else { return }
        messages = await client.messaging.getMessages(threadId: thread.id)
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
