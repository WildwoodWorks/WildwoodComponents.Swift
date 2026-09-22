// `WildwoodTestIDs` is re-exported, so moving the identifier vocabulary out of this module broke
// nothing for the hosts that already had it.
//
// The vocabulary is its own Foundation-only target because a UI test target must be able to name
// `disclaimer-accept-all` without linking SwiftUI or this package's views. But two of the moved
// types are ordinary public API here — ``ManageSection`` is the element type of
// ``RegistrationSubscriptionManageView``'s `sections:` parameter, and the identifier enums are
// documented in the README — so a host that writes `let sections: [ManageSection]` after
// `import WildwoodSwiftUI` must keep compiling. Re-exporting is how it does.
//
// `@_exported` is an underscored attribute and is used deliberately: Swift offers no other
// spelling for re-export, and the failure mode here is loud rather than silent. This package's
// tests reach these types through this
// line and nothing else — `WildwoodSwiftUITests` declares no dependency on `WildwoodTestIDs` and
// imports it in no file — so if the attribute ever stops re-exporting, the test target stops
// compiling on the next CI run.
//
// Imports are file-scoped, so this line does NOT serve the rest of this module: every file here
// that NAMES one of those types carries its own `import WildwoodTestIDs`.

@_exported import WildwoodTestIDs
