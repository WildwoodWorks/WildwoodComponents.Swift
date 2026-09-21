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

## Registration & Subscription

One component over everything a customer does with money: see the price list, sign up and buy, and
manage what they bought. `RegistrationAndSubscriptionComponent` is a switch and nothing more — each
of the three views is public on its own, for a screen that would rather pick a type than pass a
value.

```swift
import WildwoodCore
import WildwoodSwiftUI

// Pricing — no session needed. Hand the choice to your navigator.
RegistrationSubscriptionPricingView(
    showAddOns: true,
    packSelection: .multi,
    onSelect: { selection in
        path.append(Signup(tierId: selection.tierId, pricingId: selection.pricingId, packs: selection.addOnIds))
    }
)

// Signup — account, plan, packs, card.
RegistrationSubscriptionSignupView(
    preSelectedTierId: route.tierId,
    preSelectedPricingId: route.pricingId,
    preSelectedAddOnIds: route.packs,
    onSignupComplete: { outcome in path = NavigationPath() }
)

// Manage — the plan, its packs, features, usage and (for an admin) overrides.
RegistrationSubscriptionManageView(
    layout: .stacked,
    allowPackSelfService: true,
    onEntitlementsChanged: { reason in refreshGates(reason) }
)

// Or the shell, when the surface comes out of a route rather than out of the source:
RegistrationAndSubscriptionComponent(.manage(RegistrationSubscriptionManageConfiguration()))
```

The shell takes a `RegistrationSubscriptionScreen` — `.pricing`, `.signup` or `.manage`, each
carrying that view's own configuration struct (`RegistrationSubscriptionPricingConfiguration`,
`…SignupConfiguration`, `…ManageConfiguration`). Every configuration member is the view's own
parameter under the same name, and every one is defaulted except `onSelect` on pricing, so
`init(configuration:)` and the view's designated initializer cannot drift.

| View | Parameters |
|---|---|
| **Pricing** | `appId`, `currency`, `contactUrl`, `showPlans`, `showAddOns`, `offerFreeTierChoice`, `packSelection` (`.none` / `.multi`), `packPurchaseAvailable`, `addOnGroups`, `describeAddOn`, `showBillingToggle`, `defaultBilling`, `showFeatureComparison`, `showLimits`, `highlightTierId`, `labels`, `onError`, `onSelect` |
| **Signup** | `appId`, `preSelectedTierId`, `preSelectedPricingId`, `preSelectedAddOnIds`, `registrationToken`, `prefillEmail`, `planSelection` (`.choose` / `.skip`), `planDefault` (`.none` / `.free`), `packSelection` (`.choose` / `.none`), `tokenMode` (`.auto` / `.required`), `paymentOrder`, `requireBillingAddress`, `packPurchaseAvailable`, `paymentActionHandler`, `currency`, `contactUrl`, `closedMessage`, `labels`, `onAlreadySignedIn`, `onSignupComplete`, `onCancel`, `onEntitlementsChanged`, `onError` |
| **Manage** | `appId`, `layout` (`.tabs` / `.stacked`), `sections`, `showStatusAboveTabs`, `isAdmin`, `userId`, `companyId`, `allowPackSelfService`, `allowCancel`, `showAddOns`, `paymentActionHandler`, `currency`, `contactUrl`, `labels`, `onMergeUsage`, `onPaymentRequired`, `onSubscriptionChanged`, `onEntitlementsChanged`, `onError` |

Every user-facing string is a member of `RegistrationSubscriptionLabels`, defaulted to the same
words the React and React Native packages say; override only the ones you are replacing.
`RegistrationSubscriptionPricingLabels` and `…SignupLabels` are typealiases of it, which is why the
signup view takes a second `pricingLabels` for the grids inside it while the configuration's single
`labels` feeds both.

### The plan the grid opens on (`planDefault`)

`planDefault: .free` opens the plan step MARKED on the app's free plan — a suggestion the visitor
still taps, not a choice already made. Nothing else changes: the step still runs, the flow's state
machine never sees the default, and it is ignored in invite mode (`tokenMode: .required`), where
the plan comes from the token, and when the app sells no free plan. The grid marks
`state.selection.tierId ?? planDefault's tier ?? preSelectedTierId` — the default sits AHEAD of a
link's `?tier=` on purpose, because a stale or hand-edited one is an id the flow already refused.

### Account first, and `paymentOrder`

`paymentOrder` defaults to `.afterAccount` here; the web defaults to `beforeAccount`. A store
purchase that succeeds before a registration that then fails strands a paid subscription with
nobody to attach it to — a support ticket, not a void. An account with no plan is the cheaper and
the recoverable failure, so it is the one this stack risks, and a customer who walks away from the
card still finishes signup: the outcome carries `planActivationPending == true` and the success
panel says activation is pending. Pass `.beforeAccount` for the web's order if you bill by card
only.

### Tokens and invites

A registration token that carries a plan has ALREADY subscribed the account, so the plan and
payment steps are skipped and nothing self-subscribes over the grant. `tokenMode: .required` is
invite redemption: the token step is the only way in. The invite preset is that plus
`planSelection: .skip`, `packSelection: .none` and `prefillEmail`.

