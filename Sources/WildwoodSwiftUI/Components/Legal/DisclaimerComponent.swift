#if os(iOS)
// Disclaimer acceptance flow with version-aware consent tracking.
// Parity with DisclaimerComponent in the React Native package.

import SwiftUI
import WildwoodCore

public struct DisclaimerComponent: View {
    @Environment(\.wildwoodClient) private var client

    private let appId: String?
    private let onAllAccepted: (() -> Void)?
    /// Fires once after the first load resolves, with the number of pending
    /// disclaimers found. Lets a gating parent (e.g. the signup flow) advance
    /// when the fetch comes back empty instead of stranding the user.
    private let onLoaded: ((Int) -> Void)?
    private let onError: ((String) -> Void)?

    @State private var isLoading = true
    @State private var isSubmitting = false
    // A load that errors with nothing to show: surface the error plus a retry
    // affordance rather than dead-ending on the "Nothing to accept" state.
    @State private var loadFailed = false
    // Guard so onLoaded fires exactly once, on the first successful load.
    @State private var didNotifyLoaded = false
    @State private var errorMessage: String?
    @State private var disclaimers: [PendingDisclaimerModel] = []
    @State private var accepted: Set<String> = []

    public init(
        appId: String? = nil,
        onAllAccepted: (() -> Void)? = nil,
        onLoaded: ((Int) -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        self.appId = appId
        self.onAllAccepted = onAllAccepted
        self.onLoaded = onLoaded
        self.onError = onError
    }

    public var body: some View {
        Group {
            if isLoading {
                LoadingSpinnerView(label: "Loading disclaimers…")
            } else if loadFailed {
                // Recover from a failed load instead of dead-ending: show the
                // error (when present) alongside a retry button. Critical when
                // this view gates signup / app access.
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage {
                        ErrorBannerView(message: errorMessage) { self.errorMessage = nil }
                    }
                    Button {
                        Task { await load() }
                    } label: {
                        Text("Try again").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if disclaimers.isEmpty {
                ContentUnavailableView(
                    "Nothing to accept",
                    systemImage: "checkmark.seal",
                    description: Text("There are no pending disclaimers.")
                )
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage {
                        ErrorBannerView(message: errorMessage) { self.errorMessage = nil }
                    }

                    ForEach(disclaimers) { disclaimer in
                        DisclaimerCard(
                            disclaimer: disclaimer,
                            isAccepted: accepted.contains(disclaimer.disclaimerId)
                        ) { isOn in
                            if isOn {
                                accepted.insert(disclaimer.disclaimerId)
                            } else {
                                accepted.remove(disclaimer.disclaimerId)
                            }
                        }
                    }

                    Button {
                        Task { await acceptAll() }
                    } label: {
                        if isSubmitting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Accept and Continue").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting || !requiredAccepted)
                }
            }
        }
        .task { await load() }
    }

    private var requiredAccepted: Bool {
        disclaimers.filter(\.isRequired).allSatisfy { accepted.contains($0.disclaimerId) }
    }

    private func load() async {
        guard let client = requireClient(client, component: "DisclaimerComponent") else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.disclaimer.getPendingDisclaimers(appId: appId)
            disclaimers = response.disclaimers
            accepted = Set(response.disclaimers.filter { $0.isAccepted == true }.map(\.disclaimerId))
            loadFailed = false
            errorMessage = nil
            // Notify the gating parent exactly once, on the first successful load.
            if !didNotifyLoaded {
                didNotifyLoaded = true
                onLoaded?(response.disclaimers.count)
            }
        } catch {
            let message = (error as? WildwoodError)?.message ?? error.localizedDescription
            errorMessage = message
            loadFailed = true
            onError?(message)
        }
    }

    private func acceptAll() async {
        guard let client else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let acceptances = disclaimers
                .filter { accepted.contains($0.disclaimerId) }
                .map { DisclaimerAcceptanceInput(disclaimerId: $0.disclaimerId, versionId: $0.versionId) }
            let result = try await client.disclaimer.acceptAllDisclaimers(acceptances, appId: appId)
            if result.success {
                disclaimers.removeAll { accepted.contains($0.disclaimerId) }
                // The Accept button is enabled once all REQUIRED disclaimers are accepted, so a
                // successful submit means the user satisfied the gate and chose to continue — fire
                // onAllAccepted even if unaccepted OPTIONAL disclaimers remain, otherwise a gating
                // parent (the signup flow) would be stranded because the list is still non-empty.
                onAllAccepted?()
            } else {
                let message = result.errorMessage ?? "Failed to record acceptance."
                errorMessage = message
                onError?(message)
            }
        } catch {
            let message = (error as? WildwoodError)?.message ?? error.localizedDescription
            errorMessage = message
            onError?(message)
        }
    }
}

private struct DisclaimerCard: View {
    let disclaimer: PendingDisclaimerModel
    let isAccepted: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(disclaimer.title)
                    .font(.headline)
                Spacer()
                if disclaimer.isRequired {
                    Text("Required")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.red.opacity(0.15), in: Capsule())
                }
            }

            if let changeNotes = disclaimer.changeNotes, !changeNotes.isEmpty {
                Text("What changed: \(changeNotes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(disclaimer.content)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)

            Toggle(isOn: Binding(get: { isAccepted }, set: onToggle)) {
                Text("I have read and accept")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }
}
#endif
