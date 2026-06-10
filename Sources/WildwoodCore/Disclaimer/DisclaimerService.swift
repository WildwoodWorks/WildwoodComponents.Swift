// Disclaimer models + service ported from @wildwood/core/src/features/disclaimerService.ts.

import Foundation

public struct PendingDisclaimersResponse: Codable, Sendable, Equatable {
    public var hasPendingDisclaimers: Bool
    public var disclaimers: [PendingDisclaimerModel]
    public var errorMessage: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasPendingDisclaimers = try c.decodeIfPresent(Bool.self, forKey: .hasPendingDisclaimers) ?? false
        disclaimers = try c.decodeIfPresent([PendingDisclaimerModel].self, forKey: .disclaimers) ?? []
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

public struct DisclaimerAcceptanceResult: Codable, Sendable, Equatable {
    public var success: Bool
    public var message: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        message = try c.decodeIfPresent(String.self, forKey: .message)
    }
}

public struct DisclaimerAcceptanceResponse: Codable, Sendable, Equatable {
    public var success: Bool
    public var errorMessage: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

public struct DisclaimerAcceptanceInput: Sendable, Equatable {
    public var disclaimerId: String
    public var versionId: String

    public init(disclaimerId: String, versionId: String) {
        self.disclaimerId = disclaimerId
        self.versionId = versionId
    }
}

public final class DisclaimerService: Sendable {
    private let http: WildwoodHttpClient
    private let defaultAppId: String

    public init(http: WildwoodHttpClient, defaultAppId: String) {
        self.http = http
        self.defaultAppId = defaultAppId
    }

    public func getPendingDisclaimers(appId: String? = nil) async throws -> PendingDisclaimersResponse {
        let targetAppId = appId ?? defaultAppId
        return try await http.get("api/disclaimeracceptance/pending/\(targetAppId)")
    }

    public func acceptDisclaimer(disclaimerId: String, versionId: String, appId: String? = nil) async throws -> DisclaimerAcceptanceResult {
        struct AcceptDto: Encodable {
            let companyDisclaimerId: String
            let companyDisclaimerVersionId: String
            let appId: String
        }
        return try await http.post(
            "api/disclaimeracceptance/accept",
            body: AcceptDto(
                companyDisclaimerId: disclaimerId,
                companyDisclaimerVersionId: versionId,
                appId: appId ?? defaultAppId
            )
        )
    }

    public func acceptAllDisclaimers(_ acceptances: [DisclaimerAcceptanceInput], appId: String? = nil) async throws -> DisclaimerAcceptanceResponse {
        struct AcceptanceDto: Encodable {
            let companyDisclaimerId: String
            let companyDisclaimerVersionId: String
        }
        struct BulkDto: Encodable {
            let appId: String
            let acceptances: [AcceptanceDto]
        }
        return try await http.post(
            "api/disclaimeracceptance/accept-bulk",
            body: BulkDto(
                appId: appId ?? defaultAppId,
                acceptances: acceptances.map {
                    AcceptanceDto(companyDisclaimerId: $0.disclaimerId, companyDisclaimerVersionId: $0.versionId)
                }
            )
        )
    }
}
