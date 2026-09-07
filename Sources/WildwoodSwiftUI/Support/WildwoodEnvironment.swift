// Environment injection for WildwoodClient — the SwiftUI equivalent of the
// React WildwoodProvider.

import SwiftUI
import os
import WildwoodCore

public extension EnvironmentValues {
    @Entry var wildwoodClient: WildwoodClient? = nil
}

public extension View {
    /// Inject a WildwoodClient, initialize it (session restore, theme load) on
    /// first appearance, and apply the client's current theme
    /// (`WildwoodTheme.named(client.theme.theme)`) to the subtree — live, since
    /// ThemeService is @Observable — unless the host pinned one with `.wildwoodTheme(_:)`.
    func wildwoodClient(_ client: WildwoodClient) -> some View {
        environment(\.wildwoodClient, client)
            .modifier(WildwoodServiceThemeModifier(client: client))
            .task {
                await client.initialize()
            }
    }
}

/// The SwiftUI twin of WildwoodProvider's `resolveTheme(theme ?? serviceTheme)`.
private struct WildwoodServiceThemeModifier: ViewModifier {
    let client: WildwoodClient
    @Environment(\.wildwoodTheme) private var inheritedTheme
    @Environment(\.wildwoodThemeIsExplicit) private var isExplicit

    func body(content: Content) -> some View {
        // Reading client.theme.theme registers the Observable dependency: the
        // restore in initialize() and later setTheme() calls re-run this body.
        // When the host pinned a theme, re-apply it unchanged (no branching, so
        // the subtree keeps its identity).
        content.applyWildwoodTheme(isExplicit ? inheritedTheme : WildwoodTheme.named(client.theme.theme))
    }
}

let wildwoodLogger = Logger(subsystem: "io.wildwoodworks.components", category: "WildwoodSwiftUI")

/// Resolve the environment client or stop with a clear message — mirrors the
/// React provider's "useWildwood must be used within WildwoodProvider" error.
/// Asserts in Debug; logs a fault in Release so the misconfiguration shows up
/// in Console instead of a silent forever-spinner.
@MainActor
func requireClient(_ client: WildwoodClient?, component: String) -> WildwoodClient? {
    if client == nil {
        wildwoodLogger.fault("\(component, privacy: .public) requires .wildwoodClient(_:) on an ancestor view — no client found in the environment.")
        assertionFailure("\(component) requires .wildwoodClient(_:) on an ancestor view")
    }
    return client
}
