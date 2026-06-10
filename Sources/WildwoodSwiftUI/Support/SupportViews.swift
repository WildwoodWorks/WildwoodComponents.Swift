// Shared support views (LoadingSpinner / ErrorBanner equivalents of the JS
// common components).

import SwiftUI

public struct LoadingSpinnerView: View {
    private let label: String?

    public init(label: String? = nil) {
        self.label = label
    }

    public var body: some View {
        VStack(spacing: 8) {
            ProgressView()
            if let label {
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

public struct ErrorBannerView: View {
    private let message: String
    private let onDismiss: (() -> Void)?

    public init(message: String, onDismiss: (() -> Void)? = nil) {
        self.message = message
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
