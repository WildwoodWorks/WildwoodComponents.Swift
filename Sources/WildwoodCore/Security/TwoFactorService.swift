// Two-factor settings service ported from @wildwood/core/src/security/twoFactorService.ts
// (itself a port of WildwoodComponents.Blazor/Services/TwoFactorSettingsService.cs).

import Foundation

public final class TwoFactorService: Sendable {
    private let http: WildwoodHttpClient

    public init(http: WildwoodHttpClient) {
        self.http = http
    }

    // MARK: - Configuration

    /// App-level 2FA configuration (anonymous endpoint).
    public func getConfiguration(appId: String) async -> TwoFactorConfiguration? {
        try? await http.get("api/twofactor/configuration/\(appId)", skipAuth: true)
    }

    // MARK: - Status

    public func getStatus() async throws -> TwoFactorUserStatus {
        try await http.get("api/twofactor/status")
    }

    // MARK: - Credentials

    public func getCredentials() async -> [TwoFactorCredential] {
        let data: [TwoFactorCredential]? = try? await http.get("api/twofactor/credentials")
        return data ?? []
    }

    public func setPrimaryCredential(credentialId: String) async -> Bool {
        struct Empty: Encodable {}
        do {
            try await http.putVoid("api/twofactor/credentials/\(credentialId)/primary", body: Empty())
            return true
        } catch {
            return false
        }
    }

    public func removeCredential(credentialId: String) async -> Bool {
        do {
            try await http.deleteVoid("api/twofactor/credentials/\(credentialId)")
            return true
        } catch {
            return false
        }
    }

    // MARK: - Email enrollment

    public func enrollEmail(email: String? = nil) async throws -> EmailEnrollmentResult {
        struct EnrollEmailDto: Encodable {
            let email: String?
        }
        return try await http.post("api/twofactor/enroll/email", body: EnrollEmailDto(email: email))
    }

    public func verifyEmailEnrollment(credentialId: String, code: String) async -> Bool {
        struct VerifyDto: Encodable {
            let credentialId: String
            let code: String
        }
        do {
            try await http.postVoid("api/twofactor/enroll/email/verify", body: VerifyDto(credentialId: credentialId, code: code))
            return true
        } catch {
            return false
        }
    }

    // MARK: - Authenticator enrollment

    public func beginAuthenticatorEnrollment(friendlyName: String? = nil) async throws -> AuthenticatorEnrollmentResult {
        struct BeginDto: Encodable {
            let friendlyName: String?
        }
        return try await http.post("api/twofactor/enroll/authenticator", body: BeginDto(friendlyName: friendlyName))
    }

    public func completeAuthenticatorEnrollment(credentialId: String, code: String) async -> Bool {
        struct VerifyDto: Encodable {
            let credentialId: String
            let code: String
        }
        do {
            try await http.postVoid("api/twofactor/enroll/authenticator/verify", body: VerifyDto(credentialId: credentialId, code: code))
            return true
        } catch {
            return false
        }
    }

    // MARK: - Recovery codes

    public func getRecoveryCodeInfo() async throws -> RecoveryCodeInfo {
        try await http.get("api/twofactor/recovery-codes/info")
    }

    public func regenerateRecoveryCodes() async throws -> RegenerateRecoveryCodesResult {
        try await http.post("api/twofactor/recovery-codes/regenerate")
    }

    // MARK: - Trusted devices

    public func getTrustedDevices() async -> [TrustedDevice] {
        let data: [TrustedDevice]? = try? await http.get("api/twofactor/trusted-devices")
        return data ?? []
    }

    public func revokeTrustedDevice(deviceId: String) async -> Bool {
        do {
            try await http.deleteVoid("api/twofactor/trusted-devices/\(deviceId)")
            return true
        } catch {
            return false
        }
    }

    public func revokeAllTrustedDevices() async -> Int {
        struct RevokeAllResponse: Decodable {
            var revokedCount: Int?
        }
        let data: RevokeAllResponse? = try? await http.delete("api/twofactor/trusted-devices")
        return data?.revokedCount ?? 0
    }
}
