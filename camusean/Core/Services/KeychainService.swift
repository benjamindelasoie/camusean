import Foundation
import Security

enum KeychainService {
    private static let service = "com.camusean.app"
    private static let apiKeyAccount = "anthropic-api-key"

    static func saveAPIKey(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Seeds the Keychain from a bundled `Secrets.plist` on first launch, if present.
    ///
    /// Used for TestFlight builds so non-technical testers skip the API-key wall:
    /// a capped, revocable key is baked into the build via the (gitignored) `Secrets.plist`
    /// resource and copied into the Keychain once — after which it behaves exactly as if the
    /// user had pasted it in Settings (editable, revocable, persists across launches).
    ///
    /// No-op when a key already exists, the file is absent, or the value is still the
    /// placeholder — in those cases the app falls back to the normal manual-entry flow.
    static func seedAPIKeyIfNeeded() {
        if let existing = loadAPIKey(), !existing.isEmpty { return }
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let dict = NSDictionary(contentsOf: url),
            let key = dict["AnthropicAPIKey"] as? String,
            key.hasPrefix("sk-ant-")
        else { return }
        try? saveAPIKey(key)
    }

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status): "Keychain save failed: \(status)"
        }
    }
}
