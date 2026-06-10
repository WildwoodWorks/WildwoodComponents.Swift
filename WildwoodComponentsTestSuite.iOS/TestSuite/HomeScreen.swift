import SwiftUI
import WildwoodCore
import WildwoodSwiftUI

enum TestScreen: String, CaseIterable, Identifiable {
    case authentication = "Authentication"
    case tokenRegistration = "Token Registration"
    case signupWithSubscription = "Signup + Subscription"
    case twoFactor = "Two-Factor Settings"
    case aiChat = "AI Chat"
    case messaging = "Secure Messaging"
    case notification = "Notifications"
    case notificationToast = "Notification Toasts"
    case payment = "Payment"
    case paymentForm = "Payment Form"
    case pricingDisplay = "Pricing Display"
    case appTier = "App Tier"
    case subscriptionAdmin = "Subscription Admin"
    case usageDashboard = "Usage Dashboard"
    case disclaimer = "Disclaimers"
    case feedback = "Feedback"
    case theme = "Theme"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .authentication: return "person.badge.key"
        case .tokenRegistration: return "ticket"
        case .signupWithSubscription: return "person.crop.circle.badge.plus"
        case .twoFactor: return "lock.shield"
        case .aiChat: return "bubble.left.and.text.bubble.right"
        case .messaging: return "envelope.badge"
        case .notification: return "bell"
        case .notificationToast: return "bell.badge"
        case .payment: return "creditcard"
        case .paymentForm: return "creditcard.and.123"
        case .pricingDisplay: return "tag"
        case .appTier: return "square.stack.3d.up"
        case .subscriptionAdmin: return "gearshape.2"
        case .usageDashboard: return "gauge.with.dots.needle.50percent"
        case .disclaimer: return "doc.text"
        case .feedback: return "exclamationmark.bubble"
        case .theme: return "paintpalette"
        }
    }
}

struct HomeScreen: View {
    @Bindable var store: ClientStore
    @Environment(\.wildwoodClient) private var client

    var body: some View {
        NavigationStack {
            List {
                Section {
                    sessionStatusRow
                }
                Section("Component Tests") {
                    ForEach(TestScreen.allCases) { screen in
                        NavigationLink(value: screen) {
                            Label(screen.rawValue, systemImage: screen.icon)
                        }
                    }
                }
            }
            .navigationTitle("Wildwood Test Suite")
            .navigationDestination(for: TestScreen.self) { screen in
                TestScreenHost(screen: screen, store: store)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsScreen(store: store)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    @ViewBuilder private var sessionStatusRow: some View {
        if let session = client?.session {
            HStack {
                Circle()
                    .fill(session.isAuthenticated ? .green : .gray)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.isAuthenticated ? "Signed in" : "Not signed in")
                        .font(.subheadline.weight(.medium))
                    if let email = session.userEmail {
                        Text(email).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(TestSuiteConfig.baseUrl)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if session.isAuthenticated {
                    Button("Sign Out") {
                        Task {
                            await client?.auth.logout()
                            client?.session.logout()
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }
}
