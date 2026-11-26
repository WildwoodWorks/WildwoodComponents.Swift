// View-model state machine tests (cross-platform — no SwiftUI).

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct AuthModelTests {
    private func makeModel(onSuccess: ((AuthenticationResponse) -> Void)? = nil) -> WildwoodAuthModel {
        let client = WildwoodClient(
            config: WildwoodConfig(baseUrl: "https://unit.test", appId: "app-1", storage: .memory)
        )
        return WildwoodAuthModel(client: client, appId: "app-1", onAuthenticationSuccess: onSuccess)
    }

    @Test func twoFactorResponseRoutesToChallengeView() {
        let model = makeModel()
        model.processAuthResponse(
            AuthenticationResponse(
                requiresTwoFactor: true,
                twoFactorSessionId: "s-1",
                availableTwoFactorMethods: [TwoFactorMethodInfo(providerType: "Email", name: "Email")],
                defaultTwoFactorMethod: "Email"
            )
        )
        #expect(model.view == .twoFactor)
        #expect(model.twoFactorSessionId == "s-1")
        #expect(model.selectedTwoFactorMethod == "Email")
    }

    @Test func passwordResetResponseRoutesToResetView() {
        let model = makeModel()
        model.processAuthResponse(AuthenticationResponse(jwtToken: "jwt", requiresPasswordReset: true))
        #expect(model.view == .passwordReset)
        #expect(model.pendingAuth != nil)
    }

    @Test func cleanResponseCompletesAuthentication() {
        var succeeded: AuthenticationResponse?
        let model = makeModel { succeeded = $0 }
        model.processAuthResponse(AuthenticationResponse(userId: "u1", email: "a@b.c", jwtToken: "jwt", refreshToken: "r"))
        #expect(model.view == .login)
        #expect(succeeded?.userId == "u1")
    }

    @Test func toggleModeClearsSensitiveState() {
        let model = makeModel()
        model.password = "secret"
        model.twoFactorCode = "123456"
        model.toggleMode()
        #expect(model.view == .register)
        #expect(model.password.isEmpty)
        #expect(model.twoFactorCode.isEmpty)
        model.toggleMode()
        #expect(model.view == .login)
    }

    @Test func registrationPasswordMismatchSetsError() async {
        let model = makeModel()
        model.regEmail = "a@b.c"
        model.regPassword = "one"
        model.regConfirmPassword = "two"
        await model.handleRegister()
        #expect(model.errorMessage == "Passwords do not match")
    }

    // MARK: - Required two-factor enrollment

    private func makeModel(backend: TestBackend, onSuccess: ((AuthenticationResponse) -> Void)? = nil) -> (WildwoodAuthModel, WildwoodClient) {
        let client = WildwoodClient(
            config: WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false, storage: .memory),
            urlSession: backend.makeSession()
        )
        return (WildwoodAuthModel(client: client, appId: "app-1", onAuthenticationSuccess: onSuccess), client)
    }

    @Test func enrollmentRequiredHoldsTheUserOnSetup() {
        var succeeded: AuthenticationResponse?
        let client = WildwoodClient(
            config: WildwoodConfig(baseUrl: "https://unit.test", appId: "app-1", storage: .memory)
        )
        let model = WildwoodAuthModel(client: client, appId: "app-1", onAuthenticationSuccess: { succeeded = $0 })

        model.processAuthResponse(
            AuthenticationResponse(userId: "u1", jwtToken: "jwt", refreshToken: "r", requiresTwoFactorEnrollment: true)
        )

        #expect(model.view == .twoFactorEnrollment)
        #expect(model.resolveTitle() == "Set Up Two-Factor Authentication")
        // Signed in (enrollment calls need the token) but restricted, and not reported as success.
        #expect(client.session.accessToken == "jwt")
        #expect(client.session.requiresTwoFactorEnrollment)
        #expect(succeeded == nil)
    }

    @Test func completingEnrollmentRefreshesAndReportsSuccess() async {
        let backend = TestBackend()
        var succeeded: AuthenticationResponse?
        let (model, client) = makeModel(backend: backend) { succeeded = $0 }
        client.storage.setItem(WildwoodStorageKeys.refreshToken, "r1")
        model.processAuthResponse(
            AuthenticationResponse(userId: "u1", jwtToken: "restricted", refreshToken: "r1", requiresTwoFactorEnrollment: true)
        )
        backend.stub("POST", "/api/auth/refresh-token", TestStubResponse(json: """
        {"userId":"u1","jwtToken":"unrestricted","refreshToken":"r2","requiresTwoFactorEnrollment":false}
        """))

        await model.handleTwoFactorEnrollmentCompleted()

        #expect(model.view == .login)
        #expect(succeeded?.jwtToken == "unrestricted")
        #expect(!client.session.requiresTwoFactorEnrollment)
    }

    @Test func completingBeforeEnrollingKeepsTheUserOnSetup() async {
        let backend = TestBackend()
        var succeeded: AuthenticationResponse?
        let (model, client) = makeModel(backend: backend) { succeeded = $0 }
        client.storage.setItem(WildwoodStorageKeys.refreshToken, "r1")
        model.processAuthResponse(
            AuthenticationResponse(userId: "u1", jwtToken: "restricted", refreshToken: "r1", requiresTwoFactorEnrollment: true)
        )
        backend.stub("POST", "/api/auth/refresh-token", TestStubResponse(json: """
        {"userId":"u1","jwtToken":"still-restricted","refreshToken":"r2","requiresTwoFactorEnrollment":true}
        """))

        await model.handleTwoFactorEnrollmentCompleted()

        #expect(model.view == .twoFactorEnrollment)
        #expect(!model.errorMessage.isEmpty)
        #expect(succeeded == nil)
    }

    // The registration gate can collapse .register to .login during render, so the
    // component titles the view it actually shows rather than the model's own.
    @Test func resolveTitleForAViewIgnoresTheInternalView() {
        let model = makeModel()
        model.toggleMode()
        #expect(model.view == .register)
        #expect(model.resolveTitle(for: .login) == "Sign In")
        #expect(model.resolveTitle() == "Create Account")
    }
}
