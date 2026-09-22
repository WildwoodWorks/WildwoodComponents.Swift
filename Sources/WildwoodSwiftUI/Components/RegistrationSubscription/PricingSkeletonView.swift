#if os(iOS)
// The placeholder shown while the live catalog loads.
//
// Blocks, never numbers. A skeleton that shows a price — a remembered one, a "from" price, a zero
// — is a price the visitor may act on and the server never quoted, so there is nothing here to read
// but shapes. The only text is what a screen reader is told, and it comes from the labels.
//
// The twin of the React Native `PricingSkeleton` part.

import SwiftUI
import WildwoodTestIDs

public struct PricingSkeletonView: View {
    /// How many placeholder cards to draw.
    private let cards: Int
    /// What a screen reader hears while the prices load.
    private let label: String

    public init(cards: Int = 3, label: String) {
        self.cards = cards
        self.label = label
    }

    public var body: some View {
        VStack(spacing: 16) {
            ForEach(0 ..< max(cards, 1), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .frame(height: 160)
            }
        }
        .frame(maxWidth: .infinity)
        // One element, one sentence: a screen reader announces that prices are loading rather
        // than reading out several nameless rectangles.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier(RegistrationSubscriptionTestID.skeleton)
    }
}
#endif
