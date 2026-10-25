import Foundation
import Security
import CryptoKit

/// Dịch vụ quản lý khóa định danh thiết bị (P-256 ECC) tương thích ESign / KSign.
/// Ưu tiên lưu trong Secure Enclave với fallback phần mềm được bảo vệ bởi Keychain.
public final class DeviceIdentityService {
    public static let shared = DeviceIdentityService()

    private let installIdKey = "novax_device_install_id"
    private let deviceKeyIdKey = "novax_device_key_id"
    private let softwareKeyTag = "novax_software_p256_key"
    private let seKeyTag = "novax_se_p256_key"

    public enum AssuranceLevel: String {
        case secureEnclave = "secure_enclave"
        case softwareKeychain = "software_keychain"
    }

    private var cachedSeKey: SecureEnclave.P256.Signing.PrivateKey?
    private var cachedSoftwareKey: P256.Signing.PrivateKey?

    private init() {}

    /// UUID định danh installation duy nhất, được lưu bền vững trong Keychain.
    public var installId: String {
        if let existing = KeychainUtils.read(key: installIdKey), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString.lowercased()
        _ = KeychainUtils.save(key: installIdKey, value: fresh)
        return fresh
    }

    /// Server Device Key ID được cấp sau khi enroll thành công.
    public var enrolledDeviceKeyId: String? {
        get { KeychainUtils.read(key: deviceKeyIdKey) }
        set {
            if let val = newValue {
                _ = KeychainUtils.save(key: deviceKeyIdKey, value: val)
            } else {
                KeychainUtils.delete(key: deviceKeyIdKey)
            }
        }
    }

    /// Xác định mức độ tin cậy của phần cứng có sẵn.
    public var assuranceLevel: AssuranceLevel {
        if SecureEnclave.isAvailable {
            return .secureEnclave
        }
        return .softwareKeychain
    }

    /// Lấy hoặc tạo khóa P-256 (ưu tiên Secure Enclave, fallback Keychain).
    public func getOrCreateKey() throws -> (publicKeyX963Base64: String, assurance: AssuranceLevel) {
        if SecureEnclave.isAvailable {
            do {
                let seKey = try loadOrCreateSecureEnclaveKey()
                self.cachedSeKey = seKey
                let pubRaw = seKey.publicKey.x963Representation
                return (pubRaw.base64EncodedString(), .secureEnclave)
            } catch {
                // Fallback nếu Secure Enclave bị từ chối do entitlement khi re-sign
            }
        }

        let softKey = try loadOrCreateSoftwareKey()
        self.cachedSoftwareKey = softKey
        let pubRaw = softKey.publicKey.x963Representation
        return (pubRaw.base64EncodedString(), .softwareKeychain)
    }

    /// Ký thông điệp đăng ký thiết bị (Enrollment challenge).
    public func signEnrollment(
        challengeId: String,
        challenge: String,
        key: String,
        hwid: String,
        installId: String,
        publicKeyX963: String,
        assurance: AssuranceLevel
    ) throws -> String {
        let canonical = [
            "ASTRA-ENROLL-V2",
            challengeId,
            challenge,
            key.trimmingCharacters(in: .whitespacesAndNewlines),
            hwid.trimmingCharacters(in: .whitespacesAndNewlines),
            installId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            publicKeyX963,
            assurance.rawValue
        ].joinWithNewline()

        return try signData(canonical.data(using: .utf8) ?? Data())
    }

    /// Ký thông điệp request canonical v2.
    public func signRequest(
        method: String,
        path: String,
        bodySha256: String,
        sessionId: String,
        deviceKeyId: String,
        nonce: String,
        timestamp: Int64,
        counter: Int64
    ) throws -> String {
        let canonical = [
            "ASTRA-REQ-V2",
            method.uppercased(),
            path,
            bodySha256,
            sessionId,
            deviceKeyId,
            nonce,
            String(timestamp),
            String(counter)
        ].joinWithNewline()

        return try signData(canonical.data(using: .utf8) ?? Data())
    }

    // MARK: - Private Key Management

    private func signData(_ data: Data) throws -> String {
        if let seKey = cachedSeKey ?? (try? loadOrCreateSecureEnclaveKey()) {
            let signature = try seKey.signature(for: data)
            return signature.rawRepresentation.base64EncodedString()
        }
        let softKey = try (cachedSoftwareKey ?? loadOrCreateSoftwareKey())
        let signature = try softKey.signature(for: data)
        return signature.rawRepresentation.base64EncodedString()
    }

    private func loadOrCreateSecureEnclaveKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        if let cached = cachedSeKey { return cached }

        if let dataRepresentation = readRawKeychainData(tag: seKeyTag) {
            if let existing = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: dataRepresentation) {
                return existing
            }
        }

        // Tạo khóa Secure Enclave với accessible khi mở khóa thiết bị
        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            nil
        )

        let newKey: SecureEnclave.P256.Signing.PrivateKey
        if let access = access {
            newKey = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        } else {
            newKey = try SecureEnclave.P256.Signing.PrivateKey()
        }

        _ = saveRawKeychainData(tag: seKeyTag, data: newKey.dataRepresentation)
        return newKey
    }

    private func loadOrCreateSoftwareKey() throws -> P256.Signing.PrivateKey {
        if let cached = cachedSoftwareKey { return cached }

        if let data = readRawKeychainData(tag: softwareKeyTag) {
            if let existing = try? P256.Signing.PrivateKey(rawRepresentation: data) {
                return existing
            }
        }

        let newKey = P256.Signing.PrivateKey()
        _ = saveRawKeychainData(tag: softwareKeyTag, data: newKey.rawRepresentation)
        return newKey
    }

    private func saveRawKeychainData(tag: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func readRawKeychainData(tag: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }
}

private extension Array where Element == String {
    func joinWithNewline() -> String {
        return self.joined(separator: "\n")
    }
}
