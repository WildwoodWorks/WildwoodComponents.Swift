// Storage abstraction mirroring @wildwood/core's StorageAdapter.
// Adapters are synchronous (Keychain/UserDefaults are synchronous on Apple platforms).

import Foundation
import Security
import Synchronization

public protocol WildwoodStorageAdapter: Sendable {
    func getItem(_ key: String) -> String?
    func setItem(_ key: String, _ value: String)
    func removeItem(_ key: String)
}

/// Storage selection for `WildwoodConfig`, mirroring the JS `storage` option.
public enum WildwoodStorageOption: Sendable {
    /// Tokens and user data in the Keychain, everything else in UserDefaults (default).
    case composite
    case keychain
    case userDefaults
    /// In-memory only — used by tests and ephemeral sessions.
    case memory
    case custom(any WildwoodStorageAdapter)

    func makeAdapter() -> any WildwoodStorageAdapter {
        switch self {
        case .composite: return CompositeStorage()
        case .keychain: return KeychainStorage()
        case .userDefaults: return UserDefaultsStorage()
        case .memory: return MemoryStorage()
        case .custom(let adapter): return adapter
        }
    }
}

public final class MemoryStorage: WildwoodStorageAdapter {
    private let store = Mutex<[String: String]>([:])

    public init() {}

    public func getItem(_ key: String) -> String? {
        store.withLock { $0[key] }
    }

    public func setItem(_ key: String, _ value: String) {
        store.withLock { $0[key] = value }
    }

    public func removeItem(_ key: String) {
        store.withLock { $0[key] = nil }
    }
}

// UserDefaults is documented thread-safe.
public final class UserDefaultsStorage: WildwoodStorageAdapter, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func getItem(_ key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func setItem(_ key: String, _ value: String) {
        defaults.set(value, forKey: key)
    }

    public func removeItem(_ key: String) {
        defaults.removeObject(forKey: key)
    }
}

public final class KeychainStorage: WildwoodStorageAdapter {
    private let service: String

    public init(service: String = "io.wildwoodworks.components") {
        self.service = service
    }

    public func getItem(_ key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setItem(_ key: String, _ value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query = baseQuery(for: key)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    public func removeItem(_ key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

/// Default storage: secrets (tokens, stored user/session auth JSON) go to the Keychain;
/// non-sensitive keys (theme, drafts, session expiry) go to UserDefaults.
public final class CompositeStorage: WildwoodStorageAdapter {
    private let keychain: KeychainStorage
    private let defaults: UserDefaultsStorage

    private static let keychainKeys: Set<String> = [
        WildwoodStorageKeys.accessToken,
        WildwoodStorageKeys.refreshToken,
        WildwoodStorageKeys.user,
        WildwoodStorageKeys.sessionAuth,
    ]

    public init(keychain: KeychainStorage = KeychainStorage(), defaults: UserDefaultsStorage = UserDefaultsStorage()) {
        self.keychain = keychain
        self.defaults = defaults
    }

    private func backend(for key: String) -> any WildwoodStorageAdapter {
        Self.keychainKeys.contains(key) ? keychain : defaults
    }

    public func getItem(_ key: String) -> String? {
        backend(for: key).getItem(key)
    }

    public func setItem(_ key: String, _ value: String) {
        backend(for: key).setItem(key, value)
    }

    public func removeItem(_ key: String) {
        backend(for: key).removeItem(key)
    }
}
