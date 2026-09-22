#if os(iOS)
// Subscription administration container hosting the six panels — parity with
// SubscriptionAdminComponent (+ Status/TierPlans/Features/AddOns/UsageLimits/
// Overrides panels).
//
// The plan change runs through ``WildwoodPlanChangeModel``, the same driver and the same two
// sheets the manage view uses (``View/wildwoodPlanChangeSheets(flow:client:appId:labels:paymentActionHandler:hasHostPaymentHandler:onError:)``).
// Two things about a change therefore behave differently from before, and both are the documented
// behaviour change the other stacks made in this sync:
//
//  · A change the server PARKS on a 3-D Secure challenge is now finished rather than abandoned:
//    with a ``WildwoodPaymentActionHandler`` wired the challenge is put to the customer and the
//    parked change completed, and `SupportsPaymentAction` goes up only then — without a handler
//    the plain change is posted and the server refuses instead of parking one nobody can answer.
//  · A change needing a card now opens the component's own ``PaymentSheetView`` when the host
//    supplied no ``onPaymentRequired``. The host callback still WINS wherever it exists: it
//    predates the sheet, and a host that wired one means it. Its answer is final — nothing
//    abandons the change — while closing the built-in sheet returns to the confirmation with the
//    priced change intact.

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
    @Environment(\.wildwoodPaymentActionHandler) private var environmentPaymentActionHandler

    private let appId: String?
    private let scope: SubscriptionAdminScope
    /// Collect payment for a plan change. The args carry the pricing MODEL id, the plan's own
    /// price and its trial days (JS 05dd7cb) — a host that forwards them into `PaymentComponent`
    /// gets a recurring subscription instead of a one-off prorated charge.
    ///
    /// Supplied, it is used INSTEAD of the built-in card sheet and its answer is final.
    private let onPaymentRequired: ((WildwoodPaymentRequiredArgs) async -> String?)?
    private let labels: RegistrationSubscriptionLabels
    /// This screen's own payment-action handler, which beats the subtree's
    /// (`.wildwoodPaymentActionHandler(_:)`) and the client's. No handler anywhere is supported
    /// and is the default.
    private let paymentActionHandler: (any WildwoodPaymentActionHandler)?
    /// Told about every plan-change failure, with a stable code.
    private let onError: ((RegistrationSubscriptionError) -> Void)?

    @State private var model: WildwoodSubscriptionAdminModel?
    @State private var flow: WildwoodPlanChangeModel?
    @State private var resolvedClient: WildwoodClient?
    @State private var selectedPanel: Panel = .status

    public init(
        appId: String? = nil,
        scope: SubscriptionAdminScope = .currentUser,
        onPaymentRequired: ((WildwoodPaymentRequiredArgs) async -> String?)? = nil,
        labels: RegistrationSubscriptionLabels = .defaults,
        paymentActionHandler: (any WildwoodPaymentActionHandler)? = nil,
        onError: ((RegistrationSubscriptionError) -> Void)? = nil
    ) {
        self.appId = appId
        self.scope = scope
        self.onPaymentRequired = onPaymentRequired
        self.labels = labels
        self.paymentActionHandler = paymentActionHandler
        self.onError = onError
    }

    public var body: some View {
        Group {
            if let model, let flow, let resolvedClient {
                loaded(model, flow: flow, client: resolvedClient)
            } else {
                LoadingSpinnerView(label: "Loading subscription admin\u{2026}")
            }
        }
        .task { await start() }
        // Never cancels money already in flight: `detach()` lets an authenticated change drain
        // through its completion and only silences the callbacks.
        .onDisappear { flow?.detach() }
    }

    private func loaded(
        _ model: WildwoodSubscriptionAdminModel,
        flow: WildwoodPlanChangeModel,
        client: WildwoodClient
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Panel", selection: $selectedPanel) {
                ForEach(visiblePanels, id: \.self) { panel in
                    Text(panel.rawValue).tag(panel)
                }
            }
            .pickerStyle(.segmented)

            PlanChangeNoticeView(flow: flow, labels: labels, collectsPaymentInApp: true)

            // The flow's own notice carries a failed change's message, so the data layer's copy of
            // it is not shown a second time.
            if !model.errorMessage.isEmpty, flow.step != .failed {
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
                panelBody(selectedPanel, model: model, flow: flow)
            }
        }
        .wildwoodPlanChangeSheets(
            flow: flow,
            client: client,
            appId: model.appId,
            labels: labels,
            paymentActionHandler: resolveHandler(client),
            hasHostPaymentHandler: onPaymentRequired != nil,
            onError: onError
        )
    }

    @ViewBuilder private func panelBody(
        _ panel: Panel,
        model: WildwoodSubscriptionAdminModel,
        flow: WildwoodPlanChangeModel
    ) -> some View {
        switch panel {
        case .status:
            SubscriptionStatusPanel(model: model)
        case .tierPlans:
            TierPlansPanel(model: model, onSelectTier: { selection in flow.selectTier(selection) })
        case .features:
            FeaturesPanel(model: model, includedLabel: labels.featureIncluded)
        case .addOns:
            AddOnsPanel(model: model, labels: labels.addOnsPanelLabels)
        case .usageLimits:
            UsageLimitsPanel(model: model)
        case .overrides:
            OverridesPanel(model: model)
        }
    }

    private var visiblePanels: [Panel] {
        scope.isAdmin ? Panel.allCases : Panel.allCases.filter { $0 != .overrides }
    }

    private func resolveHandler(_ client: WildwoodClient) -> (any WildwoodPaymentActionHandler)? {
        WildwoodPaymentAction.resolve(
            parameter: paymentActionHandler,
            environment: environmentPaymentActionHandler,
            client: client
        )
    }

    private func start() async {
        guard model == nil,
              let client = requireClient(client, component: "SubscriptionAdminComponent")
        else { return }
        guard let resolvedAppId = appId ?? client.config.appId, !resolvedAppId.isEmpty else { return }

        let created = WildwoodSubscriptionAdminModel(client: client, appId: resolvedAppId, scope: scope)
        let change = WildwoodPlanChangeModel(
            client: client,
            admin: created,
            paymentActionHandler: resolveHandler(client)
        )
        change.labels = labels
        change.onPaymentRequired = onPaymentRequired
        // No `onChanged`: the flow settles its own change — entitlement cache dropped, status,
        // features and limits re-read — and this container shows nothing else that a plan move
        // changes. Reloading here too would fetch all three a second time per change.
        change.onError = onError

        resolvedClient = client
        model = created
        flow = change

        await created.loadAll()
    }
}
#endif
