#if os(iOS)
// Real-time messaging UI: thread list, messages, reactions, drafts, typing
// indicators — parity with SecureMessagingComponent.

import SwiftUI
import WildwoodCore

public struct SecureMessagingComponent: View {
    @Environment(\.wildwoodClient) private var client

    private let companyAppId: String
    private let enableReactions: Bool
    private let pollInterval: TimeInterval
    private let onError: ((String) -> Void)?

    @State private var model: WildwoodMessagingModel?

    public init(
        companyAppId: String,
        enableReactions: Bool = true,
        pollInterval: TimeInterval = 5,
        onError: ((String) -> Void)? = nil
    ) {
        self.companyAppId = companyAppId
        self.enableReactions = enableReactions
        self.pollInterval = pollInterval
        self.onError = onError
    }

    public var body: some View {
        Group {
            if let model {
                MessagingSplitView(model: model, enableReactions: enableReactions, onError: onError)
            } else {
                LoadingSpinnerView()
            }
        }
        .task(id: companyAppId) {
            guard model?.companyAppId != companyAppId,
                  let client = requireClient(client, component: "SecureMessagingComponent") else { return }
            model?.closeThread()
            let created = WildwoodMessagingModel(client: client, companyAppId: companyAppId, pollInterval: pollInterval)
            model = created
            await created.loadThreads()
        }
        .onDisappear {
            model?.closeThread()
        }
    }
}

private struct MessagingSplitView: View {
    @Bindable var model: WildwoodMessagingModel
    let enableReactions: Bool
    let onError: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if !model.errorMessage.isEmpty {
                ErrorBannerView(message: model.errorMessage) { model.errorMessage = "" }
                    .padding(.horizontal)
                    .onAppear { onError?(model.errorMessage) }
            }

            if let thread = model.selectedThread {
                conversationView(thread)
            } else {
                threadList
            }
        }
    }

    // MARK: - Thread list

    @ViewBuilder private var threadList: some View {
        if model.isLoading {
            LoadingSpinnerView(label: "Loading conversations…")
        } else if model.threads.isEmpty {
            ContentUnavailableView(
                "No conversations",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Start a new thread to begin messaging.")
            )
        } else {
            List(model.threads) { thread in
                Button {
                    Task { await model.selectThread(thread) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(thread.subject.isEmpty ? "Conversation" : thread.subject)
                                .font(.subheadline.weight(.medium))
                            if let preview = thread.lastMessagePreview {
                                Text(preview)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if thread.unreadCount > 0 {
                            Text("\(thread.unreadCount)")
                                .font(.caption2.weight(.bold))
                                .padding(6)
                                .background(.tint, in: Circle())
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Conversation

    @ViewBuilder private func conversationView(_ thread: MessageThread) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.closeThread()
                } label: {
                    Image(systemName: "chevron.left")
                }
                Text(thread.subject.isEmpty ? "Conversation" : thread.subject)
                    .font(.headline)
                Spacer()
            }
            .padding()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.messages) { message in
                            MessageRow(
                                message: message,
                                isMine: message.senderId == model.currentUserId,
                                enableReactions: enableReactions,
                                onReact: { emoji in
                                    Task { await model.react(to: message, emoji: emoji) }
                                },
                                onDelete: {
                                    Task { await model.deleteMessage(message) }
                                }
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: model.messages.count) {
                    if let last = model.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if !model.typingIndicators.isEmpty {
                HStack {
                    Text("\(model.typingIndicators.map(\.userName).joined(separator: ", ")) typing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }

            HStack(spacing: 8) {
                TextField("Message", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onChange(of: model.draft) {
                        model.onDraftChanged()
                    }
                Button {
                    Task { await model.sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            .background(.bar)
        }
    }
}

private struct MessageRow: View {
    let message: SecureMessage
    let isMine: Bool
    let enableReactions: Bool
    let onReact: (String) -> Void
    let onDelete: () -> Void

    private static let quickReactions = ["👍", "❤️", "😂", "🎉"]

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                if !isMine {
                    Text(message.senderName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(message.isDeleted ? "Message deleted" : message.content)
                    .font(.callout)
                    .italic(message.isDeleted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        isMine ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary.opacity(0.5)),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .foregroundStyle(isMine ? Color.white : Color.primary)
                    .contextMenu {
                        if enableReactions, !message.isDeleted {
                            ForEach(Self.quickReactions, id: \.self) { emoji in
                                Button(emoji) { onReact(emoji) }
                            }
                        }
                        if isMine, !message.isDeleted {
                            Button("Delete", role: .destructive) { onDelete() }
                        }
                    }

                if !message.reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(groupedReactions, id: \.emoji) { group in
                            Text("\(group.emoji) \(group.count)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary.opacity(0.5), in: Capsule())
                        }
                    }
                }

                if message.isEdited {
                    Text("edited")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if !isMine { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }

    private var groupedReactions: [(emoji: String, count: Int)] {
        Dictionary(grouping: message.reactions, by: \.emoji)
            .map { (emoji: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
}
#endif
