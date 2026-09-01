import Foundation
import Security

/// Helper to securely store and retrieve sensitive credentials like the Gemini API Key in macOS Keychain.
public final class KeychainHelper: Sendable {
    public static let shared = KeychainHelper()
    private let primaryService = "com.jigglypuff.app"
    private let fallbackServices = ["com.jigglypuff.app", "com.jiggypuff.app", "com.transrib.app"]
    private let apiKeyAccount = "GeminiAPIKey"

    private init() {}

    /// Saves API Key securely in Keychain.
    @discardableResult
    public func saveAPIKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        // Delete existing items across services first
        deleteAPIKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: primaryService,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Reads API Key from Keychain, falling back to environment variable if present.
    public func getAPIKey() -> String? {
        // First check environment variable GEMINI_API_KEY
        if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !envKey.isEmpty {
            return envKey
        }

        // Try primary and fallback services
        for svc in fallbackServices {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: svc,
                kSecAttrAccount as String: apiKeyAccount,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)

            if status == errSecSuccess,
               let data = item as? Data,
               let key = String(data: data, encoding: .utf8),
               !key.isEmpty {
                return key
            }
        }

        return nil
    }

    /// Deletes API Key from Keychain across known services.
    @discardableResult
    public func deleteAPIKey() -> Bool {
        var allSucceeded = true
        for svc in fallbackServices {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: svc,
                kSecAttrAccount as String: apiKeyAccount
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                allSucceeded = false
            }
        }
        return allSucceeded
    }
}