`onSignupComplete` reports a `SignupOutcome`: `userId`, the `tier` that ended up active, the
`packs` (granted ones first), the `tokenGrant` the token set up, and `planActivationPending`.

### Dynamic pricing

Every price comes off the app's live public catalog through `client.catalog` (60 s per app and
currency, one in-flight load, failures never cached). There is no fallback price, no remembered
price and no "from" price: while the catalog loads the visitor sees shapes, and if it cannot be
read they see "Pricing is unavailable right now" and a Retry — never a number the server did not
just quote.

### The payment-action handler (host code)

This package takes **no Stripe dependency**. A card sheet and a bank's 3-D Secure challenge need a
native module and merchant configuration, so the one thing the flows cannot do for themselves is
injected — `WildwoodPaymentActionHandler`, the same seam as `FeedbackComponent`'s screenshot
source. In an app that already ships the Stripe iOS SDK it is about twenty lines, and it is YOUR
code, not the SDK's:

```swift
import Stripe          // the host app's dependency, not WildwoodSwiftUI's
import WildwoodCore

struct StripePaymentActionHandler: WildwoodPaymentActionHandler {
    func confirmPayment(clientSecret: String, publishableKey: String?) async -> PaymentActionOutcome {
        if let publishableKey { StripeAPI.defaultPublishableKey = publishableKey }
        let params = STPPaymentIntentParams(clientSecret: clientSecret)
        return await withCheckedContinuation { continuation in
            STPPaymentHandler.shared().confirmPayment(params, with: authenticationContext) { status, _, error in
                switch status {
                case .succeeded: continuation.resume(returning: .succeeded)
                case .canceled: continuation.resume(returning: .cancelled)
                case .failed: continuation.resume(returning: .failed(message: error?.localizedDescription ?? ""))
                @unknown default: continuation.resume(returning: .failed(message: ""))
                }
            }
        }
    }

    func confirmCardSetup(clientSecret: String, publishableKey: String?) async -> PaymentActionOutcome {
        // Same shape over STPSetupIntentConfirmParams. A handler that cannot do this returns
        // .failed AND overrides `supportsCardSetup` to false, so no SetupIntent is ever requested.
    }
}
```

Wire it once with `.wildwoodPaymentActionHandler(handler)` and every Wildwood surface in the
subtree picks it up; a view's own `paymentActionHandler` parameter wins over the environment, and
the environment over `WildwoodClient.paymentActionHandler`.

**Without a handler** nothing fails silently. `SupportsPaymentAction` and `supportsSetupIntent` are
never sent, no checkout payment method is created, an in-app pack purchase is offered only when
the server's quote says a card is already on file (`UseSavedCard: true`), and a `requires_action`
answer that arrives anyway is reported as NOT completed with "finish this purchase on the web"
copy. The plan change is posted in the plain form, so the server refuses a change that needs a
challenge instead of parking one nobody can finish. The card sheet itself still works with no
handler: `PaymentComponent` completes a payment through StoreKit, the provider's own page or a
server-owned completion with no SDK at all.

**A plan change's card** comes from your own `onPaymentRequired` when you pass one, and its answer
is final (a transaction id completes the change, `nil` abandons it). Without one the manage view's
own payment sheet takes it; closing that returns to the confirmation with the priced change intact.

### App-Store-billed apps

When the app is store-exclusive (`requiresAppStorePayment`), plans are bought from the store and
pack PURCHASE is not offered — there is no in-app-purchase product behind an add-on. Owned, bundled
and complimentary packs still render and can still be cancelled, and the plan-change confirmation
drops the server's proration figures for a notice saying the store manages billing for the change.

### Signup deep links

A signup or invite link is `SignupParams`:

```swift
ContentView()
    .onOpenURL { url in
        let params = SignupParams.parse(url: url)   // ?tier= ?pricing= ?addons= ?token= ?invite= ?email=
        route = .signup(params)
    }
```

The signup view also reads `.onOpenURL` itself: a link that lands while the form is open folds its
plan, packs, token and email in and restarts the flow on them. The same URL reaches Campaign
Attribution through `.wildwoodClient(_:)`, so nothing needs capturing twice.

### Testing hooks

Accessibility identifiers carry the web's `data-ww-*` VALUES unchanged
(`RegistrationSubscriptionTestID`): `pricing` / `signup` / `manage` for a view, the step name
(`register`, `packs`, `failed`, …) for a step, `pack:<id>`, `group:<id>`, `section:<name>`,
`modal:<name>`. One test plan reads the same on both stacks.

`DisclaimerComponent` carries the web's `data-ww-disclaimer-action` values, prefixed because a
SwiftUI identifier namespace is flat (`DisclaimerTestID`): `disclaimer-retry` on "Try again",
`disclaimer-accept` on a card's "I have read and accept", and `disclaimer-accept-all` on the
submit. The middle one is a toggle rather than a button here — this component accepts everything
ticked in one call — but it is the same control: the one that accepts THAT disclaimer.

