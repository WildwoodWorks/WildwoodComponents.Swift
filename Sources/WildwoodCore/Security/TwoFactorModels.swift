// Two-factor security models ported from @wildwood/core/src/security/types.ts
// (itself a port of WildwoodComponents.Shared/Models/TwoFactorSettingsModels.cs).

import Foundation

/// App-level 2FA configuration (api/twofactor/configuration/{appId}).
public struct TwoFactorConfiguration: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var isRequired: Bool
    public var availableMethods: [TwoFactorConfigurationMethod]
    public var codeValiditySeconds: Int
    public var maxAttempts: Int
    public var lockoutMinutes: Int
    public var allowRememberDevice: Bool
    public var rememberDeviceDays: Int

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        isRequired = try c.decodeIfPresent(Bool.self, forKey: .isRequired) ?? false
        availableMethods = try c.decodeIfPresent([TwoFactorConfigurationMethod].self, forKey: .availableMethods) ?? []
        codeValiditySeconds = try c.decodeIfPresent(Int.self, forKey: .codeValiditySeconds) ?? 0
        maxAttempts = try c.decodeIfPresent(Int.self, forKey: .maxAttempts) ?? 0
        lockoutMinutes = try c.decodeIfPresent(Int.self, forKey: .lockoutMinutes) ?? 0
        allowRememberDevice = try c.decodeIfPresent(Bool.self, forKey: .allowRememberDevice) ?? false
        rememberDeviceDays = try c.decodeIfPresent(Int.self, forKey: .rememberDeviceDays) ?? 0
    }
}

public struct TwoFactorConfigurationMethod: Codable, Sendable, Equatable {
    public var providerType: String
    public var name: String
    public var description: String
    public var icon: String
    public var isEnabled: Bool

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        providerType = try c.decodeIfPresent(String.self, forKey: .providerType) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    }
}

public struct TwoFactorUserStatus: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var methodCount: Int
    public var availableMethods: [String]
    public var primaryMethod: String?
    public var recoveryCodesRemaining: Int
    public var trustedDevicesCount: Int
    public var isRequired: Bool
    public var lastUsedAt: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        methodCount = try c.decodeIfPresent(Int.self, forKey: .methodCount) ?? 0
        availableMethods = try c.decodeIfPresent([String].self, forKey: .availableMethods) ?? []
        primaryMethod = try c.decodeIfPresent(String.self, forKey: .primaryMethod)
        recoveryCodesRemaining = try c.decodeIfPresent(Int.self, forKey: .recoveryCodesRemaining) ?? 0
        trustedDevicesCount = try c.decodeIfPresent(Int.self, forKey: .trustedDevicesCount) ?? 0
        isRequired = try c.decodeIfPresent(Bool.self, forKey: .isRequired) ?? false
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    }
}

public struct TwoFactorCredential: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var providerType: String
    public var displayName: String
    public var isPrimary: Bool
    public var isActive: Bool
    public var isVerified: Bool
    public var maskedEmail: String?
    public var lastUsedAt: Date?
    public var usageCount: Int
    public var createdAt: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        providerType = try c.decodeIfPresent(String.self, forKey: .providerType) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        isPrimary = try c.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? false
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        isVerified = try c.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
        maskedEmail = try c.decodeIfPresent(String.self, forKey: .maskedEmail)
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        usageCount = try c.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

public struct EmailEnrollmentResult: Codable, Sendable, Equatable {
    public var success: Bool
    public var credentialId: String
    public var maskedEmail: String
    public var expiresIn: Int
    public var message: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        credentialId = try c.decodeIfPresent(String.self, forKey: .credentialId) ?? ""
        maskedEmail = try c.decodeIfPresent(String.self, forKey: .maskedEmail) ?? ""
        expiresIn = try c.decodeIfPresent(Int.self, forKey: .expiresIn) ?? 0
        message = try c.decodeIfPresent(String.self, forKey: .message)
    }
}

public struct AuthenticatorEnrollmentResult: Codable, Sendable, Equatable {
    public var success: Bool
    public var credentialId: String
    public var secret: String
    public var qrCodeDataUrl: String
    public var manualEntryKey: String
    public var issuer: String?
    public var accountName: String?
    public var message: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        credentialId = try c.decodeIfPresent(String.self, forKey: .credentialId) ?? ""
        secret = try c.decodeIfPresent(String.self, forKey: .secret) ?? ""
        qrCodeDataUrl = try c.decodeIfPresent(String.self, forKey: .qrCodeDataUrl) ?? ""
        manualEntryKey = try c.decodeIfPresent(String.self, forKey: .manualEntryKey) ?? ""
        issuer = try c.decodeIfPresent(String.self, forKey: .issuer)
        accountName = try c.decodeIfPresent(String.self, forKey: .accountName)
        message = try c.decodeIfPresent(String.self, forKey: .message)
    }

    /// otpauth:// URI for native QR rendering when the backend's data URL isn't used.
    public var otpauthUri: String? {
        guard !secret.isEmpty else { return nil }
        let issuerPart = issuer ?? "Wildwood"
        let account = accountName ?? ""
        return "otpauth://totp/\(issuerPart):\(account)?secret=\(secret)&issuer=\(issuerPart)"
    }
}

public struct RecoveryCodeInfo: Codable, Sendable, Equatable {
    public var totalGenerated: Int
    public var remaining: Int
    public var generatedAt: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalGenerated = try c.decodeIfPresent(Int.self, forKey: .totalGenerated) ?? 0
        remaining = try c.decodeIfPresent(Int.self, forKey: .remaining) ?? 0
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt)
    }
}

public struct RegenerateRecoveryCodesResult: Codable, Sendable, Equatable {
    public var success: Bool
    public var codes: [String]
    public var totalCodes: Int
    public var message: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        codes = try c.decodeIfPresent([String].self, forKey: .codes) ?? []
        totalCodes = try c.decodeIfPresent(Int.self, forKey: .totalCodes) ?? 0
        message = try c.decodeIfPresent(String.self, forKey: .message)
    }
}

public struct TrustedDevice: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var deviceName: String
    public var location: String?
    public var lastUsedAt: Date?
    public var usageCount: Int
    public var expiresAt: Date?
    public var createdAt: Date?
    public var isExpired: Bool

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location)
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        usageCount = try c.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        isExpired = try c.decodeIfPresent(Bool.self, forKey: .isExpired) ?? false
    }
}
