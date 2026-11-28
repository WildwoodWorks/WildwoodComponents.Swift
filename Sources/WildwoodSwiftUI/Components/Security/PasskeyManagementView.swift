#if os(iOS)
// The signed-in user's passkeys: add (through the host's ceremony), rename, remove. Parity with
// .NET PasskeyManagementComponent and the React / React Native PasskeyManagementComponent; the
// decisions live in ``WildwoodPasskeyManagementModel``.

import SwiftUI
import WildwoodCore

public struct PasskeyManagementView: View {
    @Environment(\.wildwoodClient) private var client

    private let appId: String?
    private let createCredential: PasskeyCredentialCreator?
    private let onPasskeysChanged: (() -> Void)?

    @State private var model: WildwoodPasskeyManagementModel?
    @State private var newName = ""
    @State private var renamingId: String?
    @State private var renameValue = ""
    @State private var confirmDeleteId: String?

    /// - Parameters:
    ///   - appId: defaults to the client's configured app.
    ///   - createCredential: the platform creation ceremony (an `ASAuthorizationController`
    ///     registration the host runs). Without one, the add control is replaced by a notice.
    ///   - onPasskeysChanged: called after a passkey is added, renamed or removed.
    public init(
        appId: String? = nil,
        createCredential: PasskeyCredentialCreator? = nil,
        onPasskeysChanged: (() -> Void)? = nil
    ) {
        self.appId = appId
        self.createCredential = createCredential
        self.onPasskeysChanged = onPasskeysChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let model {
                content(model)
            } else {
                LoadingSpinnerView(label: "Loading passkeys…")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("passkeys")
        .task {
            guard model == nil, let client = requireClient(client, component: "PasskeyManagementView") else { return }
            let created = WildwoodPasskeyManagementModel(client: client, appId: appId, createCredential: createCredential)
            created.onPasskeysChanged = onPasskeysChanged
            model = created
            await created.load()
        }
    }

    @ViewBuilder private func content(_ model: WildwoodPasskeyManagementModel) -> some View {
        if let error = model.errorMessage {
            ErrorBannerView(message: error) { model.clearMessages() }
                .accessibilityIdentifier("passkey-error")
        }
        if let success = model.successMessage {
            Label(success, systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
                .accessibilityIdentifier("passkey-success")
        }

        if !model.loaded {
            LoadingSpinnerView(label: "Loading passkeys…")
        } else if !model.appEnabled {
            Text("Passkeys are not enabled for this app.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("passkey-notice:app-disabled")
        } else {
            Text("A passkey signs you in with your device's Face ID, Touch ID or passcode instead of a password. A passkey that verifies you counts as two-factor authentication on its own.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if model.passkeys.isEmpty {
                Text("You have no passkeys yet.")
                    .accessibilityIdentifier("passkey-empty")
            } else {
                VStack(spacing: 0) {
                    ForEach(model.passkeys) { passkey in
                        row(passkey, model: model)
                        if passkey.id != model.passkeys.last?.id { Divider() }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                .accessibilityIdentifier("passkey-list")
            }

            if model.canRegister {
                TextField("Name (optional)", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("passkey-new-name")
                Button {
                    Task {
                        if await model.register(friendlyName: newName) { newName = "" }
                    }
                } label: {
                    Label("Add a passkey", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isLoading)
                .accessibilityIdentifier("passkey-add")
            } else {
                Text("Passkeys cannot be added on this device.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("passkey-notice:unsupported")
            }
        }
    }

    @ViewBuilder private func row(_ passkey: UserPasskey, model: WildwoodPasskeyManagementModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if renamingId == passkey.id {
                TextField("Passkey name", text: $renameValue)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("passkey-rename-input")
                HStack {
                    Button("Save") {
                        Task {
                            if await model.rename(passkey, to: renameValue) {
                                renamingId = nil
                                renameValue = ""
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLoading || renameValue.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") {
                        renamingId = nil
                        renameValue = ""
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: passkey.isPlatformAuthenticator ? "faceid" : "key")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(passkey.displayName).font(.body.weight(.semibold))
                        Text(PasskeyManagementRules.metaLine(passkey))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack {
                    Button("Rename") {
                        confirmDeleteId = nil
                        renamingId = passkey.id
                        renameValue = passkey.displayName
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isLoading)
                    .accessibilityLabel("Rename \(passkey.displayName)")
                    if confirmDeleteId == passkey.id {
                        Button("Remove", role: .destructive) {
                            Task {
                                if await model.remove(passkey) { confirmDeleteId = nil }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isLoading)
                        .accessibilityIdentifier("passkey-confirm-delete")
                        Button("Keep") { confirmDeleteId = nil }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Remove", role: .destructive) { confirmDeleteId = passkey.id }
                            .buttonStyle(.bordered)
                            .disabled(model.isLoading)
                            .accessibilityLabel("Remove \(passkey.displayName)")
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("passkey-id:\(passkey.id)")
    }
}
#endif
