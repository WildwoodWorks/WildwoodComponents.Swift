// Per-app notification delivery preferences (email / SMS / push opt-outs) for the
// authenticated user — the SwiftUI analog of react-shared's
// useNotificationPreferences hook.
//
// Retain-on-nil on load: getPreferences returns nil only on a transient failure
// (it returns safe defaults for a legitimate 401/403 deny), so we keep the
// previously-loaded preferences rather than dropping the user's settings. save()
// is optimistic (reflects the draft immediately); a nil result from
// updatePreferences is a genuine failure and surfaces via errorMessage.

import Foundation
import Observation
import WildwoodCore

@MainActor
@Observable
public final class WildwoodNotificationPreferencesModel {
    @ObservationIgnored private let client: WildwoodClient

    public private(set) var preferences: UserNotificationPreference?
    public private(set) var isLoading = true
    public private(set) var isSaving = false
    public var errorMessage: String?

    public init(client: WildwoodClient) {
        self.client = client
    }

    public func load(appId: String? = nil) async {
        isLoading = true
        defer { isLoading = false }
        // nil = transient failure: retain the previously-loaded preferences.
        if let pref = await client.notificationInbox.getPreferences(appId: appId) {
            preferences = pref
        }
    }

    /// Persist preferences. Optimistic: the passed draft is reflected immediately.
    /// Returns the saved record, or nil on failure (errorMessage is set).
    @discardableResult
    public func save(_ pref: UserNotificationPreference) async -> UserNotificationPreference? {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        preferences = pref
        guard let saved = await client.notificationInbox.updatePreferences(pref) else {
            errorMessage = "Failed to save notification preferences."
            return nil
        }
        preferences = saved
        return saved
    }
}
