// WildwoodTheme name lookup — the mapping `.wildwoodClient(_:)` uses to turn the
// ThemeService's stored theme name into the palette applied to the subtree.

import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct WildwoodThemeTests {
    @Test func namedResolvesTheSharedThemeNames() {
        #expect(WildwoodTheme.named("cool-blue") == .coolBlue)
        #expect(WildwoodTheme.named("fall-colors") == .fallColors)
        #expect(WildwoodTheme.named(WildwoodThemeNames.woodlandWarm) == .woodlandWarm)
    }

    @Test func namedFallsBackToWoodlandWarmForAnUnknownName() {
        // An unrecognized stored theme must not leave the subtree unthemed.
        #expect(WildwoodTheme.named("nope") == .woodlandWarm)
    }
}
