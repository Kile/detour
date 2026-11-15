import Foundation
import Security

/// Minimal Keychain wrapper for the API key. Items are device-only (no iCloud sync, not
/// restored to other devices) and only readable while the device is unlocked.
struct KeychainStore: Sendable {
    enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
        case invalidData
    }

    let service: String

    static let apiKeys = KeychainStore(service: "dev.sidequest.apikeys")
    static let claudeAccount = "anthropic-api-key"
    static let geminiAccount = "gemini-api-key"

    func set(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.invalidData }
        var query = baseQuery(account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func get(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unexpectedStatus(status) }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Convenience for the provider API keys.
enum APIKeyStore {
    static func account(for provider: ProviderKind) -> String? {
        switch provider {
        case .claude: return KeychainStore.claudeAccount
        case .gemini: return KeychainStore.geminiAccount
        case .demo: return nil
        }
    }

    static func key(for provider: ProviderKind) -> String? {
        guard let account = account(for: provider) else { return nil }
        return try? KeychainStore.apiKeys.get(account: account)
    }

    static func saveKey(_ key: String, for provider: ProviderKind) throws {
        guard let account = account(for: provider) else { return }
        try KeychainStore.apiKeys.set(key.trimmingCharacters(in: .whitespacesAndNewlines), account: account)
    }

    static func removeKey(for provider: ProviderKind) throws {
        guard let account = account(for: provider) else { return }
        try KeychainStore.apiKeys.delete(account: account)
    }

    static func hasKey(for provider: ProviderKind) -> Bool { !(key(for: provider) ?? "").isEmpty }

    static func geminiKey() -> String? { key(for: .gemini) }

    /// Cheap local sanity check before we hit the network.
    static func looksValid(_ key: String, for provider: ProviderKind) -> Bool {
        switch provider {
        case .claude: return looksLikeClaudeKey(key)
        case .gemini:
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count >= 30 && !trimmed.contains(" ")
        case .demo: return false
        }
    }

    /// For display only: keeps the first few and last 4 characters.
    static func masked(_ key: String, provider: ProviderKind) -> String {
        provider == .claude ? masked(key) : (key.count > 10 ? String(key.prefix(4)) + "…" + key.suffix(4) : "••••")
    }

    static func claudeKey() -> String? {
        try? KeychainStore.apiKeys.get(account: KeychainStore.claudeAccount)
    }

    static func saveClaudeKey(_ key: String) throws {
        try KeychainStore.apiKeys.set(key.trimmingCharacters(in: .whitespacesAndNewlines), account: KeychainStore.claudeAccount)
    }

    static func removeClaudeKey() throws {
        try KeychainStore.apiKeys.delete(account: KeychainStore.claudeAccount)
    }

    static var hasClaudeKey: Bool { !(claudeKey() ?? "").isEmpty }

    /// Cheap local sanity check before we hit the network.
    static func looksLikeClaudeKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("sk-ant-") && trimmed.count >= 20 && !trimmed.contains(" ")
    }

    /// For display only: "sk-ant-…a1b2".
    static func masked(_ key: String) -> String {
        guard key.count > 10 else { return "••••" }
        return "sk-ant-…" + key.suffix(4)
    }
}
