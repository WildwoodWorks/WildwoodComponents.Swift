// Pure wording for the passkey list, kept out of the iOS-gated view so it is testable (the same
// split as React Native's passkeyManagementView.ts, whose output it matches).

import Foundation
import WildwoodCore

public enum PasskeyManagementRules {
    /// "Added 11/1/2026 · last used 11/3/2026" / "… · never used". Dates the device cannot parse
    /// are dropped rather than printed.
    public static func metaLine(
        _ passkey: UserPasskey,
        format: (Date) -> String = { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .none) }
    ) -> String {
        let added = parse(passkey.createdAt).map(format) ?? ""
        let used = parse(passkey.lastUsedAt).map(format)
        return "Added \(added)" + (used.map { " · last used \($0)" } ?? " · never used")
    }

    /// ISO-8601 with or without fractional seconds, as the API sends either.
    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return date }
        // .NET serializes a DateTime with no offset ("2026-11-01T00:00:00[.fffffff]"); the API's
        // clock is UTC.
        let unzoned = DateFormatter()
        unzoned.locale = Locale(identifier: "en_US_POSIX")
        unzoned.timeZone = TimeZone(identifier: "UTC")
        for pattern in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            unzoned.dateFormat = pattern
            if let date = unzoned.date(from: value) { return date }
        }
        return nil
    }
}
