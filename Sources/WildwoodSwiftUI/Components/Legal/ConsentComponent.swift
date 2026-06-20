#if os(iOS)
// Consent banner + preferences sheet. Parity with the React Native ConsentComponent and the
// Blazor/Razor ConsentBanner.
//
// NOTE: Apple platforms have no DOM and no web pixels, so the script-injection half of consent does
// NOT apply here. This component ships the banner + preferences UI and the consent-state store (via
// WildwoodConsentModel); native SDKs should check `isGranted(_:)` before initializing.

import SwiftUI
import WildwoodCore

public struct ConsentComponent: View {
    @Environment(\.wildwoodClient) private var client

    private let appId: String?
    private let autoInit: Bool
    private let showReopenLink: Bool
    private let showFooterOptOut: Bool
    private let onConsentChanged: ((ConsentState) -> Void)?
    private let onError: ((String) -> Void)?

    @State private var model: WildwoodConsentModel?
    @State private var showBanner = false
    @State private var showPreferences = false
    @State private var selection: [ConsentCategory: Bool] = [:]

    public init(
        appId: String? = nil,
        autoInit: Bool = true,
        showReopenLink: Bool = true,
        showFooterOptOut: Bool = true,
        onConsentChanged: ((ConsentState) -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        self.appId = appId
        self.autoInit = autoInit
        self.showReopenLink = showReopenLink
        self.showFooterOptOut = showFooterOptOut
        self.onConsentChanged = onConsentChanged
        self.onError = onError
    }

    public var body: some View {
        Group {
            if let config = model?.config, config.enabled {
                VStack(alignment: .leading, spacing: 12) {
                    if showBanner {
                        bannerView(config: config)
                    }
                    footerLinks(config: config)
                }
            }
        }
        .sheet(isPresented: $showPreferences) {
            if let config = model?.config {
                preferencesSheet(config: config)
            }
        }
        .task { await start() }
    }

    // MARK: - Banner

    @ViewBuilder
    private func bannerView(config: PublicConsentConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(bannerTitle(config))
                .font(.headline)
            Text(bannerBody(config))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let urlString = config.privacyPolicyUrl, let url = URL(string: urlString) {
                Link("Privacy Policy", destination: url)
                    .font(.subheadline)
            }
            HStack {
                Button(manageLabel(config)) { openPreferences() }
                    .buttonStyle(.bordered)
                Button(rejectLabel(config)) { Task { await rejectAll() } }
                    .buttonStyle(.bordered)
                Button(acceptLabel(config)) { Task { await acceptAll() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cookie consent")
    }

    // MARK: - Preferences sheet

    @ViewBuilder
    private func preferencesSheet(config: PublicConsentConfig) -> some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Strictly necessary", isOn: .constant(true))
                        .disabled(true)
                } footer: {
                    Text("Always on")
                }

                Section("Categories") {
                    ForEach(model?.activeCategories() ?? [], id: \.self) { category in
                        Toggle(category.displayName, isOn: Binding(
                            get: { selection[category] == true },
                            set: { selection[category] = $0 }
                        ))
                    }
                }

                if config.showDoNotSell || config.showLimitSensitive {
                    Section {
                        if config.showDoNotSell {
                            Button("Do Not Sell or Share My Personal Information") {
                                Task { await optOut(.advertising) }
                            }
                        }
                        if config.showLimitSensitive {
                            Button("Limit the Use of My Sensitive Personal Information") {
                                Task { await optOut(.sensitive) }
                            }
                        }
                    }
                }

                if config.privacyPolicyUrl != nil || config.accessibilityUrl != nil {
                    Section {
                        if let urlString = config.privacyPolicyUrl, let url = URL(string: urlString) {
                            Link("Privacy Policy", destination: url)
                        }
                        if let urlString = config.accessibilityUrl, let url = URL(string: urlString) {
                            Link("Accessibility", destination: url)
                        }
                    }
                }
            }
            .navigationTitle("Privacy preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showPreferences = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await savePreferences() } }
                }
            }
        }
    }

    // MARK: - Footer entry points

    @ViewBuilder
    private func footerLinks(config: PublicConsentConfig) -> some View {
        if !showBanner, footerVisible(config) {
            HStack(spacing: 16) {
                if showReopenLink {
                    Button("Privacy choices") { openPreferences() }
                }
                if showFooterOptOut, config.showDoNotSell {
                    Button("Do Not Sell or Share") { Task { await optOut(.advertising) } }
                }
                if showFooterOptOut, config.showLimitSensitive {
                    Button("Limit Use of Sensitive PI") { Task { await optOut(.sensitive) } }
                }
            }
            .font(.footnote)
        }
    }

    private func footerVisible(_ config: PublicConsentConfig) -> Bool {
        showReopenLink || (showFooterOptOut && (config.showDoNotSell || config.showLimitSensitive))
    }

    // MARK: - Actions

    private func start() async {
        guard model == nil else { return }
        guard let client = requireClient(client, component: "ConsentComponent") else { return }
        let model = WildwoodConsentModel(client: client, appId: appId)
        self.model = model
        if autoInit {
            await model.initialize()
            // The banner UI fails closed (renders nothing) on a config-load error; surface it to the
            // host via onError so it isn't silently swallowed.
            if let message = model.errorMessage { onError?(message) }
            showBanner = model.shouldShowBanner
        }
    }

    private func openPreferences() {
        guard let model, model.config != nil else { return }
        var initial: [ConsentCategory: Bool] = [:]
        for category in model.activeCategories() {
            initial[category] = model.state?.categories[category] == true
        }
        selection = initial
        showPreferences = true
    }

    private func acceptAll() async {
        await model?.acceptAll()
        finishDecision()
    }

    private func rejectAll() async {
        await model?.rejectAll()
        finishDecision()
    }

    private func savePreferences() async {
        await model?.setCategories(selection)
        finishDecision()
    }

    /// One-click CCPA opt-out: turn a category off against the current granted state, record now.
    private func optOut(_ category: ConsentCategory) async {
        guard let model, model.config != nil else { return }
        var next: [ConsentCategory: Bool] = [:]
        for active in model.activeCategories() {
            next[active] = active == category ? false : (model.state?.categories[active] == true)
        }
        await model.setCategories(next)
        finishDecision()
    }

    private func finishDecision() {
        showBanner = false
        showPreferences = false
        if let state = model?.state {
            onConsentChanged?(state)
        }
    }

    // MARK: - Banner copy

    private func bannerTitle(_ config: PublicConsentConfig) -> String {
        config.bannerText?.title ?? "We value your privacy"
    }

    private func bannerBody(_ config: PublicConsentConfig) -> String {
        config.bannerText?.body ?? "Choose which categories to allow. Necessary items are always on."
    }

    private func acceptLabel(_ config: PublicConsentConfig) -> String {
        config.bannerText?.acceptAll ?? "Accept all"
    }

    private func rejectLabel(_ config: PublicConsentConfig) -> String {
        config.bannerText?.rejectAll ?? "Reject all"
    }

    private func manageLabel(_ config: PublicConsentConfig) -> String {
        config.bannerText?.manage ?? "Manage preferences"
    }
}
#endif