### Deliberately different from React

| React prop | Here | Why |
|---|---|---|
| `className` | Not here. Accessibility identifiers and `.wildwoodTheme(_:)` take its place. | There is no cascade to hang a class on. |
| `initialCatalog`, `includeJsonLd` | Not here. | No server render to seed from, and no crawler to publish schema.org offers to. |
| `returnUrl` | Not here. | The web carries it and never navigates to it. Where a finished signup goes is the navigator's business — hang it on `onSignupComplete`. |
| `renderClosed`, `loadingFallback`, `errorFallback` | `closedMessage`, or compose around the view. | A `View`-typed slot means a generic parameter on the view AND on the shell that hosts it; no sibling in this package pays that price. |
| `paymentOrder` | Defaults to `.afterAccount`; the web is `beforeAccount`. | See "Account first" above. |
| `paymentActionHandler` | New. | There is no Stripe.js here. |
| `view="pricing" \| "signup" \| "manage"` plus that view's props | `RegistrationSubscriptionScreen` with a configuration per case. | Swift's answer to a discriminated union, and it keeps the shell non-generic. |

### One caveat: keep the flow on top

The signup and manage views detach their drivers in `onDisappear` — in-flight money is never
cancelled, but the callbacks are silenced. A host that PUSHES another screen over a signup or a
plan change mid-flow therefore comes back to a detached flow. Present these two views as the top of
their own navigation stack, or in a sheet.

### Deprecations

| Deprecated | Use instead | Migration |
|---|---|---|
| `SignupWithSubscriptionComponent` | `RegistrationSubscriptionSignupView` | Drop `requireToken` / `allowOpenRegistration` / `showOptionalTokenEntry` — the view reads the app's registration settings itself. `onSignupComplete` now hands you a `SignupOutcome` instead of the auth response plus a subscription result. |
| `AppTierComponent` | `RegistrationSubscriptionManageView` | `onTierChangeRequested` becomes `onPaymentRequired` (or nothing at all, and the view's own payment sheet takes the card). The change then runs through preview, confirmation, 3-D Secure and completion rather than one raw apply. |
| `PricingDisplayComponent` | `RegistrationSubscriptionPricingView` | `onTierSelected(tier, pricing)` becomes `onSelect(PricingSelection)`, which also carries the billing cycle and the chosen packs. |

All three keep working exactly as documented; nothing has been removed.

## Speech-to-text

`client.ai.transcribeAudio(audioData:contentType:configurationId:language:)` posts a recorded clip
to the app's configured provider and answers a `SpeechTranscriptionResult`
(`success`, `text`, `errorMessage`). It never throws for a business failure — no audio, a refused
format, a non-2xx, a dead network all come back as a failed result with a message you can show as
it stands. The only thing it throws is `CancellationError`.

```swift
let result = try await client.ai.transcribeAudio(
    audioData: recordedData,          // e.g. an AVAudioRecorder file read back
    contentType: "audio/m4a",         // webm, ogg, mp4, m4a, mp3, wav
    configurationId: configurationId,
    language: "en-US"
)
if result.success { prompt += result.text } else { showError(result.errorMessage) }
```

**There is no voice UI in `AIChatComponent`, and none is planned.** Recording needs a microphone
usage string in the HOST's Info.plist and a recorder the host controls, and iOS already offers
on-device dictation in every text field for free. The host records and supplies the bytes; the SDK
keeps the server round trip. (The web stacks ship a recorder because a browser has no dictation
key — that divergence is deliberate.)

## Campaign attribution

`.wildwoodClient(_:)` starts attribution (`client.attribution.initialize()`) and captures every URL
the app opens, so deep links and universal links carrying `utm_*` tags or an ad click id become the
visitor's first/last touch. Registration then carries the payload automatically and drops it once
the signup is recorded; a provider sign-in (Sign in with Apple, Google) claims the touches for the
new account instead.

Injecting the client by hand? Add the capture modifier yourself, once:

```swift
ContentView()
    .environment(\.wildwoodClient, client)
    .wildwoodAttributionCapture(client)   // or: .onOpenURL { client.attribution.capture(url: $0) }
```

Touches are persisted only after the app's consent category (Analytics by default) is granted —
`ConsentService` decisions re-apply that gate on their own. Set
`WildwoodConfig(attributionEnabled: false)` to turn the whole engine off.

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

The app registers the `wildwoodtest` URL scheme, so signup links and campaign links can be walked
without a web domain:

```bash
xcrun simctl openurl booted "wildwoodtest://signup?tier=pro&addons=docs,api&utm_source=reddit"
```

The Registration & Subscription screen parses it with `SignupParams`, the signup view applies it,
and Campaign Attribution records the campaign — three readers of one link. That screen also carries
a clearly-labelled FAKE payment-action handler (a test double that confirms nothing) so the
handler branches can be exercised in the simulator without a payment SDK.

## Building

```bash
swift build      # macOS host
swift test       # unit tests (swift-testing)
```

## License

MIT — see [LICENSE](LICENSE).
