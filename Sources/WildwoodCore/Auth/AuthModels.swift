// Auth models ported from @wildwood/core/src/auth/types.ts (which mirrors
// WildwoodComponents.Shared/Models/WildwoodAuthModels.cs).

import Foundation

public struct LoginRequest: Sendable, Equatable {
    public var username: String
    public var email: String?
    public var password: String?
    public var providerName: String?
    public var providerToken: String?
    public var appId: String?
    public var rememberMe: Bool?
    public var captchaResponse: String?
    public var licenseToken: String?
    public var platform: String?
    public var deviceInfo: String?
    public var trustedDeviceToken: String?
    public var appVersion: String?

    public init(
        username: String = "",
        email: String? = nil,
        password: String? = nil,
        providerName: String? = nil,
        providerToken: String? = nil,
        appId: String? = nil,
        rememberMe: Bool? = nil,
        captchaResponse: String? = nil,
        licenseToken: String? = nil,
        platform: String? = nil,
        deviceInfo: String? = nil,
        trustedDeviceToken: String? = nil,
        appVersion: String? = nil
    ) {
        self.username = username
        self.email = email
        self.password = password
        self.providerName = providerName
        self.providerToken = providerToken
        self.appId = appId
        self.rememberMe = rememberMe
        self.captchaResponse = captchaResponse
        self.licenseToken = licenseToken
        self.platform = platform
        self.deviceInfo = deviceInfo
        self.trustedDeviceToken = trustedDeviceToken
        self.appVersion = appVersion
    }
}

public struct RegistrationRequest: Codable, Sendable, Equatable {
    public var email: String
    public var username: String?
    public var firstName: String
    public var lastName: String
    public var password: String?
    public var confirmPassword: String?
    public var providerName: String?
    public var providerToken: String?
    public var appId: String
    public var platform: String?
    public var deviceInfo: String?
    public var phoneNumber: String?
    public var captchaResponse: String?
    public var licenseToken: String?
    public var registrationToken: String?

    public init(
        email: String,
        username: String? = nil,
        firstName: String,
        lastName: String,
        password: String? = nil,
        confirmPassword: String? = nil,
        providerName: String? = nil,
        providerToken: String? = nil,
        appId: String,
        platform: String? = nil,
        deviceInfo: String? = nil,
        phoneNumber: String? = nil,
        captchaResponse: String? = nil,
        licenseToken: String? = nil,
        registrationToken: String? = nil
    ) {
        self.email = email
        self.username = username
        self.firstName = firstName
        self.lastName = lastName
        self.password = password
        self.confirmPassword = confirmPassword
        self.providerName = providerName
        self.providerToken = providerToken
        self.appId = appId
        self.platform = platform
        self.deviceInfo = deviceInfo
        self.phoneNumber = phoneNumber
        self.captchaResponse = captchaResponse
        self.licenseToken = licenseToken
        self.registrationToken = registrationToken
    }
}

/// Collected registration form data (not yet submitted). Used by deferred registration flows.
public struct RegistrationFormData: Sendable, Equatable {
    public var firstName: String
    public var lastName: String
    public var username: String
    public var email: String
    public var password: String
    public var registrationToken: String?
    public var useToken: Bool

    public init(
        firstName: String = "",
        lastName: String = "",
        username: String = "",
        email: String = "",
        password: String = "",
        registrationToken: String? = nil,
        useToken: Bool = false
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.username = username
        self.email = email
        self.password = password
        self.registrationToken = registrationToken
        self.useToken = useToken
    }
}

public struct AuthenticationResponse: Codable, Sendable, Equatable {
    public var id: String
    public var userId: String
    public var firstName: String
    public var lastName: String
    public var email: String
    public var jwtToken: String
    public var refreshToken: String
    public var requiresTwoFactor: Bool
    public var requiresPasswordReset: Bool
    public var roles: [String]
    public var companyId: String?
    public var permissions: [String]
    public var twoFactorSessionId: String?
    public var availableTwoFactorMethods: [TwoFactorMethodInfo]?
    public var defaultTwoFactorMethod: String?
    public var twoFactorSessionExpiresIn: Int?
    public var requiresDisclaimerAcceptance: Bool
    public var pendingDisclaimers: [PendingDisclaimerModel]?

