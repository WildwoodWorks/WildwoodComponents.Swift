// One test screen per component, mirroring the React suite's pages.

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

        case .pricingDisplay:
            PricingDisplayComponent { tier, pricing in
                lastEvent = "Selected \(tier.name) @ \(pricing?.price ?? 0)"
            }

        case .appTier:
            AppTierComponent { tier, pricing in
                lastEvent = "Change requested: \(tier.name) @ \(pricing?.price ?? 0)"
            }

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
