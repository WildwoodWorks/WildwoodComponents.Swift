// Environment injection for WildwoodClient — the SwiftUI equivalent of the
// React WildwoodProvider.

import SwiftUI
import os
import WildwoodCore

public extension EnvironmentValues {
    @Entry var wildwoodClient: WildwoodClient? = nil
}

public extension View {
    /// Inject a WildwoodClient into the environment and initialize it (session
    /// restore, theme load) when the view first appears.
    func wildwoodClient(_ client: WildwoodClient) -> some View {
        environment(\.wildwoodClient, client)
            .task {
                await client.initialize()
            }
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