    public init(
        id: String = "",
        userId: String = "",
        firstName: String = "",
        lastName: String = "",
        email: String = "",
        jwtToken: String = "",
        refreshToken: String = "",
        requiresTwoFactor: Bool = false,
        requiresPasswordReset: Bool = false,
        roles: [String] = [],
        companyId: String? = nil,
        permissions: [String] = [],
        twoFactorSessionId: String? = nil,
        availableTwoFactorMethods: [TwoFactorMethodInfo]? = nil,
        defaultTwoFactorMethod: String? = nil,
        twoFactorSessionExpiresIn: Int? = nil,
        requiresDisclaimerAcceptance: Bool = false,
        pendingDisclaimers: [PendingDisclaimerModel]? = nil
    ) {
        self.id = id
        self.userId = userId
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.jwtToken = jwtToken
        self.refreshToken = refreshToken
        self.requiresTwoFactor = requiresTwoFactor
        self.requiresPasswordReset = requiresPasswordReset
        self.roles = roles
        self.companyId = companyId
        self.permissions = permissions
        self.twoFactorSessionId = twoFactorSessionId
        self.availableTwoFactorMethods = availableTwoFactorMethods
        self.defaultTwoFactorMethod = defaultTwoFactorMethod
        self.twoFactorSessionExpiresIn = twoFactorSessionExpiresIn
        self.requiresDisclaimerAcceptance = requiresDisclaimerAcceptance
        self.pendingDisclaimers = pendingDisclaimers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        userId = try container.decodeIfPresent(String.self, forKey: .userId) ?? ""
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        jwtToken = try container.decodeIfPresent(String.self, forKey: .jwtToken) ?? ""
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken) ?? ""
        requiresTwoFactor = try container.decodeIfPresent(Bool.self, forKey: .requiresTwoFactor) ?? false
        requiresPasswordReset = try container.decodeIfPresent(Bool.self, forKey: .requiresPasswordReset) ?? false
        roles = try container.decodeIfPresent([String].self, forKey: .roles) ?? []
        companyId = try container.decodeIfPresent(String.self, forKey: .companyId)
        permissions = try container.decodeIfPresent([String].self, forKey: .permissions) ?? []
        twoFactorSessionId = try container.decodeIfPresent(String.self, forKey: .twoFactorSessionId)
        availableTwoFactorMethods = try container.decodeIfPresent([TwoFactorMethodInfo].self, forKey: .availableTwoFactorMethods)
        defaultTwoFactorMethod = try container.decodeIfPresent(String.self, forKey: .defaultTwoFactorMethod)
        twoFactorSessionExpiresIn = try container.decodeIfPresent(Int.self, forKey: .twoFactorSessionExpiresIn)
        requiresDisclaimerAcceptance = try container.decodeIfPresent(Bool.self, forKey: .requiresDisclaimerAcceptance) ?? false
        pendingDisclaimers = try container.decodeIfPresent([PendingDisclaimerModel].self, forKey: .pendingDisclaimers)
    }
}

public struct TwoFactorMethodInfo: Codable, Sendable, Equatable {
    public var providerType: String
    public var name: String
    public var icon: String
    public var maskedDestination: String?

    public init(providerType: String, name: String, icon: String = "", maskedDestination: String? = nil) {
        self.providerType = providerType
        self.name = name
        self.icon = icon
        self.maskedDestination = maskedDestination
    }
}

public struct TwoFactorVerifyRequest: Codable, Sendable, Equatable {
    public var sessionId: String
    public var code: String
    public var providerType: String
    public var rememberDevice: Bool?
    public var deviceFingerprint: String?
    public var deviceName: String?

    public init(
        sessionId: String,
        code: String,
        providerType: String,
        rememberDevice: Bool? = nil,
        deviceFingerprint: String? = nil,
        deviceName: String? = nil
    ) {
        self.sessionId = sessionId
        self.code = code
        self.providerType = providerType
        self.rememberDevice = rememberDevice
        self.deviceFingerprint = deviceFingerprint
        self.deviceName = deviceName
    }
}

