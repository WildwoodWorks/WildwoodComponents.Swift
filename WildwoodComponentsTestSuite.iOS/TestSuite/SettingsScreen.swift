import SwiftUI
import WildwoodCore

struct SettingsScreen: View {
    @Bindable var store: ClientStore

    @State private var baseUrl = TestSuiteConfig.baseUrl
    @State private var appId = TestSuiteConfig.appId
    @State private var applied = false

    var body: some View {
        Form {
            Section("Wildwood API") {
                TextField("Base URL", text: $baseUrl)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("App ID", text: $appId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                Button("Apply & Rebuild Client") {
                    UserDefaults.standard.set(baseUrl, forKey: TestSuiteConfig.baseUrlDefaultsKey)
                    UserDefaults.standard.set(appId, forKey: TestSuiteConfig.appIdDefaultsKey)
                    store.reset()
                    applied = true
                }
                Button("Reset to Build Defaults", role: .destructive) {
                    UserDefaults.standard.removeObject(forKey: TestSuiteConfig.baseUrlDefaultsKey)
                    UserDefaults.standard.removeObject(forKey: TestSuiteConfig.appIdDefaultsKey)
                    baseUrl = TestSuiteConfig.baseUrl
                    appId = TestSuiteConfig.appId
                    store.reset()
                    applied = true
                }
            } footer: {
                if applied {
                    Text("Client rebuilt with the new configuration.")
                }
            }
            Section("Platform") {
                LabeledContent("Distribution", value: PlatformDetection.detectPlatform().distributionSource.rawValue)
                LabeledContent("Device", value: PlatformDetection.deviceInfo())
            }
        }
        .navigationTitle("Settings")
    }
}
