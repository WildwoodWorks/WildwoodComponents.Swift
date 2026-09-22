#if os(iOS)
// Password field with a reveal toggle — the SwiftUI twin of the eye / eye-slash
// button in the React and Blazor AuthenticationComponents. Swaps SecureField and
// TextField over one binding; the content type is preserved so AutoFill and
// strong-password suggestions keep working in both states.

import SwiftUI
import UIKit

struct WildwoodSecureField: View {
    private let titleKey: LocalizedStringKey
    @Binding private var text: String
    private let contentType: UITextContentType
    /// An accessibility identifier for the ENTRY alone. Taken here rather than applied to the whole
    /// control by a caller, because the reveal button is a second accessibility element inside it
    /// and would answer to the same string — two elements under one identifier is a worse locator
    /// than none. Omitted, the control names nothing, which is what every non-test caller wants.
    private let identifier: String?

    @State private var isRevealed = false

    init(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        contentType: UITextContentType = .password,
        identifier: String? = nil
    ) {
        self.titleKey = titleKey
        self._text = text
        self.contentType = contentType
        self.identifier = identifier
    }

    var body: some View {
        HStack(spacing: 8) {
            if let identifier {
                entry.accessibilityIdentifier(identifier)
            } else {
                entry
            }

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
        }
        .textFieldStyle(.roundedBorder)
    }

    /// Whichever of the two fields is showing. Exactly one of them renders, so an identifier
    /// applied to this lands on one element.
    private var entry: some View {
        Group {
            if isRevealed {
                TextField(titleKey, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                SecureField(titleKey, text: $text)
            }
        }
        .textContentType(contentType)
    }
}
#endif
