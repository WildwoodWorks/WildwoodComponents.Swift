// The pure part of the tier/pack action surface: turning a failed request into the structured
// refusal those actions report instead of throwing, and reading a refusal body back as the
// result DTO the server answered with.
//
// Port of `toAppTierActionError` / `failedResult` in
// packages/wildwood-core/src/features/appTierService.ts, and the twin of
// WildwoodComponents.Shared/Utilities/AppTierActionMapper.cs — the three stacks must word a
// refusal identically and name the same codes, so this rule lives in one place per stack.
//
// Nothing here performs a request: callers hand it the error a verb call threw. The body it
// reads is ``WildwoodError/details`` (the raw response bytes), because ``WildwoodError/Code`` is
// a closed enum that drops a server code it does not know.

import Foundation

extension AppTierActionError {
    /// The refusal a tier/pack action reports for a failed attempt.
    ///
    /// The server's own error code wins whenever it sent one. A 404 that carries NO code is the
    /// one case worth naming: the route itself is absent, i.e. the server predates this SDK, so
    /// it becomes ``AppTierActionErrorCodes/notSupported`` rather than being reported as a
    /// missing subscription. Anything else without a code — a network failure, a 500, a bare
    /// 400 — is ``AppTierActionErrorCodes/requestFailed``. The message is never empty.
    public static func from(_ error: any Error, fallbackMessage: String) -> AppTierActionError {
        let body = AppTierActionMapping.body(of: error)
        let code = AppTierActionMapping.string(in: body, keys: ["errorCode", "code"])
        let message = AppTierActionMapping.string(in: body, keys: ["errorMessage", "message", "error", "title"])
            ?? AppTierActionMapping.nonBlank((error as? WildwoodError)?.message)
            ?? AppTierActionMapping.nonBlank((error as? any LocalizedError)?.errorDescription)
            ?? fallbackMessage

        // A request that never reached the server has no status to reason about — it is simply a
        // failed request. (WildwoodError is checked first because it also conforms to
        // LocalizedError, and its `message` is the field the other two stacks read.)
        guard let wildwoodError = error as? WildwoodError else {
            return AppTierActionError(code: code ?? AppTierActionErrorCodes.requestFailed, message: message)
        }

        let fallbackCode = wildwoodError.status == 404
            ? AppTierActionErrorCodes.notSupported
            : AppTierActionErrorCodes.requestFailed
        return AppTierActionError(
            code: code ?? fallbackCode,
            message: message,
            status: wildwoodError.status
        )
    }
}

/// The result DTOs that carry a refusal in the same three fields, so one builder can fill them.
///
/// Deliberately internal: it exists to share the refusal rule inside the SDK, not to invite a
/// host to switch on it. ``AppTierChangeResultModel`` is not a member — its `errorMessage` is a
/// non-optional `String`, and the tier-change completion builds its own refusal anyway.
protocol AppTierRefusableResult {
    var success: Bool { get set }
    var errorCode: String? { get set }
    var errorMessage: String? { get set }
}

extension AddOnCheckoutQuoteModel: AppTierRefusableResult {}
extension AddOnCheckoutPaymentMethodModel: AppTierRefusableResult {}
extension AddOnCheckoutResultModel: AppTierRefusableResult {}
extension AddOnSubscriptionCancelResultModel: AppTierRefusableResult {}
extension AddOnSubscriptionReactivateResultModel: AppTierRefusableResult {}

/// Body reading and refusal building for the structured tier/pack actions.
enum AppTierActionMapping {
    /// Probe for "the server answered with the result DTO itself", the way JS checks
    /// `typeof body.success === 'boolean'`. A numeric `success`, an array body or a non-object
    /// body all fail to decode, which is the answer we want: this is not that DTO.
    private struct SuccessProbe: Decodable {
        var success: Bool?
    }

    /// The same probe for the per-item checkout result, whose marker is a STRING `status`
    /// (JS: `typeof body.status === 'string'`).
    private struct StatusProbe: Decodable {
        var status: String?
    }

    /// The failed request's body as a JSON object, or nil when it carried none / carried
    /// something that is not an object.
    static func body(of error: any Error) -> [String: Any]? {
        guard let wildwoodError = error as? WildwoodError,
              let details = wildwoodError.details,
              let object = try? JSONSerialization.jsonObject(with: details) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    /// The first non-blank string among `keys`.
    static func string(in body: [String: Any]?, keys: [String]) -> String? {
        guard let body else { return nil }
        for key in keys {
            if let value = body[key] as? String, let text = nonBlank(value) {
                return text
            }
        }
        return nil
    }

    /// The value when it has any non-whitespace content, else nil.
    static func nonBlank(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    /// The refusal body read back as the result DTO, but only when the server really sent that
    /// DTO — recognised by a Bool `success` property. The checkout endpoints answer a refusal
    /// with the SAME DTO they answer a success with, so this is what keeps the server's fields
    /// (the checkout id, the quote's own currency) instead of discarding them.
    static func refusalBody<T: Decodable>(_ error: any Error, as type: T.Type) -> T? {
        guard let details = (error as? WildwoodError)?.details,
              let probe = try? WildwoodJSON.decoder().decode(SuccessProbe.self, from: details),
              probe.success != nil
        else {
            return nil
        }
        return try? WildwoodJSON.decoder().decode(T.self, from: details)
    }

    /// The same, for the per-item checkout result: a refusal there IS the item DTO (the
    /// controller returns it with the 400/404), recognised by a String `status`.
    static func refusalItemBody<T: Decodable>(_ error: any Error, as type: T.Type) -> T? {
        guard let details = (error as? WildwoodError)?.details,
              let probe = try? WildwoodJSON.decoder().decode(StatusProbe.self, from: details),
              probe.status != nil
        else {
            return nil
        }
        return try? WildwoodJSON.decoder().decode(T.self, from: details)
    }

    /// Build the refusal an action reports instead of throwing: whatever the server sent, with
    /// only the fields it left out filled in from `empty`, and always `success == false`.
    static func refusal<T: Decodable & AppTierRefusableResult>(
        _ error: any Error,
        fallbackMessage: String,
        empty: T
    ) -> T {
        let actionError = AppTierActionError.from(error, fallbackMessage: fallbackMessage)
        var result = refusalBody(error, as: T.self) ?? empty
        result.success = false
        result.errorCode = actionError.code
        result.errorMessage = actionError.message
        return result
    }
}
