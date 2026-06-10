// WildwoodComponents test suite — one screen per component, mirroring the
// Blazor and React test suites. API base URL + app id come from
// Config.xcconfig (via Info.plist), overridable at runtime in Settings.

import SwiftUI
import WildwoodCore
import WildwoodSwiftUI

enum TestSuiteConfig {
    static let baseUrlDefaultsKey = "testsuite.baseUrl"
    static let appIdDefaultsKey = "testsuite.appId"

    static var baseUrl: String {
        if let override = UserDefaults.standard.string(forKey: baseUrlDefaultsKey), !override.isEmpty {
            return override
        }
        let fromPlist = Bundle.main.object(forInfoDictionaryKey: "WildwoodAPIBaseURL") as? String
        return (fromPlist?.isEmpty == false ? fromPlist! : "https://api.wildwoodworks.io/")
    }

    static var appId: String {
        if let override = UserDefaults.standard.string(forKey: appIdDefaultsKey), !override.isEmpty {
            return override
        }
        return Bundle.main.object(forInfoDictionaryKey: "WildwoodAppId") as? String ?? ""
    }
}

@MainActor
@Observable
final class ClientStore {
    private(set) var client: WildwoodClient

    init() {
        client = Self.makeClient()
    }

    /// Rebuild the client after settings change.
    func reset() {
        client.dispose()
        client = Self.makeClient()
        Task { await client.initialize() }
    }

    private static func makeClient() -> WildwoodClient {
        WildwoodClient(
            config: WildwoodConfig(
                baseUrl: TestSuiteConfig.baseUrl,
                appId: TestSuiteConfig.appId.isEmpty ? nil : TestSuiteConfig.appId,
                enableAutoTokenRefresh: true
            )
        )
    }
}

@main
struct TestSuiteApp: App {
    @State private var store = ClientStore()

    var body: some Scene {
        WindowGroup {
            HomeScreen(store: store)
                .wildwoodClient(store.client)
                .overlay {
                    NotificationToastComponent()
                }
                .id(ObjectIdentifier(store.client)) // re-resolve environment on reset
        }
    }
}
