# WildwoodComponents.Swift

## Overview

Native Swift/SwiftUI implementation of the WildwoodComponents library — the third stack alongside
WildwoodComponents.Net (`C:\Development\WildwoodComponents.Net\Dev`) and WildwoodComponents.JS
(`C:\Development\WildwoodComponents.JS\Dev`). All three implement the same component library
against the same WildwoodAPI backend. Parity is coordinated through the Sync repo
(`C:\Development\WildwoodComponents.Sync`).

## Architecture

```
WildwoodCore        ← services, models, session/token mgmt, storage (zero UI imports)
  └─► WildwoodSwiftUI
        ├─ ViewModels/   ← @Observable classes ≈ @wildwood/react-shared hooks (no `import SwiftUI` here)
        └─ Components/   ← SwiftUI views ≈ @wildwood/react-native components (same names)
```

- **WildwoodCore** mirrors `@wildwood/core`: `WildwoodClient` factory exposing `auth`, `session`,
  `ai` (chat, TTS, and `transcribeAudio` — server STT; no voice UI, see below), `aiFlow`,
  `aiFlowSubscriptions`, `documents`, `messaging`, `payment`, `appTier`, `features` (shared
  entitlement cache backing FeatureGate), `catalog` (shared public-catalog cache: 60 s TTL per app
  + currency override, one in-flight load, failures never cached), `twoFactor`, `captcha`,
  `disclaimer`, `feedback`, `consent`, `attribution`, `notifications`, `notificationInbox`,
  `theme`, `events`, `http`, plus the app-wide `paymentActionHandler` seam. Strict Swift 6
  concurrency: `WildwoodHttpClient` and `TokenRefreshCoordinator` are actors;
  `SessionManager`/`NotificationService`/`ThemeService`/`AttributionService`/`FeatureStore`/
  `PublicCatalogStore`/`WildwoodEventEmitter`/`WildwoodClient` are `@MainActor @Observable`;
  request/response services are stateless `Sendable` classes.
- **Components**: 46 `.swift` files under `Sources/WildwoodSwiftUI/Components/` (the Sync count
  rule — support types such as `TierCard`, `UsageMath` and `StorePurchaseSettlement` included).
  `RegistrationAndSubscriptionComponent` (September 2026) is the shell over
  `RegistrationSubscriptionPricingView` / `…SignupView` / `…ManageView`; it supersedes
  `SignupWithSubscriptionComponent`, `AppTierComponent` and `PricingDisplayComponent`, all three
  now `@available(*, deprecated)` but unchanged and still supported.
- **Test suite**: `WildwoodComponentsTestSuite.iOS/` — XcodeGen app (project.yml checked in,
  .xcodeproj generated on a Mac), one test screen per component: 21 `case`s of `TestScreen`
  (the Sync count rule), including `registrationSubscription` and `attribution`. Custom plist keys
  go through XcodeGen's `info:` block, never `INFOPLIST_KEY_*`; the app registers the
  `wildwoodtest` URL scheme there so `.onOpenURL` / `SignupParams` / attribution capture can be
  exercised (`xcrun simctl openurl booted "wildwoodtest://signup?tier=pro"`).

## Parity rules (CRITICAL)

- **Endpoint paths** must match the other stacks. Always pass endpoints as double-quoted string
  literals to `WildwoodHttpClient` verb methods (`http.post("api/auth/login", ...)`), with Swift
  interpolation inside the literal for route params. Never build raw `URLRequest`s in services —
  the Sync parity script extracts endpoints by regex from these literals.
- **Storage keys** use the exact shared literals in `WildwoodStorageKeys` (`ww_accessToken`,
  `ww_refreshToken`, `ww_user`, `ww_session_auth`, `ww_session_expiry`, `ww_theme`,
  `ww_draft_{threadId}`). The parity check hard-fails on drift.
- When porting or changing a service, copy endpoint strings verbatim from the JS source
  (`packages/wildwood-core/src/<domain>/`), never from memory.
- ViewModels must not `import SwiftUI` (keeps a future UIKit split mechanical).
- Run `node C:\Development\WildwoodComponents.Sync\scripts\parity-check.mjs` after service changes.

## Wire format

- WildwoodAPI is ASP.NET Core: camelCase JSON, case-insensitive request parsing. Use the default
  Codable key strategy and `WildwoodJSON.decoder()/encoder()` (handles .NET 7-digit fractional
  ISO 8601 dates).
- JWTs are decoded client-side for `exp` only (no signature verification) — same as the JS SDK.
  Auto-refresh fires at 80% of token lifetime; reactive 401 → single-flight refresh → replay once.

## Platform notes

- Min deployment iOS 26; iOS 27 APIs only behind `@available(iOS 27, *)` (and `#if` SDK guards
  while CI is on older Xcode).
- Tokens/user go to Keychain, other keys to UserDefaults (CompositeStorage default).
- Payments: provider selection is backend-driven via `PlatformFilteredProvidersDto` — never
  hardcode a processor. App Store path = StoreKit 2 → `payment.validateStorePurchase` →
  `api/payment/validate-apple-receipt` (body carries productId, the store transactionId,
  isRestore, and receiptData = the JWS) → `linkTransactionToUser` →
  `selfSubscribe(paymentTransactionId:)`. A StoreKit transaction is finished only after a
  successful validation that returned a Wildwood transactionId (restores: success alone) —
  see `StorePurchaseSettlement`. Other providers = generic `initiatePayment`/`confirmPayment`
  with external web checkout.

- Speech-to-text is **method-level parity only**: `AIService.transcribeAudio` posts multipart to
  `api/stt/transcribe` (file part `file`, `speech.<ext>` from the bare media type, optional
  `configurationId`/`language`) and never throws except on cancellation. There is deliberately no
  microphone UI in `AIChatComponent` — the usage strings belong in the HOST's Info.plist and iOS
  gives every text field dictation for free. Do not "fix" this against the web stacks.
- Payments/3-D Secure: no Stripe dependency. A host injects `WildwoodPaymentActionHandler`
  (parameter, then `.wildwoodPaymentActionHandler(_:)`, then `WildwoodClient.paymentActionHandler`).
  Without one the flows never send `SupportsPaymentAction`/`supportsSetupIntent`, never create a
  checkout payment method, and report a `requires_action` answer as "finish on the web".

## Commands (macOS only — code is authored on Windows, built on a Mac/CI)

```bash
swift build
swift test
cd WildwoodComponentsTestSuite.iOS && xcodegen generate && open WildwoodComponentsTestSuite.xcodeproj
```