public struct TwoFactorVerifyResponse: Codable, Sendable, Equatable {
    public var success: Bool
    public var errorMessage: String?
    public var authResponse: AuthenticationResponse?
    public var trustedDeviceToken: String?

    public init(success: Bool, errorMessage: String? = nil, authResponse: AuthenticationResponse? = nil, trustedDeviceToken: String? = nil) {
        self.success = success
        self.errorMessage = errorMessage
        self.authResponse = authResponse
        self.trustedDeviceToken = trustedDeviceToken
    }
}

public struct TwoFactorSendCodeResponse: Codable, Sendable, Equatable {
    public var success: Bool
    public var maskedDestination: String?
    public var expiresInSeconds: Int?
    public var errorMessage: String?

    public init(success: Bool, maskedDestination: String? = nil, expiresInSeconds: Int? = nil, errorMessage: String? = nil) {
        self.success = success
        self.maskedDestination = maskedDestination
        self.expiresInSeconds = expiresInSeconds
        self.errorMessage = errorMessage
    }
}

public struct AuthProvider: Codable, Sendable, Equatable, Identifiable {
    public var name: String
    public var displayName: String
    public var icon: String
    public var isEnabled: Bool
    public var clientId: String?
    public var redirectUri: String?

    public var id: String { name }

    public init(name: String, displayName: String, icon: String = "", isEnabled: Bool = true, clientId: String? = nil, redirectUri: String? = nil) {
        self.name = name
        self.displayName = displayName
        self.icon = icon
        self.isEnabled = isEnabled
        self.clientId = clientId
        self.redirectUri = redirectUri
    }
}

public struct AuthProviderDetails: Codable, Sendable, Equatable {
    public var id: String
    public var providerName: String
    public var displayName: String
    public var icon: String?
    public var isEnabled: Bool
    public var displayOrder: Int?
    public var buttonText: String?
    public var buttonColor: String?
    public var clientId: String?
    public var redirectUri: String?
    public var authUrl: String?
    public var tokenUrl: String?
    public var scope: String?
}

public struct AppComponentAuthProvidersResponse: Codable, Sendable {
    public var id: String?
    public var appId: String?
    public var isEnabled: Bool?
    public var defaultProvider: String?
    public var allowLocalAuth: Bool?
    public var requireEmailVerification: Bool?
    public var allowTokenRegistration: Bool?
    public var allowOpenRegistration: Bool?
    public var allowPasswordReset: Bool?
    public var passwordMinimumLength: Int?
    public var passwordRequireDigit: Bool?
    public var passwordRequireLowercase: Bool?
    public var passwordRequireUppercase: Bool?
    public var passwordRequireSpecialChar: Bool?
    public var passwordHistoryLimit: Int?
    public var passwordExpiryDays: Int?
    public var authProviders: [AuthProviderDetails]?
}

