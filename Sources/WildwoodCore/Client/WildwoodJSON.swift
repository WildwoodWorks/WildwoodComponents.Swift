// Shared JSON coding for the WildwoodAPI wire format.
// The backend is ASP.NET Core: camelCase responses (so the default Codable key
// strategy matches), case-insensitive request parsing, and dates that may carry
// .NET's 7-digit fractional seconds with or without a timezone suffix.

import Foundation

public enum WildwoodJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { container in
            let value = try container.singleValueContainer()
            let string = try value.decode(String.self)
            if let date = parseDate(string) {
                return date
            }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unrecognized date format: \(string)"
                )
            )
        }
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFractional.string(from: date))
        }
        return encoder
    }

    // MARK: - Date parsing

    // ISO8601DateFormatter and DateFormatter are documented thread-safe but
    // not marked Sendable; these are immutable after creation.

    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // .NET DateTime (Kind.Unspecified) serializes without a timezone suffix;
    // treat those as UTC, matching how the other stacks consume them.
    nonisolated(unsafe) private static let dotNetFractional: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"
        return f
    }()

    nonisolated(unsafe) private static let dotNetPlain: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    static func parseDate(_ string: String) -> Date? {
        isoFractional.date(from: string)
            ?? isoPlain.date(from: string)
            ?? dotNetFractional.date(from: string)
            ?? dotNetPlain.date(from: string)
    }
}
