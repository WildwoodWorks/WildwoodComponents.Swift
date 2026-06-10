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
}