public struct AuthenticationConfiguration: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var defaultProvider: String?
    public var allowLocalAuth: Bool
    public var requireEmailVerification: Bool
    public var allowPasswordReset: Bool
    public var showDetailedErrors: Bool
    public var allowTokenRegistration: Bool
    public var allowOpenRegistration: Bool
    public var defaultPricingModelId: String?
    public var defaultPricingModelName: String?
    public var requireEmailVerificationForOpenRegistration: Bool
    public var hasEmailConfiguration: Bool
    public var registrationRateLimitPerHour: Int
    public var registrationRateLimitPerDay: Int
    public var registrationRateLimitPerIpPerHour: Int
    public var passwordMinimumLength: Int
    public var passwordRequireDigit: Bool
    public var passwordRequireLowercase: Bool
    public var passwordRequireUppercase: Bool
    public var passwordRequireSpecialChar: Bool
    public var passwordHistoryLimit: Int
    public var passwordExpiryDays: Int

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        defaultProvider = try c.decodeIfPresent(String.self, forKey: .defaultProvider)
        allowLocalAuth = try c.decodeIfPresent(Bool.self, forKey: .allowLocalAuth) ?? true
        requireEmailVerification = try c.decodeIfPresent(Bool.self, forKey: .requireEmailVerification) ?? false
        allowPasswordReset = try c.decodeIfPresent(Bool.self, forKey: .allowPasswordReset) ?? true
        showDetailedErrors = try c.decodeIfPresent(Bool.self, forKey: .showDetailedErrors) ?? false
        allowTokenRegistration = try c.decodeIfPresent(Bool.self, forKey: .allowTokenRegistration) ?? false
        allowOpenRegistration = try c.decodeIfPresent(Bool.self, forKey: .allowOpenRegistration) ?? false
        defaultPricingModelId = try c.decodeIfPresent(String.self, forKey: .defaultPricingModelId)
        defaultPricingModelName = try c.decodeIfPresent(String.self, forKey: .defaultPricingModelName)
        requireEmailVerificationForOpenRegistration = try c.decodeIfPresent(Bool.self, forKey: .requireEmailVerificationForOpenRegistration) ?? false
        hasEmailConfiguration = try c.decodeIfPresent(Bool.self, forKey: .hasEmailConfiguration) ?? false
        registrationRateLimitPerHour = try c.decodeIfPresent(Int.self, forKey: .registrationRateLimitPerHour) ?? 0
        registrationRateLimitPerDay = try c.decodeIfPresent(Int.self, forKey: .registrationRateLimitPerDay) ?? 0
        registrationRateLimitPerIpPerHour = try c.decodeIfPresent(Int.self, forKey: .registrationRateLimitPerIpPerHour) ?? 0
        passwordMinimumLength = try c.decodeIfPresent(Int.self, forKey: .passwordMinimumLength) ?? 8
        passwordRequireDigit = try c.decodeIfPresent(Bool.self, forKey: .passwordRequireDigit) ?? false
        passwordRequireLowercase = try c.decodeIfPresent(Bool.self, forKey: .passwordRequireLowercase) ?? false
        passwordRequireUppercase = try c.decodeIfPresent(Bool.self, forKey: .passwordRequireUppercase) ?? false
        passwordRequireSpecialChar = try c.decodeIfPresent(Bool.self, forKey: .passwordRequireSpecialChar) ?? false
        passwordHistoryLimit = try c.decodeIfPresent(Int.self, forKey: .passwordHistoryLimit) ?? 0
        passwordExpiryDays = try c.decodeIfPresent(Int.self, forKey: .passwordExpiryDays) ?? 0
    }
}

public struct CaptchaConfiguration: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var providerType: String
    public var siteKey: String?
    public var minimumScore: Double
    public var requireForLogin: Bool
    public var requireForRegistration: Bool
    public var requireForPasswordReset: Bool

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        providerType = try c.decodeIfPresent(String.self, forKey: .providerType) ?? ""
        siteKey = try c.decodeIfPresent(String.self, forKey: .siteKey)
        minimumScore = try c.decodeIfPresent(Double.self, forKey: .minimumScore) ?? 0
        requireForLogin = try c.decodeIfPresent(Bool.self, forKey: .requireForLogin) ?? false
        requireForRegistration = try c.decodeIfPresent(Bool.self, forKey: .requireForRegistration) ?? false
        requireForPasswordReset = try c.decodeIfPresent(Bool.self, forKey: .requireForPasswordReset) ?? false
    }
}

public struct ValidateRegistrationRequest: Sendable, Equatable {
    public var username: String?
    public var email: String
    public var password: String
    public var token: String?
    public var appId: String

    public init(username: String? = nil, email: String, password: String, token: String? = nil, appId: String) {
        self.username = username
        self.email = email
        self.password = password
        self.token = token
        self.appId = appId
    }
}

public struct ValidateRegistrationResponse: Codable, Sendable, Equatable {
    public var usernameAvailable: Bool
    public var emailAvailable: Bool
    public var passwordValid: Bool
    public var passwordErrors: [String]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        usernameAvailable = try c.decodeIfPresent(Bool.self, forKey: .usernameAvailable) ?? false
        emailAvailable = try c.decodeIfPresent(Bool.self, forKey: .emailAvailable) ?? false
        passwordValid = try c.decodeIfPresent(Bool.self, forKey: .passwordValid) ?? false
        passwordErrors = try c.decodeIfPresent([String].self, forKey: .passwordErrors) ?? []
    }
}

