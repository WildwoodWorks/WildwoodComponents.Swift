# WildwoodComponents.Swift

Native Swift/SwiftUI SDK for the [Wildwood platform](https://admin.wildwoodworks.io) — the third
implementation of the WildwoodComponents library, at feature parity with
[WildwoodComponents.Net](https://github.com/WildwoodWorks/WildwoodComponents.Net) (Blazor/Razor) and
[WildwoodComponents.JS](https://github.com/WildwoodWorks/WildwoodComponents.JS) (React/React Native/Node).

Pre-built, production-ready SwiftUI components for authentication, AI chat, secure messaging,
payments and subscriptions, app tiers, two-factor security, disclaimers, notifications, usage
dashboards, and feedback — all backed by the WildwoodAPI.

## Requirements

- iOS 26.0+ (iOS 27 features adopted behind `@available(iOS 27, *)` gates)
- Xcode 27 beta / Swift 6.2+ toolchain
- Swift 6 language mode (strict concurrency)

## Products

| Product | Purpose | JS equivalent |
|---------|---------|---------------|
| `WildwoodCore` | Services, models, session/token management, storage — zero UI dependencies | `@wildwood/core` |
| `WildwoodSwiftUI` | SwiftUI components + `@Observable` view models | `@wildwood/react-native` + `@wildwood/react-shared` |

## Installation

```swift
.package(url: "https://github.com/WildwoodWorks/WildwoodComponents.Swift.git", from: "0.1.0")
```

## Quick start

```swift
import WildwoodCore
import WildwoodSwiftUI

@main
struct MyApp: App {
    @State private var client = WildwoodClient(
        config: WildwoodConfig(
            baseURL: URL(string: "https://api.wildwoodworks.io/")!,
            appId: "your-app-id"
        )
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .wildwoodClient(client)
        }
    }
}
```

## Test suite

`WildwoodComponentsTestSuite.iOS/` is an XcodeGen-defined iOS app with one test screen per
component, mirroring the Blazor and React test suites. On a Mac:

```bash
cd WildwoodComponentsTestSuite.iOS
xcodegen generate
open WildwoodComponentsTestSuite.xcodeproj
```

Configure the API base URL and app ID in `Config/Local.xcconfig` (gitignored) or in the app's
Settings screen.

## Building

```bash
swift build      # macOS host
swift test       # unit tests (swift-testing)
```

## License

MIT — see [LICENSE](LICENSE).
