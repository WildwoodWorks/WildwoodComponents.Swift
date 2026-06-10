// Platform detection ported from @wildwood/core/src/platform/platformDetection.ts.
// On native iOS the distribution source comes from the app's receipt environment
// rather than userAgent sniffing: App Store builds carry a production receipt,
// TestFlight a sandbox receipt, and Xcode/simulator builds none (or a sandbox
// receipt with a debug provisioning profile).

import Foundation

public enum WildwoodPlatform: String, Sendable {
    case ios
    case android
    case macos
    case windows
    case web
    case unknown
}

public enum DistributionSource: String, Sendable {
    case appleAppStore = "apple-app-store"
    case googlePlayStore = "google-play-store"
    case webBrowser = "web-browser"
    case testflight
    case sideloaded
    case development
    case unknown
}

public struct WildwoodPlatformInfo: Sendable, Equatable {
    public var platform: WildwoodPlatform
    public var isMobile: Bool
    public var isDesktop: Bool
    public var isBrowser: Bool
    public var deviceInfo: String
    public var language: String
    public var distributionSource: DistributionSource
    public var requiresAppStorePayment: Bool
    public var supportsApplePay: Bool
    public var supportsGooglePay: Bool
}

public enum PlatformDetection {
    /// Detect the current platform. `treatDevelopmentAsAppStore` forces the
    /// App Store payment path during development/TestFlight so StoreKit sandbox
    /// flows can be exercised end-to-end.
    public static func detectPlatform(treatDevelopmentAsAppStore: Bool = false) -> WildwoodPlatformInfo {
        #if os(iOS)
        let platform = WildwoodPlatform.ios
        let isMobile = true
        #elseif os(macOS)
        let platform = WildwoodPlatform.macos
        let isMobile = false
        #else
        let platform = WildwoodPlatform.unknown
        let isMobile = false
        #endif

        var source = detectDistributionSource()
        if treatDevelopmentAsAppStore, source == .development || source == .testflight {
            source = .appleAppStore
        }

        return WildwoodPlatformInfo(
            platform: platform,
            isMobile: isMobile,
            isDesktop: !isMobile,
            isBrowser: false,
            deviceInfo: deviceInfo(),
            language: Locale.current.identifier,
            distributionSource: source,
            requiresAppStorePayment: source == .appleAppStore || source == .googlePlayStore,
            supportsApplePay: platform == .ios || platform == .macos,
            supportsGooglePay: false
        )
    }

    /// Distribution source from the app receipt: production receipt → App Store,
    /// sandboxReceipt → TestFlight, none → development (simulator/Xcode build).
    public static func detectDistributionSource() -> DistributionSource {
        #if targetEnvironment(simulator)
        return .development
        #else
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            return .development
        }
        if receiptURL.lastPathComponent == "sandboxReceipt" {
            return .testflight
        }
        if FileManager.default.fileExists(atPath: receiptURL.path) {
            return .appleAppStore
        }
        return .development
        #endif
    }

    /// Mirrors JS `isProviderAvailable`: under App Store distribution only the
    /// required store provider is available; otherwise standard providers pass.
    public static func isProviderAvailable(_ providerType: PaymentProviderType, platformInfo: WildwoodPlatformInfo? = nil) -> Bool {
        let info = platformInfo ?? detectPlatform()

        if info.requiresAppStorePayment {
            if let required = requiredAppStoreProviderType(platformInfo: info), providerType != required {
                return false
            }
        }

        switch providerType {
        case .appleAppStore:
            return info.platform == .ios || info.platform == .macos
        case .googlePlayStore:
            return info.platform == .android
        case .applePay:
            return info.supportsApplePay
        case .googlePay:
            return info.supportsGooglePay
        case .stripe, .payPal, .square, .braintree, .authorizeNet,
             .klarna, .affirm, .afterpay, .razorpay, .adyen, .coinbase, .bitPay:
            return true
        }
    }

    /// The store provider the platform mandates, or nil when none is required.
    public static func requiredAppStoreProviderType(platformInfo: WildwoodPlatformInfo? = nil) -> PaymentProviderType? {
        let info = platformInfo ?? detectPlatform()
        switch info.distributionSource {
        case .appleAppStore: return .appleAppStore
        case .googlePlayStore: return .googlePlayStore
        default: return nil
        }
    }

    /// Hardware model + OS version, thread-safe (no UIKit dependency).
    public static func deviceInfo() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { buffer -> String in
            let data = Data(buffer.prefix(while: { $0 != 0 }))
            return String(data: data, encoding: .utf8) ?? "unknown"
        }
        #if os(iOS)
        let osName = "iOS"
        #elseif os(macOS)
        let osName = "macOS"
        #else
        let osName = "unknown"
        #endif
        return "\(machine); \(osName) \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }
}
