#if os(iOS)
// Streaming-style AI chat interface with session management — parity with
// AIChatComponent. AIProxyComponent (same UI via api/ai/proxy) is below.

import SwiftUI
import PhotosUI
import WildwoodCore

public struct AIChatComponent: View {
    private let configurationId: String
    private let useProxy: Bool
    private let saveToSession: Bool
    private let autoLoadRecentSession: Bool
    private let showTokenUsage: Bool
    private let enableFileUpload: Bool
    private let placeholderText: String
    private let welcomeMessage: String?
    private let onMessageReceived: ((AIMessage) -> Void)?
    private let onError: ((String) -> Void)?

    @Environment(\.wildwoodClient) private var client
    @State private var model: WildwoodChatModel?
    @State private var photoItem: PhotosPickerItem?
    @State private var attachment: (data: Data, name: String)?

    public init(
        configurationId: String,
        useProxy: Bool = false,
        saveToSession: Bool = true,
        autoLoadRecentSession: Bool = false,
        showTokenUsage: Bool = false,
        enableFileUpload: Bool = true,
        placeholderText: String = "Type a message…",
        welcomeMessage: String? = nil,
        onMessageReceived: ((AIMessage) -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        self.configurationId = configurationId
        self.useProxy = useProxy
        self.saveToSession = saveToSession
        self.autoLoadRecentSession = autoLoadRecentSession
        self.showTokenUsage = showTokenUsage
        self.enableFileUpload = enableFileUpload
        self.placeholderText = placeholderText
        self.welcomeMessage = welcomeMessage
        self.onMessageReceived = onMessageReceived
        self.onError = onError
    }

    public var body: some View {
        Group {
            if let model {
                ChatView(
                    model: model,
                    showTokenUsage: showTokenUsage,
                    enableFileUpload: enableFileUpload,
                    placeholderText: placeholderText,
                    welcomeMessage: welcomeMessage,
                    onMessageReceived: onMessageReceived,
                    onError: onError,
                    photoItem: $photoItem,
                    attachment: $attachment
                )
            } else {
                LoadingSpinnerView()
            }
        }
        .task {
            guard model == nil, let client = requireClient(client, component: "AIChatComponent") else { return }
            let created = WildwoodChatModel(
                client: client,
                configurationId: configurationId,
                useProxy: useProxy,
                saveToSession: saveToSession
            )
            model = created
            if autoLoadRecentSession {
                await created.loadRecentSession()
            }
        }
    }
}

/// AI chat routed through the server-side proxy endpoint (api/ai/proxy) —
/// parity with AIProxyComponent.
public struct AIProxyComponent: View {
    private let configurationId: String
    private let saveToSession: Bool
    private let placeholderText: String
    private let onError: ((String) -> Void)?

    public init(
        configurationId: String,
        saveToSession: Bool = false,
        placeholderText: String = "Type a message…",
        onError: ((String) -> Void)? = nil
    ) {
        self.configurationId = configurationId
        self.saveToSession = saveToSession
        self.placeholderText = placeholderText
        self.onError = onError
    }

    public var body: some View {
        AIChatComponent(
            configurationId: configurationId,
            useProxy: true,
            saveToSession: saveToSession,
            placeholderText: placeholderText,
            onError: onError
        )
    }
}

// MARK: - Chat UI

private struct ChatView: View {
    @Bindable var model: WildwoodChatModel
    let showTokenUsage: Bool
    let enableFileUpload: Bool
    let placeholderText: String
    let welcomeMessage: String?
    let onMessageReceived: ((AIMessage) -> Void)?
    let onError: ((String) -> Void)?
    @Binding var photoItem: PhotosPickerItem?
    @Binding var attachment: (data: Data, name: String)?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if let welcomeMessage, model.messages.isEmpty {
                            Text(welcomeMessage)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                        ForEach(model.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                        if model.isSending {
                            HStack {
                                ProgressView()
                                Text("Thinking…").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: model.messages.count) {
                    if let last = model.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        if last.role == "assistant" {
                            onMessageReceived?(last)
                        }
                    }
                }
            }

            if !model.errorMessage.isEmpty {
                ErrorBannerView(message: model.errorMessage) { model.errorMessage = "" }
                    .padding(.horizontal)
                    .onAppear { onError?(model.errorMessage) }
            }

            if showTokenUsage, model.totalTokensUsed > 0 {
                Text("\(model.totalTokensUsed) tokens used")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal)
            }

            inputBar
        }
    }

    @ViewBuilder private var inputBar: some View {
        VStack(spacing: 4) {
            if let attachment {
                HStack {
                    Label(attachment.name, systemImage: "paperclip")
                        .font(.caption)
                    Spacer()
                    Button {
                        self.attachment = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }
            HStack(spacing: 8) {
                if enableFileUpload {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "paperclip")
                    }
                    .onChange(of: photoItem) {
                        Task {
                            if let item = photoItem, let data = try? await item.loadTransferable(type: Data.self) {
                                attachment = (data, "photo.jpg")
                            }
                            photoItem = nil
                        }
                    }
                }
                TextField(placeholderText, text: $model.input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit { send() }
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(model.isSending || (model.input.trimmingCharacters(in: .whitespaces).isEmpty && attachment == nil))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func send() {
        let pending = attachment
        attachment = nil
        Task { await model.send(fileData: pending?.data, fileName: pending?.name) }
    }
}

private struct ChatBubble: View {
    let message: AIMessage

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(isUser ? Color.white : Color.primary)
            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }

    private var isUser: Bool { message.role == "user" }

    private var bubbleBackground: AnyShapeStyle {
        if message.isError {
            return AnyShapeStyle(.red.opacity(0.15))
        }
        return isUser ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary.opacity(0.5))
    }
}
#endif
