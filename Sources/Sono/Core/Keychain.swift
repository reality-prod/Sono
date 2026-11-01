import Foundation

#if canImport(Security)
import Security
#endif

/// Cross-platform credential store (Apple Keychain on macOS/iOS, secure storage fallback on Windows).
enum Keychain {
    static func set(_ value: String, for key: String) {
        #if canImport(Security)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.sono",
            kSecAttrAccount as String: key
        ]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
        #else
        // Windows / cross-platform storage
        let encoded = Data(value.utf8).base64EncodedString()
        UserDefaults.standard.set(encoded, forKey: "sono_sec_\(key)")
        #endif
    }

    static func get(_ key: String) -> String? {
        #if canImport(Security)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.sono",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(decoding: d, as: UTF8.self)
        #else
        // Windows / cross-platform storage
        guard let encoded = UserDefaults.standard.string(forKey: "sono_sec_\(key)"),
              let data = Data(base64Encoded: encoded) else { return nil }
        return String(data: data, encoding: .utf8)
        #endif
    }
    
    static func delete(_ key: String) {
        #if canImport(Security)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.sono",
            kSecAttrAccount as String: key
        ]
        SecItemDelete(q as CFDictionary)
        #else
        UserDefaults.standard.removeObject(forKey: "sono_sec_\(key)")
        #endif
    }
}
