#if os(iOS)
// Feedback widget: typed submissions with duplicate detection and voting —
// parity with FeedbackComponent. Screenshots are passed in by the host app
// (e.g. captured with ImageRenderer) or attached from the photo library.

import SwiftUI
import PhotosUI
import WildwoodCore

public struct FeedbackComponent: View {
    @Environment(\.wildwoodClient) private var client

    private let appId: String?
    /// Pre-captured screenshot as a base64 data URL (e.g. from ImageRenderer).
    private let screenshotData: String?
    private let pageContext: String?
    private let onSubmitted: ((SystemFeedback) -> Void)?
    private let onError: ((String) -> Void)?

    @State private var config: FeedbackWidgetConfig?
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage = ""
    @State private var successMessage = ""

    @State private var title = ""
    @State private var descriptionText = ""
    @State private var feedbackType = ""
    @State private var submitterName = ""
    @State private var submitterEmail = ""
    @State private var duplicate: FeedbackDuplicateCheck?
    @State private var photoItem: PhotosPickerItem?
    @State private var attachedScreenshot: String?
    @State private var duplicateCheckTask: Task<Void, Never>?

    public init(
        appId: String? = nil,
        screenshotData: String? = nil,
        pageContext: String? = nil,
        onSubmitted: ((SystemFeedback) -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        self.appId = appId
        self.screenshotData = screenshotData
        self.pageContext = pageContext
        self.onSubmitted = onSubmitted
        self.onError = onError
    }

    public var body: some View {
        Group {
            if isLoading {
                LoadingSpinnerView(label: "Loading feedback form…")
            } else if let config, !config.isEnabled {
                ContentUnavailableView("Feedback is not enabled", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            } else {
                form
            }
        }
        .task { await load() }
    }

    @ViewBuilder private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send Feedback").font(.title2.weight(.bold))

            if !errorMessage.isEmpty {
                ErrorBannerView(message: errorMessage) { errorMessage = "" }
            }
            if !successMessage.isEmpty {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }

            if let types = config?.feedbackTypes, !types.isEmpty {
                Picker("Type", selection: $feedbackType) {
                    ForEach(types, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .onChange(of: title) { scheduleDuplicateCheck() }

            if let duplicate, duplicate.hasPotentialDuplicate {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Someone may have already reported this:", systemImage: "doc.on.doc")
                        .font(.caption)
                    Text(duplicate.duplicateTitle ?? "")
                        .font(.caption.weight(.medium))
                    Button("Me too (+\(duplicate.duplicateVoteCount))") {
                        Task { await voteOnDuplicate(duplicate) }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            TextField("Describe the issue or idea…", text: $descriptionText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4...8)

            if isAnonymous {
                TextField("Your name (optional)", text: $submitterName)
                    .textFieldStyle(.roundedBorder)
                TextField("Your email (optional)", text: $submitterEmail)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            HStack {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(attachedScreenshot == nil ? "Attach screenshot" : "Screenshot attached", systemImage: "photo")
                        .font(.caption)
                }
                .onChange(of: photoItem) {
                    Task {
                        if let item = photoItem, let data = try? await item.loadTransferable(type: Data.self) {
                            attachedScreenshot = "data:image/jpeg;base64,\(data.base64EncodedString())"
                        }
                        photoItem = nil
                    }
                }
                if attachedScreenshot != nil {
                    Button {
                        attachedScreenshot = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Button {
                Task { await submit() }
            } label: {
                if isSubmitting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Submit Feedback").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting || title.isEmpty || descriptionText.isEmpty || screenshotMissing)
        }
    }

    private var isAnonymous: Bool {
        client?.session.isAuthenticated != true
    }

    private var screenshotMissing: Bool {
        (config?.requireScreenshot ?? false) && attachedScreenshot == nil && screenshotData == nil
    }

    private func scheduleDuplicateCheck() {
        guard config?.enableDuplicateDetection == true else { return }
        duplicateCheckTask?.cancel()
        let currentTitle = title
        guard currentTitle.count >= 5 else {
            duplicate = nil
            return
        }
        duplicateCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let client else { return }
            duplicate = try? await client.feedback.checkDuplicate(title: currentTitle, appId: appId)
        }
    }

    private func voteOnDuplicate(_ duplicate: FeedbackDuplicateCheck) async {
        guard let client, let id = duplicate.duplicateId else { return }
        do {
            let result = try await client.feedback.voteFeedback(id: id)
            successMessage = "Thanks! That report now has \(result.voteCount) votes."
            self.duplicate = nil
            title = ""
            descriptionText = ""
        } catch {
            errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
        }
    }

    private func submit() async {
        guard let client else { return }
        errorMessage = ""
        successMessage = ""
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let feedback = try await client.feedback.submitFeedback(
                SubmitFeedbackInput(
                    appId: appId,
                    title: title,
                    description: descriptionText,
                    feedbackType: feedbackType.isEmpty ? (config?.feedbackTypes.first ?? "Bug") : feedbackType,
                    pageUrl: pageContext,
                    screenshotData: attachedScreenshot ?? screenshotData,
                    submitterEmail: submitterEmail.isEmpty ? nil : submitterEmail,
                    submitterName: submitterName.isEmpty ? nil : submitterName
                )
            )
            successMessage = "Feedback submitted. Thank you!"
            title = ""
            descriptionText = ""
            attachedScreenshot = nil
            duplicate = nil
            onSubmitted?(feedback)
        } catch {
            let message = (error as? WildwoodError)?.message ?? error.localizedDescription
            errorMessage = message
            onError?(message)
        }
    }

    private func load() async {
        guard let client = requireClient(client, component: "FeedbackComponent") else { return }
        isLoading = true
        defer { isLoading = false }
        config = try? await client.feedback.getWidgetConfig(appId: appId)
        if feedbackType.isEmpty {
            feedbackType = config?.feedbackTypes.first ?? ""
        }
    }
}
#endif
