// One test screen per component, mirroring the React suite's pages.

import Foundation
import SwiftUI
import WildwoodCore
import WildwoodSwiftUI

struct TestScreenHost: View {
    let screen: TestScreen
    @Bindable var store: ClientStore
    @Environment(\.wildwoodClient) private var client

    @State private var lastEvent = ""
    @State private var aiConfigurationId = ""
    @State private var themeName = WildwoodThemeNames.woodlandWarm

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
                if !lastEvent.isEmpty {
                    GroupBox("Last event") {
                        Text(lastEvent)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(screen.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case .authentication:
            AuthenticationComponent(
                onAuthenticationSuccess: { response in lastEvent = "Authenticated: \(response.email)" },
                onAuthenticationError: { error in lastEvent = "Error: \(error)" }
            )

        case .tokenRegistration:
            TokenRegistrationComponent(
                onRegistrationSuccess: { response in lastEvent = "Registered: \(response.email)" },
                onRegistrationError: { error in lastEvent = "Error: \(error)" }
            )

        case .signupWithSubscription:
            SignupWithSubscriptionComponent(
                onSignupComplete: { auth, result in
                    lastEvent = "Signed up \(auth.email); tier: \(result?.subscription?.tierName ?? "none")"
                },
                onSignupError: { error in lastEvent = "Error: \(error)" }
            )

        case .twoFactor:
            TwoFactorSettingsComponent { status in
                lastEvent = "2FA enabled: \(status.isEnabled), methods: \(status.methodCount)"
            }

        case .aiChat:
            VStack(alignment: .leading, spacing: 8) {
                TextField("AI configuration ID", text: $aiConfigurationId)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !aiConfigurationId.isEmpty {
                    AIChatComponent(
                        configurationId: aiConfigurationId,
                        showTokenUsage: true,
                        welcomeMessage: "Ask the Wildwood assistant anything.",
                        onError: { error in lastEvent = "Error: \(error)" }
                    )
                    .frame(minHeight: 420)
                } else {
                    Text("Enter an AI configuration ID to start chatting (see wildwood_get_ai_config).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .aiFlow:
            AIFlowTestScreen { event in lastEvent = event }

        case .messaging:
            if let appId = client?.config.appId, !appId.isEmpty {
                SecureMessagingComponent(companyAppId: appId) { error in
                    lastEvent = "Error: \(error)"
                }
                .frame(minHeight: 480)
            } else {
                missingAppId
            }

        case .notification:
            VStack(spacing: 12) {
                notificationButtons
                NotificationComponent()
            }

        case .notificationToast:
            VStack(spacing: 12) {
                Text("Toasts render in the app-level overlay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                notificationButtons
            }

        case .payment:
            PaymentComponent(
                amount: 9.99,
                description: "Test payment",
                treatDevelopmentAsAppStore: false,
                onPaymentSuccess: { result in lastEvent = "Paid: \(result.transactionId ?? "?")" },
                onPaymentFailure: { error in lastEvent = "Error: \(error)" },
                onCancel: { lastEvent = "Payment cancelled" }
            )

        case .paymentForm:
            PaymentFormTestScreen { event in lastEvent = event }

        // These two cases, and `.signupWithSubscription` above, render components that are now
        // deprecated in favour of RegistrationAndSubscriptionComponent (see the
        // "Registration & Subscription" screen below). The three deprecation WARNINGS they raise
        // are expected and deliberate: the suite has to keep exercising them while they ship, and
        // Swift has no way to silence a deprecation at a call site — the only route is to
        // deprecate the enclosing declaration, which would spread up through `body`. Nothing in
        // this project or in Package.swift turns warnings into errors.
        case .pricingDisplay:
            PricingDisplayComponent { tier, pricing in
                lastEvent = "Selected \(tier.name) @ \(pricing?.price ?? 0)"
            }

        case .appTier:
            AppTierComponent { args in
                lastEvent = "Change requested: \(args.tier.name) @ \(args.price)"
            }

        case .registrationSubscription:
            RegistrationSubscriptionTestScreen()

        case .attribution:
            AttributionTestScreen()

        case .subscriptionAdmin:
            SubscriptionAdminComponent()

        case .usageDashboard:
            VStack(spacing: 16) {
                OverageSummaryComponent(onUpgradeRequested: {
                    lastEvent = "Upgrade requested from overage summary"
                })
                UsageDashboardComponent()
            }

        case .disclaimer:
            DisclaimerComponent(
                onAllAccepted: { lastEvent = "All disclaimers accepted" },
                onError: { error in lastEvent = "Error: \(error)" }
            )

        case .consent:
            ConsentComponent(
                onConsentChanged: { state in
                    let granted = ConsentCategory.nonNecessary.filter { state.categories[$0] == true }.map(\.rawValue)
                    lastEvent = "Consent updated: \(granted.isEmpty ? "necessary only" : granted.joined(separator: ", "))"
                },
                onError: { error in lastEvent = "Error: \(error)" }
            )

        case .feedback:
            FeedbackComponent(
                pageContext: "testsuite://feedback",
                onSubmitted: { feedback in lastEvent = "Submitted: \(feedback.id)" },
                onError: { error in lastEvent = "Error: \(error)" }
            )

        case .theme:
            VStack(alignment: .leading, spacing: 12) {
                Picker("Theme", selection: $themeName) {
                    Text("Woodland Warm").tag(WildwoodThemeNames.woodlandWarm)
                    Text("Cool Blue").tag(WildwoodThemeNames.coolBlue)
                    Text("Fall Colors").tag(WildwoodThemeNames.fallColors)
                }
                .pickerStyle(.segmented)
                .onChange(of: themeName) {
                    client?.theme.setTheme(themeName)
                    lastEvent = "Theme set to \(themeName) (persisted under ww_theme)"
                }

                GroupBox("Preview") {
                    VStack(spacing: 8) {
                        Button("Primary Action") {}
                            .buttonStyle(.borderedProminent)
                        Button("Secondary Action") {}
                            .buttonStyle(.bordered)
                        ProgressView(value: 0.6)
                    }
                    .padding(.vertical, 4)
                }
                .wildwoodTheme(.named(themeName))
            }
            .onAppear {
                themeName = client?.theme.theme ?? WildwoodThemeNames.woodlandWarm
            }
        }
    }

    @ViewBuilder private var notificationButtons: some View {
        HStack {
            Button("Info") { _ = client?.notifications.info("Something happened.") }
            Button("Success") { _ = client?.notifications.success("It worked!") }
            Button("Warning") { _ = client?.notifications.warning("Careful now.") }
            Button("Error") { _ = client?.notifications.error("It broke.") }
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }

    @ViewBuilder private var missingAppId: some View {
        ContentUnavailableView(
            "App ID required",
            systemImage: "exclamationmark.triangle",
            description: Text("Set the App ID in Settings to use this test.")
        )
    }
}

// Mirrors the Blazor AIFlowTest.razor page: tweakable AIFlowSettings around a
// live AIFlowComponent, with terminal results logged to the event panel.
private struct AIFlowTestScreen: View {
    let onEvent: (String) -> Void

    @State private var fixedFlowId = ""
    @State private var title = "AI Flows"
    @State private var runLabel = "Run"
    @State private var showLiveProgress = true
    @State private var showRunHistory = true
    @State private var showDebugInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Settings") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Fixed flow ID (blank = picker)", text: $fixedFlowId)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)
                    TextField("Run button label", text: $runLabel)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Show live progress", isOn: $showLiveProgress)
                    Toggle("Show run history", isOn: $showRunHistory)
                    Toggle("Show debug info", isOn: $showDebugInfo)
                }
                .font(.caption)
            }

            AIFlowComponent(
                settings: AIFlowSettings(
                    flowId: fixedFlowId.isEmpty ? nil : fixedFlowId,
                    showLiveProgress: showLiveProgress,
                    showDebugInfo: showDebugInfo,
                    showRunHistory: showRunHistory,
                    title: title,
                    runLabel: runLabel
                ),
                onRunCompleted: { result in
                    onEvent(
                        "Run completed: \(result.status) (\(result.totalTokens) tokens)"
                            + (result.errorMessage.map { " — \($0)" } ?? "")
                    )
                }
            )
            // Recreate the component (and its model) when settings change —
            // the Blazor test page re-keys the component the same way.
            .id("\(fixedFlowId)|\(title)|\(runLabel)|\(showLiveProgress)|\(showRunHistory)|\(showDebugInfo)")
        }
    }
}

