import Dependencies
import Foundation
import Security

enum KeychainService {
    private nonisolated static let service = "com.camusean.app"
    private nonisolated static let apiKeyAccount = "anthropic-api-key"

    // `nonisolated` (the Security framework is thread-safe) so the `APIKeyStore` live client
    // can call these from its `@Sendable` closures.
    nonisolated static func saveAPIKey(_ key: String) throws {
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

    nonisolated static func loadAPIKey() -> String? {
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

    /// Seeds the Keychain once from a bundled (gitignored) `Secrets.plist` so TestFlight testers
    /// skip the API-key wall. No-op when a key already exists, the file is absent, or the value is
    /// still the placeholder — the app then falls back to manual entry in Settings.
    static func seedAPIKeyIfNeeded() {
        if let existing = loadAPIKey(), !existing.isEmpty {
            print("[seed] key already present — nothing to do")
            return
        }
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist") else {
            print("[seed] no Secrets.plist in the bundle — falling back to manual entry")
            return
        }
        guard let dict = NSDictionary(contentsOf: url) else {
            print("[seed] Secrets.plist present but unreadable at \(url.lastPathComponent)")
            return
        }
        guard let key = dict["AnthropicAPIKey"] as? String else {
            print("[seed] Secrets.plist has no AnthropicAPIKey string")
            return
        }
        guard key.hasPrefix("sk-ant-") else {
            print("[seed] AnthropicAPIKey is still the placeholder — not seeding")
            return
        }
        // Never `try?` this — a silent failure is indistinguishable from "no key provided".
        do {
            try saveAPIKey(key)
            print("[seed] seeded API key into the Keychain")
        } catch {
            print("[seed] FAILED to write seeded key to the Keychain: \(error)")
        }
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

// swift-dependencies seam (closure-client idiom) so the lookup flow and Settings resolve the
// key overridably — a test can supply one without the real Keychain. testValue is keyless.
// Launch seeding stays on the static `seedAPIKeyIfNeeded()`, which runs in `@main` before any
// dependency scope exists.
struct APIKeyStore: Sendable {
    var load: @Sendable () -> String?
    var save: @Sendable (String) throws -> Void
}

extension APIKeyStore: DependencyKey {
    nonisolated static let liveValue = APIKeyStore(
        load: { KeychainService.loadAPIKey() },
        save: { try KeychainService.saveAPIKey($0) }
    )
    nonisolated static let testValue = APIKeyStore(
        load: { nil },
        save: { _ in }
    )
    nonisolated static var previewValue: APIKeyStore { testValue }
}

extension DependencyValues {
    nonisolated var apiKeyStore: APIKeyStore {
        get { self[APIKeyStore.self] }
        set { self[APIKeyStore.self] = newValue }
    }
}
