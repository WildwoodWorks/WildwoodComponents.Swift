// swift-tools-version: 6.2
// Pinned to 6.2 (not 6.4) until GitHub-hosted macOS runners ship Xcode 27;
// nothing in this package requires 6.4-only syntax. Bump when CI catches up.
import PackageDescription

let package = Package(
    name: "WildwoodComponents",
    platforms: [
        .iOS(.v26),
        // macOS is declared so `swift test` runs on a Mac host without a
        // simulator; it is not a supported product platform.
        .macOS(.v26),
    ],
    products: [
        .library(name: "WildwoodCore", targets: ["WildwoodCore"]),
        .library(name: "WildwoodSwiftUI", targets: ["WildwoodSwiftUI"]),
        // The accessibility-identifier vocabulary on its own, for a UI test target: Foundation
        // only, no dependency on either library above, so asserting an identifier never means
        // linking the views the test is driving. `WildwoodSwiftUI` re-exports it, so an app target
        // keeps seeing these types without naming this product.
        .library(name: "WildwoodTestIDs", targets: ["WildwoodTestIDs"]),
    ],
    targets: [
        .target(name: "WildwoodCore"),
        .target(name: "WildwoodTestIDs"),
        .target(name: "WildwoodSwiftUI", dependencies: ["WildwoodCore", "WildwoodTestIDs"]),
        .testTarget(name: "WildwoodCoreTests", dependencies: ["WildwoodCore"]),
        // No dependency on WildwoodTestIDs: the identifier assertions reach it through
        // WildwoodSwiftUI's re-export, which is the path a host takes, so the re-export is
        // exercised rather than assumed.
        .testTarget(name: "WildwoodSwiftUITests", dependencies: ["WildwoodSwiftUI"]),
    ],
    swiftLanguageModes: [.v6]
)
