// Which plan switches a subscriber's current tier allows. Port of `isTierChangeAllowed` in
// packages/wildwood-core/src/features/tierUtils.ts (and .NET `TierChangeRules`).

import Foundation

public enum TierChangeRules {
    /// Whether a subscriber on `current` may move to `target`, by the same rule the server applies
    /// in `ChangeTierAsync`: a move to a higher `displayOrder` is an upgrade and needs the CURRENT
    /// tier's `allowUpgrades`; any other move is a downgrade and needs its `allowDowngrades`. The
    /// server applies it to admins too, so a grid that offers a switch this refuses offers a button
    /// that can only fail.
    ///
    /// No current tier (a first subscription) is always allowed, and so is staying where you are.
    /// A payload that omits the flags decodes them as `true` (``AppTierModel``), so an older server
    /// allows every change.
    public static func isTierChangeAllowed(current: AppTierModel?, target: AppTierModel) -> Bool {
        guard let current else { return true }
        if current.id.lowercased() == target.id.lowercased() { return true }
        let isUpgrade = target.displayOrder > current.displayOrder
        return isUpgrade ? current.allowUpgrades : current.allowDowngrades
    }
}
