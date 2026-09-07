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

    @State private var isRevealed = false

    init(_ titleKey: LocalizedStringKey, text: Binding<String>, contentType: UITextContentType = .password) {
        self.titleKey = titleKey
        self._text = text
        self.contentType = contentType
    }

    var body: some View {
        HStack(spacing: 8) {
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
}
#endif
