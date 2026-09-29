import Foundation

/// Known error codes returned by WildwoodAPI auth endpoints (the body's `error` / `errorCode`).
/// Mirrors `@wildwood/core`'s `AuthErrorCodes` and .NET `WildwoodComponents.Shared/Models/AuthErrorCodes.cs`.
///
/// The server's own `message` is what a login screen shows (``WildwoodError/fromResponse(status:body:fallbackMessage:)``
/// already surfaces it); these exist for a host that wants to branch on the reason — for example to
/// send a user whose temporary password expired to their administrator.
public enum AuthErrorCodes {
    public static let invalidApplication = "InvalidApplication"
    public static let invalidCredentials = "InvalidCredentials"
    public static let notAuthorizedForApplication = "NotAuthorizedForApplication"
    public static let accountDeactivated = "AccountDeactivated"
    public static let temporaryPasswordExpired = "TemporaryPasswordExpired"
    public static let userExists = "USER_EXISTS"
}
