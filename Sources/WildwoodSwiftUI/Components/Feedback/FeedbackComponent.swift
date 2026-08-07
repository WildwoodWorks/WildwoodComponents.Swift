#if os(iOS)
// Feedback widget: typed submissions with duplicate detection and voting —
// parity with FeedbackComponent. Screenshots are passed in by the host app
// (e.g. captured with ImageRenderer) or attached from the photo library.
//
// There is no in-SDK screen capture here, and so no counterpart to the web SDKs'
// html2canvas plumbing: on iOS there is no Content-Security-Policy to work around, no
// third-party script to load, and no screen-share permission prompt to avoid. What DOES
// cross over from that work is the part about honesty — an attachment that cannot be read
// says so instead of doing nothing, and the bytes are encoded as the media type the data
// URL claims, at the size the app's widget configuration asks for.

import SwiftUI
import PhotosUI
import UIKit
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
                    // Clearing the selection below re-enters here with nil; that is not a pick.
                    // A cancelled picker never changes the selection at all, so it never
                    // reaches this point — a cancel stays silent, as it should.
                    guard let item = photoItem else { return }
                    let qualityPct = config?.screenshotQuality ?? 80
                    let maxSizeKb = config?.screenshotMaxSizeKb ?? 0
                    Task {
                        defer { photoItem = nil }
                        do {
                            guard let data = try await item.loadTransferable(type: Data.self) else {
                                // The picker handed back an item it could not then produce bytes
                                // for — an iCloud photo that never downloaded is the usual cause.
                                errorMessage = "That image couldn't be read. It may still be "
                                    + "downloading from iCloud — try again, or pick another."
                                return
                            }
                            // Off the main actor: re-encoding a full-resolution photo is real
                            // work, and the form must stay responsive while it happens.
                            let encoded = await Task.detached(priority: .userInitiated) {
                                FeedbackScreenshotEncoder.jpegDataURL(
                                    from: data, qualityPct: qualityPct, maxSizeKb: maxSizeKb)
                            }.value
                            guard let encoded else {
                                errorMessage = "That file isn't an image this app can attach."
                                return
                            }
                            attachedScreenshot = encoded
                            errorMessage = ""
                        } catch {
                            // Swallowing this is what the old code did, and it left the button
                            // reading "Attach screenshot" with no hint that anything had gone
                            // wrong — indistinguishable from never having tapped it.
                            errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
                        }
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

/// Turn picked image bytes into a size-bounded JPEG data URL.
///
/// Mirrors the web SDKs' `compressScreenshot`, and exists for the same two reasons. The
/// widget's `screenshotMaxSizeKb` and `screenshotQuality` are configured per app and every
/// other stack honours them — attaching an untouched 12-megapixel original ignores both, and
/// the server is entitled to refuse it. And a photo library holds HEIC and PNG as readily as
/// JPEG, so base64-ing the original bytes under a `data:image/jpeg` prefix, as this component
/// used to, states a media type that is simply not true of what follows it.
enum FeedbackScreenshotEncoder {
    /// `maxSizeKb <= 0` means unbounded, matching the web implementation and the server
    /// default of 0.
    static func jpegDataURL(from data: Data, qualityPct: Int, maxSizeKb: Int) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let quality = CGFloat(min(max(Double(qualityPct) / 100.0, 0.1), 1.0))
        guard var jpeg = image.jpegData(compressionQuality: quality) else { return nil }

        if maxSizeKb > 0 {
            let maxBytes = maxSizeKb * 1024
            // Step the quality down first: it costs nothing but fidelity, where scaling costs
            // pixels the reporter may have been pointing at.
            var current = quality
            while jpeg.count > maxBytes, current > 0.1 {
                current -= 0.1
                guard let smaller = image.jpegData(compressionQuality: current) else { break }
                jpeg = smaller
            }
            // Still over at the lowest useful quality: scale by the square root of the overage,
            // which is the linear factor that brings the pixel COUNT down by it.
            if jpeg.count > maxBytes {
                let scale = CGFloat((Double(maxBytes) / Double(jpeg.count)).squareRoot())
                let size = CGSize(width: (image.size.width * scale).rounded(),
                                  height: (image.size.height * scale).rounded())
                // `preparingThumbnail(of:)` rather than a graphics context: Apple documents it
                // as the resize to run off the main thread, which is where this whole function
                // is called from.
                if size.width >= 1, size.height >= 1,
                   let scaled = image.preparingThumbnail(of: size),
                   let scaledData = scaled.jpegData(compressionQuality: 0.7) {
                    jpeg = scaledData
                }
            }
        }

        return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
    }
}
#endif
