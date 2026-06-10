#if os(iOS)
// Streaming-style AI chat interface with session management and server TTS —
// parity with AIChatComponent. AIProxyComponent (same UI via api/ai/proxy) is below.

import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import WildwoodCore

public struct AIChatComponent: View {
    private let configurationId: String
    private let useProxy: Bool
    private let saveToSession: Bool
    private let autoLoadRecentSession: Bool
    private let showTokenUsage: Bool
    private let enableFileUpload: Bool
    private let enableTextToSpeech: Bool
    private let placeholderText: String
    private let welcomeMessage: String?
    private let requestTimeout: TimeInterval?
    private let onMessageReceived: ((AIMessage) -> Void)?
    private let onError: ((String) -> Void)?

    @Environment(\.wildwoodClient) private var client
    @State private var model: WildwoodChatModel?

    public init(
        configurationId: String,
        useProxy: Bool = false,
        saveToSession: Bool = true,
        autoLoadRecentSession: Bool = false,
        showTokenUsage: Bool = false,
        enableFileUpload: Bool = true,
        enableTextToSpeech: Bool = true,
        placeholderText: String = "Type a message…",
        welcomeMessage: String? = nil,
        requestTimeout: TimeInterval? = nil,
        onMessageReceived: ((AIMessage) -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        self.configurationId = configurationId
        self.useProxy = useProxy
        self.saveToSession = saveToSession
        self.autoLoadRecentSession = autoLoadRecentSession
        self.showTokenUsage = showTokenUsage
        self.enableFileUpload = enableFileUpload
        self.enableTextToSpeech = enableTextToSpeech
        self.placeholderText = placeholderText
        self.welcomeMessage = welcomeMessage
        self.requestTimeout = requestTimeout
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
                    enableTextToSpeech: enableTextToSpeech,
                    placeholderText: placeholderText,
                    welcomeMessage: welcomeMessage,
                    onMessageReceived: onMessageReceived,
                    onError: onError
                )
            } else {
                LoadingSpinnerView()
            }
        }
        .task(id: configurationId) {
            // Rebuild the model when the configuration changes (React parity:
            // hooks re-run on prop change).
            guard model?.configurationId != configurationId,
                  let client = requireClient(client, component: "AIChatComponent") else { return }
            let created = WildwoodChatModel(
                client: client,
                configurationId: configurationId,
                useProxy: useProxy,
                saveToSession: saveToSession,
                requestTimeout: requestTimeout
            )
            model = created
            await created.loadConfiguration()
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
    private let requestTimeout: TimeInterval?
    private let onError: ((String) -> Void)?

    public init(
        configurationId: String,
        saveToSession: Bool = false,
        placeholderText: String = "Type a message…",
        requestTimeout: TimeInterval? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        self.configurationId = configurationId
        self.saveToSession = saveToSession
        self.placeholderText = placeholderText
        self.requestTimeout = requestTimeout
        self.onError = onError
    }

    public var body: some View {
        AIChatComponent(
            configurationId: configurationId,
            useProxy: true,
            saveToSession: saveToSession,
            placeholderText: placeholderText,
            requestTimeout: requestTimeout,
            onError: onError
        )
    }
}

// MARK: - Chat UI

private struct ChatView: View {
    @Bindable var model: WildwoodChatModel
    let showTokenUsage: Bool
    let enableFileUpload: Bool
    let enableTextToSpeech: Bool
    let placeholderText: String
    let welcomeMessage: String?
    let onMessageReceived: ((AIMessage) -> Void)?
    let onError: ((String) -> Void)?

    @State private var photoItem: PhotosPickerItem?
    @State private var attachment: (data: Data, name: String)?
    @State private var showSessions = false
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        VStack(spacing: 0) {
            if model.saveToSession {
                sessionBar
            }

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
                            ChatBubble(
                                message: message,
                                canSpeak: enableTextToSpeech && model.isTTSEnabled && message.role == "assistant" && !message.isError,
                                onSpeak: { speak(message) }
                            )
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
        .sheet(isPresented: $showSessions) {
            SessionListSheet(model: model, isPresented: $showSessions)
        }
    }

    @ViewBuilder private var sessionBar: some View {
        HStack {
            Button {
                Task {
                    await model.loadSessions()
                    showSessions = true
                }
            } label: {
                Label("Sessions", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
            }
            Spacer()
            Button {
                model.startNewSession()
            } label: {
                Label("New Chat", systemImage: "square.and.pencil")
                    .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
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
        Task {
            if let reply = await model.send(fileData: pending?.data, fileName: pending?.name) {
                onMessageReceived?(reply)
            }
        }
    }

    private func speak(_ message: AIMessage) {
        Task {
            guard let audioData = await model.synthesizeSpeech(for: message),
                  let player = try? AVAudioPlayer(data: audioData) else {
                model.errorMessage = "Speech synthesis failed."
                return
            }
            audioPlayer = player
            player.play()
        }
    }
}

private struct SessionListSheet: View {
    @Bindable var model: WildwoodChatModel
    @Binding var isPresented: Bool

    @State private var renamingSession: AISessionSummary?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.sessions) { session in
                    Button {
                        Task {
                            await model.loadSession(session.id)
                            isPresented = false
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.sessionName.isEmpty ? "Untitled" : session.sessionName)
                                .font(.subheadline.weight(session.id == model.sessionId ? .semibold : .regular))
                            HStack {
                                Text("\(session.messageCount) messages")
                                if let preview = session.lastMessagePreview {
                                    Text("· \(preview)").lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task { await model.deleteSession(session.id) }
                        }
                        Button("Rename") {
                            renamingSession = session
                            newName = session.sessionName
                        }
                    }
                }
            }
            .overlay {
                if model.sessions.isEmpty {
                    ContentUnavailableView("No sessions yet", systemImage: "clock.arrow.circlepath")
                }
            }
            .navigationTitle("Chat Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
            .alert("Rename Session", isPresented: Binding(
                get: { renamingSession != nil },
                set: { if !$0 { renamingSession = nil } }
            )) {
                TextField("Name", text: $newName)
                Button("Save") {
                    if let session = renamingSession, !newName.isEmpty {
                        Task { await model.renameSession(session.id, to: newName) }
                    }
                    renamingSession = nil
                }
                Button("Cancel", role: .cancel) { renamingSession = nil }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ChatBubble: View {
    let message: AIMessage
    let canSpeak: Bool
    let onSpeak: () -> Void

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.content
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    if canSpeak {
                        Button {
                            onSpeak()
                        } label: {
                            Label("Read Aloud", systemImage: "speaker.wave.2")
                        }
                    }
                }
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
