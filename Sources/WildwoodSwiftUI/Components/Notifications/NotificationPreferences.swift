#if os(iOS)
// Notification delivery preferences — parity with NotificationPreferences in the
// React Native package. Manages email + SMS opt-outs, persisted immediately on
// toggle via the model's save(). Push is OS-governed, so it is shown as an
// informational row ("Managed in device settings") rather than a toggle that
// would fight the platform. No browser channel (web-only).

import SwiftUI
import WildwoodCore

public struct NotificationPreferences: View {
    @Environment(\.wildwoodClient) private var client

    private let appId: String?
    private let showPushNotice: Bool

    @State private var model: WildwoodNotificationPreferencesModel?
    @State private var draft: UserNotificationPreference

    public init(appId: String? = nil, showPushNotice: Bool = true) {
        self.appId = appId
        self.showPushNotice = showPushNotice
        _draft = State(initialValue: .createDefault(appId: appId ?? ""))
    }

    public var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                LoadingSpinnerView(label: "Loading preferences…")
            }
        }
        .task {
            guard model == nil, let client = requireClient(client, component: "NotificationPreferences") else { return }
            let resolvedAppId = appId ?? client.config.appId
            if draft.appId.isEmpty, let resolvedAppId {
                draft.appId = resolvedAppId
            }
            let created = WildwoodNotificationPreferencesModel(client: client)
            model = created
            await created.load(appId: resolvedAppId)
            if let loaded = created.preferences {
                draft = loaded
            }
        }
    }

    @ViewBuilder
    private func content(_ model: WildwoodNotificationPreferencesModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Notification Preferences").font(.headline)
                Spacer()
                if model.isSaving {
                    Text("Saving…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 8)

            if let error = model.errorMessage {
                ErrorBannerView(message: error)
                    .padding(.bottom, 8)
            }

            Toggle("Email notifications", isOn: channelBinding(model, keyPath: \.emailEnabled))
                .disabled(model.isSaving)
                .padding(.vertical, 10)

            Divider()

            Toggle("SMS notifications", isOn: channelBinding(model, keyPath: \.smsEnabled))
                .disabled(model.isSaving)
                .padding(.vertical, 10)

            if showPushNotice {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Push notifications").font(.body)
                    Text("Managed in device settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
            }
        }
        .padding()
    }

    /// Two-way binding for a Bool channel that mutates the local draft and persists
    /// it on every change (mirrors the React Native toggle → save() flow).
    private func channelBinding(
        _ model: WildwoodNotificationPreferencesModel,
        keyPath: WritableKeyPath<UserNotificationPreference, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                draft[keyPath: keyPath] = newValue
                let next = draft
                Task { await model.save(next) }
            }
        )
    }
}
#endif