private struct PaymentFormTestScreen: View {
    let onEvent: (String) -> Void
    @Environment(\.wildwoodClient) private var client

    @State private var providers: [PaymentProviderDto] = []
    @State private var selectedProviderId = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !loaded {
                LoadingSpinnerView(label: "Loading providers…")
            } else if providers.isEmpty {
                ContentUnavailableView("No providers configured", systemImage: "creditcard.trianglebadge.exclamationmark")
            } else {
                Picker("Provider", selection: $selectedProviderId) {
                    ForEach(providers) { provider in
                        Text(provider.displayName ?? provider.name).tag(provider.id)
                    }
                }
                .pickerStyle(.menu)

                if !selectedProviderId.isEmpty {
                    PaymentFormComponent(
                        providerId: selectedProviderId,
                        amount: 4.99,
                        description: "Test form payment",
                        onPaymentSuccess: { response in onEvent("Initiated: \(response.paymentIntentId ?? "?")") },
                        onPaymentError: { error in onEvent("Error: \(error)") }
                    )
                }
            }
        }
        .task {
            guard let client, let appId = client.config.appId else {
                loaded = true
                return
            }
            let info = try? await client.payment.getAvailableProviders(appId: appId)
            providers = info?.availableProviders ?? []
            selectedProviderId = info?.defaultProvider?.id ?? providers.first?.id ?? ""
            loaded = true
        }
    }
}

