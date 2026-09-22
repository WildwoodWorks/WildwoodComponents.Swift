#if os(iOS)
// What a visitor sees when an app is not taking registrations.
//
// Its own view for the same reason the web keeps it apart: two very different screens need exactly
// the same words — the signup view when the app's authentication settings say registration is
// closed, and any host that wants to say so on a landing screen without mounting the signup flow
// at all.
//
// The contact link is rendered only when there is BOTH a URL to open and something to call it, so
// a host that supplied one without the other gets the notice rather than a button that goes
// nowhere.

import SwiftUI
import WildwoodTestIDs

public struct ClosedNoticeView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.wildwoodTheme) private var theme

    /// The sentence to show.
    let message: String
    /// Where a visitor who still wants in should go.
    let contactUrl: String?
    /// The link's text.
    let contactLabel: String?

    public init(message: String, contactUrl: String? = nil, contactLabel: String? = nil) {
        self.message = message
        self.contactUrl = contactUrl
        self.contactLabel = contactLabel
    }

    public var body: some View {
        let label: String = contactLabel ?? ""

        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.headline)

            if let destination = contactDestination, !label.isEmpty {
                Button(label) {
                    openURL(destination)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.info.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(RegistrationSubscriptionTestID.closedNotice)
    }

    private var contactDestination: URL? {
        guard let contactUrl, !contactUrl.isEmpty else { return nil }
        return URL(string: contactUrl)
    }
}
#endif
