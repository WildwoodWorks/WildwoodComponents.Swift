// The signed-in user's passkeys: list, add (through a host-supplied ceremony), rename, remove.
// Port of .NET PasskeyManagementComponent and @wildwood/react-shared usePasskeyManagement.
//
// The creation ceremony is INJECTED, as React Native's is: an `ASAuthorizationController`
// registration needs the app's associated-domains entitlement and its own presentation anchor, so
// the host supplies it and this package takes no AuthenticationServices dependency. Without one,
// passkeys can be listed, renamed and removed, and the view says adding is unavailable here.

import Foundation
import Observation
import WildwoodCore

/// Runs the platform's passkey creation ceremony over the server's registration options (the raw
/// JSON `getPasskeyRegistrationOptions` returns) and answers the credential to register. Throw
/// `CancellationError` when the user cancels — that is reported as no error at all.
public typealias PasskeyCredentialCreator = @MainActor (Data) async throws -> PasskeyRegistrationCredential

@MainActor
@Observable
public final class WildwoodPasskeyManagementModel {
    public private(set) var loaded = false
    public private(set) var appEnabled = false
    public private(set) var passkeys: [UserPasskey] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var successMessage: String?

    /// A creation ceremony was supplied, so ``register(friendlyName:)`` can work.
    public var canRegister: Bool { createCredential != nil }

    @ObservationIgnored private let client: WildwoodClient
    @ObservationIgnored private let appId: String
    @ObservationIgnored private let createCredential: PasskeyCredentialCreator?
    /// Called after a passkey is added, renamed or removed.
    @ObservationIgnored public var onPasskeysChanged: (() -> Void)?

    public init(client: WildwoodClient, appId: String? = nil, createCredential: PasskeyCredentialCreator? = nil) {
        self.client = client
        self.appId = appId ?? client.config.appId ?? ""
        self.createCredential = createCredential
    }

    /// The enabled check, then the list. Safe to call again to refresh.
    public func load() async {
        errorMessage = nil
        guard !appId.isEmpty else {
            loaded = true
            return
        }
        appEnabled = await client.auth.isPasskeyEnabled(appId: appId)
        if appEnabled {
            do {
                passkeys = try await client.auth.listPasskeys(appId: appId)
            } catch {
                errorMessage = Self.message(for: error, fallback: "Could not load your passkeys.")
            }
        }
        loaded = true
    }

    @discardableResult
    public func register(friendlyName: String?) async -> Bool {
        guard let createCredential else {
            errorMessage = "Passkeys cannot be added on this device."
            return false
        }
        let name = friendlyName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return await run(fallback: "The passkey could not be registered.") {
            let options = try await self.client.auth.getPasskeyRegistrationOptions(appId: self.appId, friendlyName: name)
            let credential = try await createCredential(options)
            try await self.client.auth.completePasskeyRegistration(appId: self.appId, credential: credential)
            try await self.reload()
            return "Passkey \"\((name?.isEmpty ?? true) ? "new passkey" : name!)\" added."
        }
    }

    @discardableResult
    public func rename(_ passkey: UserPasskey, to friendlyName: String) async -> Bool {
        let name = friendlyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return await run(fallback: "The passkey could not be renamed.") {
            _ = try await self.client.auth.renamePasskey(id: passkey.id, friendlyName: name)
            try await self.reload()
            return "Passkey renamed."
        }
    }

    @discardableResult
    public func remove(_ passkey: UserPasskey) async -> Bool {
        await run(fallback: "The passkey could not be removed.") {
            try await self.client.auth.deletePasskey(id: passkey.id)
            try await self.reload()
            return "Passkey \"\(passkey.displayName)\" removed."
        }
    }

    public func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    // MARK: - Private

    private func reload() async throws {
        passkeys = try await client.auth.listPasskeys(appId: appId)
    }

    /// One action with the shared loading / error / success bookkeeping.
    private func run(fallback: String, _ action: () async throws -> String) async -> Bool {
        isLoading = true
        errorMessage = nil
        successMessage = nil
        defer { isLoading = false }
        do {
            successMessage = try await action()
            onPasskeysChanged?()
            return true
        } catch is CancellationError {
            // The user dismissed the system sheet: nothing to report.
            return false
        } catch {
            errorMessage = Self.message(for: error, fallback: fallback)
            return false
        }
    }

    /// The API's own message when it sent one, the ceremony's for a ceremony error, else the fallback.
    static func message(for error: any Error, fallback: String) -> String {
        if let wildwood = error as? WildwoodError {
            return wildwood.message.isEmpty ? fallback : wildwood.message
        }
        let described = error.localizedDescription
        return described.isEmpty ? fallback : described
    }
}
