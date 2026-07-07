// Codable representation of arbitrary JSON, used where the wire format carries
// open-ended objects (payment metadata, provider data, confirmation data).

import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Compact JSON text with sorted keys — the Swift analog of
    /// System.Text.Json's JsonElement.GetRawText() (key order is normalized
    /// rather than preserved).
    public var rawJSONString: String? {
        Self.encode(self, formatting: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// Pretty-printed JSON text (sorted keys) for display surfaces.
    public var prettyJSONString: String? {
        Self.encode(self, formatting: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    private static func encode(_ value: JSONValue, formatting: JSONEncoder.OutputFormatting) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = formatting
        guard let data = try? encoder.encode(value) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
