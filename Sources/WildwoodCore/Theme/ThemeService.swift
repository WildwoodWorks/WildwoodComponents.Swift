// Theme service ported from @wildwood/core/src/theme. Persists the selected
// theme name under the shared ww_theme storage key and emits themeChanged.

import Foundation
import Observation

public typealias ThemeName = String

public enum WildwoodThemeNames {
    public static let woodlandWarm: ThemeName = "woodland-warm"
    public static let coolBlue: ThemeName = "cool-blue"
    public static let fallColors: ThemeName = "fall-colors"
}

@MainActor
@Observable
public final class ThemeService {
    public private(set) var theme: ThemeName = WildwoodThemeNames.woodlandWarm

    @ObservationIgnored private let storage: any WildwoodStorageAdapter
    @ObservationIgnored private let events: WildwoodEventEmitter

    public init(storage: any WildwoodStorageAdapter, events: WildwoodEventEmitter) {
        self.storage = storage
        self.events = events
    }

    /// Restores `ww_theme`. Does not emit `themeChanged` (JS parity:
    /// `@wildwood/core` initialize() is silent too); observers of `theme` see the
    /// restore through Observation.
    public func initialize() {
        if let stored = storage.getItem(WildwoodStorageKeys.theme), !stored.isEmpty {
            theme = stored
        }
    }

    /// Persists the new theme under `ww_theme` and emits `themeChanged` —
    /// the only place that event is raised, matching the JS core service.
    public func setTheme(_ newTheme: ThemeName) {
        theme = newTheme
        storage.setItem(WildwoodStorageKeys.theme, newTheme)
        events.emit(.themeChanged(newTheme))
    }
}
