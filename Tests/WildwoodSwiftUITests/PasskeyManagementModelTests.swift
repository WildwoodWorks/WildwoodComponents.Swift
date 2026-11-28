// The passkey management screen's model: the same branches as .NET PasskeyManagementComponent and
// the React/RN screens, with the creation ceremony injected.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct PasskeyManagementModelTests {
    private static let laptop = """
    {"id":"pk-1","friendlyName":"Laptop","isPlatformAuthenticator":true,"isActive":true,"usageCount":1,
     "createdAt":"2026-11-01T00:00:00Z"}
    """

    private func stubEnabled(_ backend: TestBackend, _ enabled: Bool) {
        backend.stub("GET", "/api/webauthn/enabled/app-1", TestStubResponse(json: enabled ? "true" : "false"))
    }

    private func makeModel(_ backend: TestBackend, creator: PasskeyCredentialCreator? = nil) -> WildwoodPasskeyManagementModel {
        WildwoodPasskeyManagementModel(client: makeTestClient(backend, appId: "app-1"), createCredential: creator)
    }

    private static func credential() -> PasskeyRegistrationCredential {
        PasskeyRegistrationCredential(
            id: "new",
            rawId: "new",
            response: PasskeyRegistrationResponse(clientDataJSON: "c", attestationObject: "a", transports: nil)
        )
    }

    @Test func listsPasskeysWhenTheAppEnablesThem() async {
        let backend = TestBackend()
        stubEnabled(backend, true)
        backend.stub("GET", "/api/webauthn/credentials", TestStubResponse(json: "[\(Self.laptop)]"))
        let model = makeModel(backend)

        await model.load()

        #expect(model.loaded && model.appEnabled)
        #expect(model.passkeys.map(\.displayName) == ["Laptop"])
    }

    @Test func neverListsWhenTheAppDisablesPasskeys() async {
        let backend = TestBackend()
        stubEnabled(backend, false)
        let model = makeModel(backend)

        await model.load()

        #expect(model.loaded && !model.appEnabled)
        #expect(!backend.requests().contains { $0.path == "/api/webauthn/credentials" })
    }

    @Test func withoutACeremonyNothingCanBeAdded() async {
        let backend = TestBackend()
        let model = makeModel(backend)

        #expect(!model.canRegister)
        #expect(await model.register(friendlyName: "x") == false)
        #expect(model.errorMessage == "Passkeys cannot be added on this device.")
    }

    @Test func addingRunsOptionsCeremonyCompletionAndReload() async {
        let backend = TestBackend()
        stubEnabled(backend, true)
        backend.stub("GET", "/api/webauthn/credentials", TestStubResponse(json: "[\(Self.laptop)]"))
        backend.stub("POST", "/api/webauthn/register/options", TestStubResponse(json: #"{"challenge":"c"}"#))
        backend.stub("POST", "/api/webauthn/register", TestStubResponse(json: "{}"))
        let model = makeModel(backend) { _ in Self.credential() }
        let changed = CallCounter()
        model.onPasskeysChanged = { changed.bump() }
        await model.load()

        let added = await model.register(friendlyName: " Work key ")

        #expect(added)
        #expect(model.successMessage == "Passkey \"Work key\" added.")
        #expect(changed.count == 1)
        #expect(backend.requests().contains { $0.method == "POST" && $0.path == "/api/webauthn/register" })
    }

    @Test func aCancelledCeremonyReportsNothing() async {
        let backend = TestBackend()
        stubEnabled(backend, true)
        backend.stub("GET", "/api/webauthn/credentials", TestStubResponse(json: "[]"))
        backend.stub("POST", "/api/webauthn/register/options", TestStubResponse(json: #"{"challenge":"c"}"#))
        let model = makeModel(backend) { _ in throw CancellationError() }
        await model.load()

        let added = await model.register(friendlyName: nil)

        #expect(!added)
        #expect(model.errorMessage == nil)
        #expect(!backend.requests().contains { $0.path == "/api/webauthn/register" })
    }

    @Test func theMetaLineReportsNeverUsedAndDropsAnUnparseableDate() {
        let fmt: (Date) -> String = { _ in "D" }
        #expect(PasskeyManagementRules.metaLine(UserPasskey(id: "a", createdAt: "2026-11-01T00:00:00Z"), format: fmt) == "Added D · never used")
        #expect(PasskeyManagementRules.metaLine(UserPasskey(id: "b", lastUsedAt: "2026-11-03T00:00:00", createdAt: "nope"), format: fmt) == "Added  · last used D")
    }
}
