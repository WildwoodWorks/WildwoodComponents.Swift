// Environment injection for WildwoodClient — the SwiftUI equivalent of the
// React WildwoodProvider.

import SwiftUI
import os
import WildwoodCore

public extension EnvironmentValues {
    @Entry var wildwoodClient: WildwoodClient? = nil

    /// The payment-action handler in force for this subtree, seeded by
    /// `.wildwoodPaymentActionHandler(_:)`. Nil — no handler — is the default and a supported
    /// state; see ``WildwoodPaymentActionHandler``.
    @Entry var wildwoodPaymentActionHandler: (any WildwoodPaymentActionHandler)? = nil
}

public extension View {
    /// Inject a WildwoodClient, initialize it (session restore, theme load, Campaign Attribution
    /// start) on first appearance, capture campaign touches from every opened URL, and apply the
    /// client's current theme (`WildwoodTheme.named(client.theme.theme)`) to the subtree — live,
    /// since ThemeService is @Observable — unless the host pinned one with `.wildwoodTheme(_:)`.
    func wildwoodClient(_ client: WildwoodClient) -> some View {
        environment(\.wildwoodClient, client)
            .modifier(WildwoodServiceThemeModifier(client: client))
            .wildwoodAttributionCapture(client)
            .task {
                await client.initialize()
            }
    }

    /// Supply the payment-action handler every Wildwood surface in this subtree uses — the
    /// SwiftUI analog of React Native's `WildwoodProvider paymentActionHandler` prop.
    ///
    /// Precedence, nearest first: a component's own parameter, then this modifier, then
    /// ``WildwoodClient/paymentActionHandler``. Resolved in one place by
    /// ``WildwoodPaymentAction/resolve(parameter:environment:client:)`` so no component
    /// re-derives it.
    func wildwoodPaymentActionHandler(_ handler: (any WildwoodPaymentActionHandler)?) -> some View {
        environment(\.wildwoodPaymentActionHandler, handler)
    }

    /// Feed deep links and universal links to Campaign Attribution — the native stand-in for the
    /// web SDK's landing-URL read, and the same wiring the React Native provider does with
    /// `Linking`. `.wildwoodClient(_:)` applies this for you; apply it yourself only when the
    /// client is injected some other way, and apply it once (a second copy would re-capture the
    /// same URL). Attribution off (`WildwoodConfig.attributionEnabled == false`) makes it a no-op.
    func wildwoodAttributionCapture(_ client: WildwoodClient) -> some View {
        onOpenURL { url in
            // Hop explicitly: AttributionService is main-actor isolated, and the delivery
            // closure's isolation is SwiftUI's business, not ours.
            Task { @MainActor in
                _ = client.attribution.capture(url: url)
            }
        }
    }

    /// Record a Campaign Attribution funnel `page_view` for this screen, as `/<name>`, each time it
    /// appears. A native app has no URL for the funnel to read, so screens say where the visitor is.
    /// The same screen twice in a row counts once, and nothing is sent while the app has funnel
    /// tracking off. Apply it inside the `.wildwoodClient(_:)` subtree (it reads the client from the
    /// environment); outside one it does nothing.
    func wildwoodTrackScreen(_ name: String) -> some View {
        modifier(WildwoodTrackScreenModifier(name: name))
    }
}

/// `.wildwoodTrackScreen(_:)`: a `page_view` on every appearance (a tab or a stack pop coming back
/// to the screen counts again, unless it was already the current screen).
private struct WildwoodTrackScreenModifier: ViewModifier {
    let name: String
    @Environment(\.wildwoodClient) private var client

    func body(content: Content) -> some View {
        content.onAppear {
            client?.attribution.trackScreen(name)
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
