#if os(iOS)
// Subscription administration container hosting the six panels — parity with
// SubscriptionAdminComponent (+ Status/TierPlans/Features/AddOns/UsageLimits/
// Overrides panels).

import SwiftUI
import WildwoodCore

public struct SubscriptionAdminComponent: View {
    public enum Panel: String, CaseIterable, Sendable {
        case status = "Status"
        case tierPlans = "Plans"
        case features = "Features"
        case addOns = "Add-Ons"
        case usageLimits = "Limits"
        case overrides = "Overrides"
    }

    @Environment(\.wildwoodClient) private var client

    private let appId: String?
    private let scope: SubscriptionAdminScope
    private let onPaymentRequired: ((AppTierModel, AppTierPricingModel?) async -> String?)?

    @State private var model: WildwoodSubscriptionAdminModel?
    @State private var selectedPanel: Panel = .status

    public init(
        appId: String? = nil,
        scope: SubscriptionAdminScope = .currentUser,
        onPaymentRequired: ((AppTierModel, AppTierPricingModel?) async -> String?)? = nil
    ) {
        self.appId = appId
        self.scope = scope
        self.onPaymentRequired = onPaymentRequired
    }

    public var body: some View {
        Group {
            if let model {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Panel", selection: $selectedPanel) {
                        ForEach(visiblePanels, id: \.self) { panel in
                            Text(panel.rawValue).tag(panel)
                        }
                    }
                    .pickerStyle(.segmented)

                    if !model.errorMessage.isEmpty {
                        ErrorBannerView(message: model.errorMessage) { model.errorMessage = "" }
                    }
                    if !model.successMessage.isEmpty {
                        Label(model.successMessage, systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }

                    if model.isLoading {
                        LoadingSpinnerView()
                    } else {
                        switch selectedPanel {
                        case .status: SubscriptionStatusPanel(model: model)
                        case .tierPlans: TierPlansPanel(model: model, onPaymentRequired: onPaymentRequired)
                        case .features: FeaturesPanel(model: model)
                        case .addOns: AddOnsPanel(model: model)
                        case .usageLimits: UsageLimitsPanel(model: model)
                        case .overrides: OverridesPanel(model: model)
                        }
                    }
                }
            } else {
                LoadingSpinnerView(label: "Loading subscription admin…")
            }
        }
        .task {
            guard model == nil, let client = requireClient(client, component: "SubscriptionAdminComponent") else { return }
            guard let resolvedAppId = appId ?? client.config.appId else { return }
            let created = WildwoodSubscriptionAdminModel(client: client, appId: resolvedAppId, scope: scope)
            model = created
            await created.loadAll()
        }
    }

    private var visiblePanels: [Panel] {
        scope.isAdmin ? Panel.allCases : Panel.allCases.filter { $0 != .overrides }
    }
}
#endif
