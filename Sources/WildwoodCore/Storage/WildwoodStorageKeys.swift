// Storage key names shared across all WildwoodComponents stacks (.NET, JS, Swift).
// These literals are parity-checked by WildwoodComponents.Sync/scripts/parity-check.mjs —
// never rename without changing every stack.

public enum WildwoodStorageKeys {
    public static let accessToken = "ww_accessToken"
    public static let refreshToken = "ww_refreshToken"
    public static let user = "ww_user"
    public static let sessionAuth = "ww_session_auth"
    public static let sessionExpiry = "ww_session_expiry"
    public static let theme = "ww_theme"

    /// First-party consent blob (the native analog of the JS Consent SDK's `ww_consent` cookie).
    /// Stored in UserDefaults via CompositeStorage. Treated as a cookie name by the Sync parity
    /// check, so it is excluded from the cross-stack localStorage-key comparison.
    public static let consent = "ww_consent"

    /// Prefix for per-thread message draft keys (`ww_draft_{threadId}` in the JS SDK).
    public static let draftPrefix = "ww_draft_"

    public static func draft(threadId: String) -> String {
        draftPrefix + threadId
    }
}
