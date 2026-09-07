import Foundation
import Security
import CommonCrypto

// MARK: - Keychain helpers (sideload-safe: no entitlement dependency)

enum KeychainUtils {
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Try with access group first (works for sideload with matching entitlements)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess { return true }

        // Fallback: no access group (works across re-signing tools)
        let fallback: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(fallback as CFDictionary)
        return SecItemAdd(fallback as CFDictionary, nil) == errSecSuccess
    }

    static func read(key: String) -> String? {
        // Try primary query
        if let value = readInternal(key: key, accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly) {
            return value
        }
        // Fallback: after re-signing, accessibility may differ
        return readInternal(key: key, accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    }

    private static func readInternal(key: String, accessible: CFString) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessible as String: accessible
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - HMAC helpers

enum HMACUtils {
    static func sha256Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { buf in
            CC_SHA256(buf.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func compute(key: String, message: String) -> String {
        guard let keyData = key.data(using: .utf8),
              let msgData = message.data(using: .utf8) else { return "" }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        keyData.withUnsafeBytes { keyBuf in
            msgData.withUnsafeBytes { msgBuf in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       keyBuf.baseAddress, keyData.count,
                       msgBuf.baseAddress, msgData.count,
                       &digest)
            }
        }
        return Data(digest).base64EncodedString()
    }
}

// MARK: - Certificate Pinning (Disabled)

class CertPinningDelegate: NSObject, URLSessionDelegate {
    static let shared = CertPinningDelegate()

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }
}

// Legacy API (backward compat)
var expectedServerPin: String { "" }
