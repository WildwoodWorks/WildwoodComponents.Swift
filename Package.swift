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
    ],
    targets: [
        .target(name: "WildwoodCore"),
        .target(name: "WildwoodSwiftUI", dependencies: ["WildwoodCore"]),
        .testTarget(name: "WildwoodCoreTests", dependencies: ["WildwoodCore"]),
        .testTarget(name: "WildwoodSwiftUITests", dependencies: ["WildwoodSwiftUI"]),
    ],
    swiftLanguageModes: [.v6]
)