/// Result of open (no-token) registration — no tokens are returned; log in afterwards.
public struct OpenRegistrationResult: Codable, Sendable, Equatable {
    public var success: Bool
    public var message: String
    public var userId: String?
    public var companyClientId: String?
    public var errorCode: String?
    public var requiresStripeSetup: Bool?
    public var requiresPaymentSetup: Bool?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
        companyClientId = try c.decodeIfPresent(String.self, forKey: .companyClientId)
        errorCode = try c.decodeIfPresent(String.self, forKey: .errorCode)
        requiresStripeSetup = try c.decodeIfPresent(Bool.self, forKey: .requiresStripeSetup)
        requiresPaymentSetup = try c.decodeIfPresent(Bool.self, forKey: .requiresPaymentSetup)
    }
}

public struct PendingDisclaimerModel: Codable, Sendable, Equatable, Identifiable {
    public var disclaimerId: String
    public var versionId: String
    public var title: String
    public var disclaimerType: String?
    public var versionNumber: Int?
    public var content: String
    public var contentFormat: String?
    public var isRequired: Bool
    public var previouslyAcceptedVersion: Int?
    public var changeNotes: String?
    public var isAccepted: Bool?

    public var id: String { disclaimerId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        disclaimerId = try c.decodeIfPresent(String.self, forKey: .disclaimerId) ?? ""
        versionId = try c.decodeIfPresent(String.self, forKey: .versionId) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        disclaimerType = try c.decodeIfPresent(String.self, forKey: .disclaimerType)
        versionNumber = try c.decodeIfPresent(Int.self, forKey: .versionNumber)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        contentFormat = try c.decodeIfPresent(String.self, forKey: .contentFormat)
        isRequired = try c.decodeIfPresent(Bool.self, forKey: .isRequired) ?? false
        previouslyAcceptedVersion = try c.decodeIfPresent(Int.self, forKey: .previouslyAcceptedVersion)
        changeNotes = try c.decodeIfPresent(String.self, forKey: .changeNotes)
        isAccepted = try c.decodeIfPresent(Bool.self, forKey: .isAccepted)
    }
}

public struct PasswordValidationResult: Sendable, Equatable {
    public var isValid: Bool
    public var errorMessage: String

    public init(isValid: Bool, errorMessage: String) {
        self.isValid = isValid
        self.errorMessage = errorMessage
    }
}

// MARK: - Passkey / WebAuthn credential payloads

public struct PasskeyAssertionResponse: Codable, Sendable {
    public var clientDataJSON: String
    public var authenticatorData: String
    public var signature: String
    public var userHandle: String?

    enum CodingKeys: String, CodingKey {
        case clientDataJSON = "ClientDataJSON"
        case authenticatorData = "AuthenticatorData"
        case signature = "Signature"
        case userHandle = "UserHandle"
    }

    public init(clientDataJSON: String, authenticatorData: String, signature: String, userHandle: String? = nil) {
        self.clientDataJSON = clientDataJSON
        self.authenticatorData = authenticatorData
        self.signature = signature
        self.userHandle = userHandle
    }
}

public struct PasskeyAssertionCredential: Codable, Sendable {
    public var id: String
    public var rawId: String
    public var type: String
    public var response: PasskeyAssertionResponse

    public init(id: String, rawId: String, type: String = "public-key", response: PasskeyAssertionResponse) {
        self.id = id
        self.rawId = rawId
        self.type = type
        self.response = response
    }
}

public struct PasskeyRegistrationResponse: Codable, Sendable {
    public var clientDataJSON: String
    public var attestationObject: String
    public var transports: [String]?

    enum CodingKeys: String, CodingKey {
        case clientDataJSON = "ClientDataJSON"
        case attestationObject = "AttestationObject"
        case transports = "Transports"
    }

    public init(clientDataJSON: String, attestationObject: String, transports: [String]? = nil) {
        self.clientDataJSON = clientDataJSON
        self.attestationObject = attestationObject
        self.transports = transports
    }
}

public struct PasskeyRegistrationCredential: Codable, Sendable {
    public var id: String
    public var rawId: String
    public var type: String
    public var response: PasskeyRegistrationResponse

    public init(id: String, rawId: String, type: String = "public-key", response: PasskeyRegistrationResponse) {
        self.id = id
        self.rawId = rawId
        self.type = type
        self.response = response
    }
}