// MARK: - Event log

/// One line of a screen's event log.
struct TestEventLogEntry: Identifiable, Sendable {
    let id = UUID()
    let message: String
}

/// A newest-first event log, shared by the two screens below.
///
/// A main-actor class rather than a `@State` array because the fake payment-action handler is
/// `Sendable` and appends from a `@Sendable` closure: a main-actor-isolated object can be
/// captured there and written to after one hop, which a view struct's `@State` cannot.
@MainActor
@Observable
final class TestEventLog {
    private(set) var entries: [TestEventLogEntry] = []

    func append(_ message: String) {
        entries.insert(TestEventLogEntry(message: message), at: 0)
        if entries.count > 50 {
            entries.removeLast(entries.count - 50)
        }
    }

    func clear() {
        entries.removeAll()
    }
}

private struct EventLogCard: View {
    let log: TestEventLog
    let placeholder: String

    var body: some View {
        GroupBox("Event log") {
            VStack(alignment: .leading, spacing: 4) {
                if log.entries.isEmpty {
                    Text(placeholder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(log.entries) { entry in
                        Text(entry.message)
                            .font(.caption2.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button("Clear log") { log.clear() }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Registration & Subscription

/// A FAKE payment-action handler. IT CONFIRMS NOTHING, AND IT TAKES NO MONEY.
///
/// The SDK deliberately ships no Stripe dependency: a host that needs 3-D Secure or a saved card
/// implements ``WildwoodPaymentActionHandler`` over its own payment SDK (see the README). This
/// double exists so the HANDLER BRANCHES — a parked plan change, an in-app pack card — can be
/// walked in the simulator with no merchant account and no native module. It answers whatever the
/// screen's picker is set to, and every answer is a lie: `succeeded` here means "the test app said
/// so", never "the bank approved it". Never copy it into an app.
private struct FakePaymentActionHandler: WildwoodPaymentActionHandler {
    enum Outcome: String, CaseIterable, Identifiable {
        case succeeded
        case failed
        case cancelled

        var id: String { rawValue }
    }

    let outcome: Outcome
    let onCall: @Sendable (String) -> Void

    func confirmPayment(clientSecret: String, publishableKey: String?) async -> PaymentActionOutcome {
        onCall("FAKE confirmPayment -> \(outcome.rawValue) (nothing was confirmed)")
        return answer
    }

    func confirmCardSetup(clientSecret: String, publishableKey: String?) async -> PaymentActionOutcome {
        onCall("FAKE confirmCardSetup -> \(outcome.rawValue) (no card was saved)")
        return answer
    }

    private var answer: PaymentActionOutcome {
        switch outcome {
        case .succeeded: return PaymentActionOutcome.succeeded
        case .failed: return PaymentActionOutcome.failed(message: "Fake handler: pretend the bank refused the challenge.")
        case .cancelled: return PaymentActionOutcome.cancelled
        }
    }
}

/// Mirrors the React suite's `RegistrationAndSubscriptionTest` page: the component's four surfaces
/// (its three views plus the invite preset), the same settings controls, and an event log.
private struct RegistrationSubscriptionTestScreen: View {
    private enum Surface: String, CaseIterable, Identifiable {
        case pricing
        case signup
        case manage
        case invite

        var id: String { rawValue }

        var label: String {
            switch self {
            case .pricing: return "Pricing"
            case .signup: return "Signup"
            case .manage: return "Manage"
            case .invite: return "Invite"
            }
        }
    }

    /// One control for both pack enums: the pricing view and the signup view spell "offer packs"
    /// differently (`PricingPackSelection.multi` against `SignupPackSelection.choose`).
    private enum PackSetting: String, CaseIterable, Identifiable {
        case offered
        case hidden

        var id: String { rawValue }

        var label: String {
            switch self {
            case .offered: return "Offered"
            case .hidden: return "Hidden"
            }
        }

        var pricing: PricingPackSelection {
            switch self {
            case .offered: return PricingPackSelection.multi
            case .hidden: return PricingPackSelection.none
            }
        }

        var signup: SignupPackSelection {
            switch self {
            case .offered: return SignupPackSelection.choose
            case .hidden: return SignupPackSelection.none
            }
        }
    }

    private static let demoAddOnGroups: [WildwoodAddOnGroup] = [
        WildwoodAddOnGroup(id: "content", title: "Content", categories: ["Content", "Documents"]),
        WildwoodAddOnGroup(id: "analytics", title: "Analytics", categories: ["Analytics", "Insights"]),
    ]

    @State private var log = TestEventLog()
    @State private var surface: Surface = .pricing
    @State private var appId = TestSuiteConfig.appId
    @State private var registrationToken = ""
    @State private var prefillEmail = ""
    @State private var planSelection: SignupPlanSelection = .choose
    @State private var packSetting: PackSetting = .offered
    @State private var tokenMode: SignupTokenMode = .auto
    @State private var paymentOrder: SignupPaymentOrder = .afterAccount
    @State private var layout: ManageLayout = .tabs
    @State private var showAddOns = true
    @State private var allowPackSelfService = true
    @State private var packPurchaseAvailable = true
    @State private var useFakeHandler = false
    @State private var fakeOutcome: FakePaymentActionHandler.Outcome = .succeeded
    /// What the last opened signup link asked for, fed back in as the pre-selection.
    @State private var deepLink: SignupParams?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Surface", selection: $surface) {
                ForEach(Surface.allCases) { value in
                    Text(value.label).tag(value)
                }
            }
            .pickerStyle(.segmented)

            settingsBox
            togglesBox
            fakeHandlerBox

            surfaceView
                // Re-key on every setting, the way the AI Flow screen does: the views own their
                // drivers, so a changed option has to rebuild them.
                .id(configurationKey)
                // The signup and manage views scroll themselves, and this screen is already
                // inside the host's ScrollView.
                .frame(minHeight: 520)

            EventLogCard(
                log: log,
                placeholder: "onSelect, onSignupComplete, onEntitlementsChanged, onSubscriptionChanged and onError payloads appear here."
            )
        }
        // A signup link that lands while this screen is open: its plan, packs, token and email are
        // folded into the settings and the signup surface is shown. The signup view carries its
        // own `.onOpenURL` for the same URL (DD-5), and `.wildwoodClient(_:)` hands it to Campaign
        // Attribution — three readers of one link, each doing its own job.
        .onOpenURL { url in applyDeepLink(url) }
    }

    // MARK: - Settings

    @ViewBuilder private var settingsBox: some View {
        GroupBox("Settings") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("App ID (blank = Settings screen value)", text: $appId)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Registration token", text: $registrationToken)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Prefill email (invite)", text: $prefillEmail)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Plan step", selection: $planSelection) {
                    ForEach(SignupPlanSelection.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                Picker("Packs", selection: $packSetting) {
                    ForEach(PackSetting.allCases) { value in
                        Text(value.label).tag(value)
                    }
                }
                Picker("Token mode", selection: $tokenMode) {
                    ForEach(SignupTokenMode.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                Picker("Payment order", selection: $paymentOrder) {
                    ForEach(SignupPaymentOrder.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                Picker("Manage layout", selection: $layout) {
                    ForEach(ManageLayout.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
            }
            .font(.caption)
        }
    }

    @ViewBuilder private var togglesBox: some View {
        GroupBox("Options") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show add-ons", isOn: $showAddOns)
                Toggle("Allow pack self-service (manage)", isOn: $allowPackSelfService)
                Toggle("Pack purchase available", isOn: $packPurchaseAvailable)
            }
            .font(.caption)
        }
    }

    @ViewBuilder private var fakeHandlerBox: some View {
        GroupBox("FAKE payment-action handler") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use the fake handler", isOn: $useFakeHandler)
                Picker("It answers", selection: $fakeOutcome) {
                    ForEach(FakePaymentActionHandler.Outcome.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .disabled(!useFakeHandler)
                Text("""
                A TEST DOUBLE. It confirms nothing and takes no money: it answers whatever is \
                picked above so the handler branches (a parked 3-D Secure change, an in-app pack \
                card) can be walked in the simulator. Off is the real no-handler behaviour: no \
                SetupIntent is requested, SupportsPaymentAction is never sent, and a purchase \
                that needs a challenge is reported as one to finish on the web.
                """)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    // MARK: - Surfaces

    @ViewBuilder private var surfaceView: some View {
        switch surface {
        case .pricing:
            RegistrationAndSubscriptionComponent(.pricing(pricingConfiguration))
        case .signup:
            RegistrationAndSubscriptionComponent(.signup(signupConfiguration))
        case .manage:
            RegistrationAndSubscriptionComponent(.manage(manageConfiguration))
        case .invite:
            RegistrationAndSubscriptionComponent(.signup(inviteConfiguration))
        }
    }

    private var pricingConfiguration: RegistrationSubscriptionPricingConfiguration {
        RegistrationSubscriptionPricingConfiguration(
            appId: trimmedAppId,
            contactUrl: "https://www.wildwoodworks.io/contact",
            showAddOns: showAddOns,
            packSelection: packSetting.pricing,
            packPurchaseAvailable: packPurchaseAvailable,
            addOnGroups: showAddOns ? Self.demoAddOnGroups : nil,
            onError: { error in log.append("onError \(error.code): \(error.message)") },
            onSelect: { selection in
                let tier: String = selection.tierId ?? "-"
                let pricing: String = selection.pricingId ?? "-"
                let packs: String = selection.addOnIds.joined(separator: ",")
                log.append("onSelect tier=\(tier) pricing=\(pricing) billing=\(selection.billing.rawValue) packs=[\(packs)]")
            }
        )
    }

    private var signupConfiguration: RegistrationSubscriptionSignupConfiguration {
        RegistrationSubscriptionSignupConfiguration(
            appId: trimmedAppId,
            preSelectedTierId: deepLink?.tierId,
            preSelectedPricingId: deepLink?.pricingId,
            preSelectedAddOnIds: deepLink?.addOnIds ?? [],
            registrationToken: trimmed(registrationToken),
            prefillEmail: trimmed(prefillEmail),
            planSelection: planSelection,
            packSelection: packSetting.signup,
            tokenMode: tokenMode,
            paymentOrder: paymentOrder,
            packPurchaseAvailable: packPurchaseAvailable,
            paymentActionHandler: paymentActionHandler,
            contactUrl: "https://www.wildwoodworks.io/contact",
            onAlreadySignedIn: { log.append("onAlreadySignedIn") },
            onSignupComplete: { outcome in log.append(Self.describe(outcome)) },
            onCancel: { log.append("onCancel") },
            onEntitlementsChanged: { reason in log.append("onEntitlementsChanged \(reason.rawValue)") },
            onError: { error in log.append("onError \(error.code): \(error.message)") }
        )
    }

    /// Invite redemption: the token step is the only way in, the plan comes from the token and
    /// packs are out of scope.
    private var inviteConfiguration: RegistrationSubscriptionSignupConfiguration {
        RegistrationSubscriptionSignupConfiguration(
            appId: trimmedAppId,
            registrationToken: trimmed(registrationToken),
            prefillEmail: trimmed(prefillEmail),
            planSelection: SignupPlanSelection.skip,
            packSelection: SignupPackSelection.none,
            tokenMode: SignupTokenMode.required,
            paymentOrder: paymentOrder,
            packPurchaseAvailable: packPurchaseAvailable,
            paymentActionHandler: paymentActionHandler,
            contactUrl: "https://www.wildwoodworks.io/contact",
            onAlreadySignedIn: { log.append("onAlreadySignedIn") },
            onSignupComplete: { outcome in log.append(Self.describe(outcome)) },
            onCancel: { log.append("onCancel") },
            onEntitlementsChanged: { reason in log.append("onEntitlementsChanged \(reason.rawValue)") },
            onError: { error in log.append("onError \(error.code): \(error.message)") }
        )
    }

    private var manageConfiguration: RegistrationSubscriptionManageConfiguration {
        RegistrationSubscriptionManageConfiguration(
            appId: trimmedAppId,
            layout: layout,
            showStatusAboveTabs: true,
            allowPackSelfService: allowPackSelfService,
            showAddOns: showAddOns,
            paymentActionHandler: paymentActionHandler,
            contactUrl: "https://www.wildwoodworks.io/contact",
            onSubscriptionChanged: { log.append("onSubscriptionChanged") },
            onEntitlementsChanged: { reason in log.append("onEntitlementsChanged \(reason.rawValue)") },
            onError: { error in log.append("onError \(error.code): \(error.message)") }
        )
    }

    // MARK: - Helpers

    private var paymentActionHandler: (any WildwoodPaymentActionHandler)? {
        guard useFakeHandler else { return nil }
        // Capture the log OBJECT, not this view: the callback is @Sendable, and a main-actor
        // @Observable class is Sendable while a View struct is not.
        let eventLog = log
        return FakePaymentActionHandler(outcome: fakeOutcome) { message in
            Task { @MainActor in eventLog.append(message) }
        }
    }

    private var trimmedAppId: String? {
        trimmed(appId)
    }

    private func trimmed(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private var configurationKey: String {
        let parts: [String] = [
            surface.rawValue,
            trimmedAppId ?? "-",
            registrationToken,
            prefillEmail,
            planSelection.rawValue,
            packSetting.rawValue,
            tokenMode.rawValue,
            paymentOrder.rawValue,
            layout.rawValue,
            "\(showAddOns)",
            "\(allowPackSelfService)",
            "\(packPurchaseAvailable)",
            "\(useFakeHandler)",
            fakeOutcome.rawValue,
            deepLink?.tierId ?? "-",
        ]
        return parts.joined(separator: "|")
    }

    private func applyDeepLink(_ url: URL) {
        let params = SignupParams.parse(url: url)
        deepLink = params
        if let token = params.token ?? params.invite {
            registrationToken = token
        }
        if let email = params.email {
            prefillEmail = email
        }
        let invited: String? = params.token ?? params.invite
        surface = invited == nil ? Surface.signup : Surface.invite

        let tier: String = params.tierId ?? "-"
        let pricing: String = params.pricingId ?? "-"
        let packs: String = params.addOnIds.joined(separator: ",")
        let email: String = params.email ?? "-"
        log.append("onOpenURL \(url.absoluteString) -> tier=\(tier) pricing=\(pricing) packs=[\(packs)] token=\(invited ?? "-") email=\(email)")
    }

    private static func describe(_ outcome: SignupOutcome) -> String {
        let tier: String = outcome.tier?.name ?? "-"
        let pending: Bool = outcome.planActivationPending == true
        return "onSignupComplete user=\(outcome.userId) tier=\(tier) packs=\(outcome.packs.count) pending=\(pending)"
    }
}

// MARK: - Campaign Attribution

/// Mirrors the React suite's `AttributionTest` page: the current touches and state, a capture-URL
/// form and a clear.
private struct AttributionTestScreen: View {
    @Environment(\.wildwoodClient) private var client

    @State private var log = TestEventLog()
    @State private var urlText =
        "https://example.com/?utm_source=reddit&utm_medium=paid&utm_campaign=govcon-test-sep26&utm_content=ad1"
    @State private var referrerText = ""
    @State private var showPayload = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            howToTest
            captureControls
            stateCard
            EventLogCard(log: log, placeholder: "Captures and clears appear here.")
        }
    }

    @ViewBuilder private var howToTest: some View {
        GroupBox("How to test") {
            Text("""
            Open a tagged link while the app runs \u{2014} in the simulator, \
            xcrun simctl openurl booted "wildwoodtest://signup?utm_source=reddit&utm_medium=paid\
            &utm_campaign=sept26&tier=pro" \u{2014} or capture one below. Touches stay in memory \
            until the app's consent category (Analytics by default) is granted; then they are \
            written to storage under ww_attribution. The app must have Campaign Attribution \
            enabled in WildwoodAdmin for the config to load.
            """)
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var captureControls: some View {
        GroupBox("Capture a URL") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Referrer (optional)", text: $referrerText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("Show the registration payload", isOn: $showPayload)
                HStack {
                    Button("Capture URL") { captureTypedUrl() }
                        .buttonStyle(.borderedProminent)
                    Button("Clear touches") { clearTouches() }
                        .buttonStyle(.bordered)
                }
            }
            .font(.caption)
        }
    }

    @ViewBuilder private var stateCard: some View {
        if let attribution = client?.attribution {
            GroupBox("State") {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Visitor key", value: attribution.visitorKey)
                    LabeledContent("App config", value: Self.describeConfig(attribution.config))
                    LabeledContent(
                        "Persisted",
                        value: attribution.persisted ? "yes" : "no (memory only until consent allows it)"
                    )
                    LabeledContent("First touch", value: Self.describe(attribution.first))
                    LabeledContent("Last touch", value: Self.describe(attribution.last))
                    if showPayload {
                        Text(Self.describePayload(attribution.getForRegistration()))
                            .font(.caption2.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "No client",
                systemImage: "exclamationmark.triangle",
                description: Text("Inject a WildwoodClient to use this screen.")
            )
        }
    }

    private func captureTypedUrl() {
        guard let client else {
            log.append("No client: nothing captured.")
            return
        }
        let trimmedUrl = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedUrl) else {
            log.append("Not a URL: \(trimmedUrl)")
            return
        }
        let referrer = URL(string: referrerText.trimmingCharacters(in: .whitespacesAndNewlines))
        if let touch = client.attribution.capture(url: url, referrer: referrer) {
            log.append("capture -> \(Self.describe(touch))")
        } else {
            log.append("capture -> no touch (a direct visit, or attribution is off for this app)")
        }
    }

    private func clearTouches() {
        client?.attribution.clear()
        log.append("clear() -> touches dropped from memory and storage")
    }

    private static func describe(_ touch: AttributionTouch?) -> String {
        guard let touch else { return "none" }
        return "\(touch.source ?? "(none)") / \(touch.medium ?? "(none)") / \(touch.campaign ?? "(none)")"
    }

    private static func describeConfig(_ config: PublicAttributionConfig?) -> String {
        guard let config else { return "not loaded" }
        return config.isEnabled ? "attribution enabled" : "attribution disabled for this app"
    }

    private static func describePayload(_ payload: AttributionPayload?) -> String {
        guard let payload else { return "getForRegistration(): nil (nothing captured yet)" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload), let json = String(data: data, encoding: .utf8) else {
            return "getForRegistration(): visitorKey \(payload.visitorKey)"
        }
        return json
    }
}
