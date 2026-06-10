// Theme palette for Wildwood components. Mirrors the named themes the other
// stacks expose (woodland-warm, cool-blue, fall-colors) while deferring chrome
// to the system: on iOS 27 Liquid Glass tinting applies automatically, so the
// theme only supplies accent/semantic colors.

import SwiftUI
import WildwoodCore

public struct WildwoodTheme: Sendable, Equatable {
    public var name: ThemeName
    public var accent: Color
    public var secondaryAccent: Color
    public var success: Color
    public var warning: Color
    public var danger: Color
    public var info: Color

    public init(
        name: ThemeName,
        accent: Color,
        secondaryAccent: Color,
        success: Color = .green,
        warning: Color = .orange,
        danger: Color = .red,
        info: Color = .blue
    ) {
        self.name = name
        self.accent = accent
        self.secondaryAccent = secondaryAccent
        self.success = success
        self.warning = warning
        self.danger = danger
        self.info = info
    }

    public static let woodlandWarm = WildwoodTheme(
        name: WildwoodThemeNames.woodlandWarm,
        accent: Color(red: 0.42, green: 0.30, blue: 0.16),
        secondaryAccent: Color(red: 0.55, green: 0.45, blue: 0.28)
    )

    public static let coolBlue = WildwoodTheme(
        name: WildwoodThemeNames.coolBlue,
        accent: Color(red: 0.13, green: 0.37, blue: 0.62),
        secondaryAccent: Color(red: 0.32, green: 0.55, blue: 0.78)
    )

    public static let fallColors = WildwoodTheme(
        name: WildwoodThemeNames.fallColors,
        accent: Color(red: 0.72, green: 0.34, blue: 0.10),
        secondaryAccent: Color(red: 0.85, green: 0.55, blue: 0.20)
    )

    public static func named(_ name: ThemeName) -> WildwoodTheme {
        switch name {
        case WildwoodThemeNames.coolBlue: return .coolBlue
        case WildwoodThemeNames.fallColors: return .fallColors
        default: return .woodlandWarm
        }
    }
}

public extension EnvironmentValues {
    @Entry var wildwoodTheme: WildwoodTheme = .woodlandWarm
}

public extension View {
    func wildwoodTheme(_ theme: WildwoodTheme) -> some View {
        environment(\.wildwoodTheme, theme)
            .tint(theme.accent)
    }
}
