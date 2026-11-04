import Foundation
import Security
import CryptoKit

enum DeviceIdentityError: LocalizedError {
    case keychain(OSStatus)
    case invalidIdentity
    case identityMissing
    case ambiguousIdentity
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .keychain: return "Không thể truy cập định danh bảo mật. Hãy mở khóa thiết bị rồi thử lại."
        case .identityMissing, .ambiguousIdentity, .invalidIdentity:
            return "Định danh thiết bị không còn hợp lệ. Cần khôi phục quyền thiết bị trước khi tiếp tục."
        case .invalidInput: return "Dữ liệu định danh không hợp lệ."
        }
    }
}

struct DeviceIdentityStorage {
    let read: (String) throws -> Data?
    let write: (String, Data) throws -> Void
    let remove: (String) throws -> Void
    static let keychain = DeviceIdentityStorage(read: { tag in
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag, kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw DeviceIdentityError.keychain(status) }
        guard let data = item as? Data else { throw DeviceIdentityError.invalidIdentity }
        return data
    }, write: { tag, data in
        let identity: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: tag]
        let values: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let update = SecItemUpdate(identity as CFDictionary, values as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw DeviceIdentityError.keychain(update) }
        var insert = identity
        values.forEach { insert[$0.key] = $0.value }
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw DeviceIdentityError.keychain(status) }
    }, remove: { tag in
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: tag]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DeviceIdentityError.keychain(status) }
    })
}

/// Signing and decryption use distinct P-256 identities. Existing identities are
/// never silently replaced after a Keychain error, reinstall or re-sign.
public final class DeviceIdentityService {
    public static let shared = DeviceIdentityService()

    public enum AssuranceLevel: String {
        case secureEnclave = "secure_enclave"
        case softwareKeychain = "software_keychain"
    }

    private enum SigningKey {
        case enclave(SecureEnclave.P256.Signing.PrivateKey)
        case software(P256.Signing.PrivateKey)
    }
    private enum AgreementKey {
        case enclave(SecureEnclave.P256.KeyAgreement.PrivateKey)
        case software(P256.KeyAgreement.PrivateKey)
    }

    private let lock = NSRecursiveLock()
    private var installIdKey: String { storageTag("novax_device_install_id") }
    private var deviceKeyIdKey: String { storageTag("novax_device_key_id") }
    private var softwareKeyTag: String { storageTag("novax_software_p256_key") }
    private var seKeyTag: String { storageTag("novax_se_p256_key") }
    private var signingBackendTag: String { storageTag("novax_signing_backend_v2") }
    private var agreementSoftwareTag: String { storageTag("novax_agreement_software_p256_v2") }
    private var agreementSETag: String { storageTag("novax_agreement_se_p256_v2") }
    private var agreementBackendTag: String { storageTag("novax_agreement_backend_v2") }
    private var signingKey: SigningKey?
    private var agreementKey: AgreementKey?

    let licenseBinding: String?
    private let storage: DeviceIdentityStorage
    private let useSecureEnclave: Bool
    private static let identityTags = ["novax_device_install_id", "novax_device_key_id",
        "novax_software_p256_key", "novax_se_p256_key", "novax_signing_backend_v2",
        "novax_agreement_software_p256_v2", "novax_agreement_se_p256_v2", "novax_agreement_backend_v2"]

    private convenience init() { self.init(namespace: nil) }
    init(namespace: String?, storage: DeviceIdentityStorage = .keychain, useSecureEnclave: Bool = true) {
        self.licenseBinding = namespace; self.storage = storage; self.useSecureEnclave = useSecureEnclave
    }
    static func canonicalLicense(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
    static func binding(forLicense value: String) -> String {
        SHA256.hash(data: Data(canonicalLicense(value).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func scoped(to binding: String) throws -> DeviceIdentityService {
        guard binding.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else { throw DeviceIdentityError.invalidInput }
        return DeviceIdentityService(namespace: binding)
    }
    private func storageTag(_ base: String) -> String {
        licenseBinding.map { "astra.identity.v3.\($0).\(base)" } ?? base
    }
    /// Only a verified signed device-context response may choose this binding.
    /// Preserve the legacy archive and refuse to overwrite any conflicting key.
    func migrateLegacy(to binding: String, expectedDeviceID: String, keyID: Int) throws {
        try locked {
            guard licenseBinding == nil, keyID > 0,
                  binding.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
                  try persistedEnrollmentID() == expectedDeviceID.lowercased() else { throw DeviceIdentityError.invalidIdentity }
            _ = try loadSigningKey()
            let destination = DeviceIdentityService(namespace: binding, storage: storage, useSecureEnclave: useSecureEnclave)
            let values = try Self.identityTags.compactMap { base -> (String, Data)? in
                guard let value = try readData(tag: base) else { return nil }
                let target = destination.storageTag(base)
                if let existing = try storage.read(target), existing != value { throw DeviceIdentityError.ambiguousIdentity }
                return (target, value)
            }
            // Publish the enrollment ID last. An interrupted copy is retried
            // from the intact archive instead of exposing an incomplete identity.
            let targetDeviceID = destination.storageTag("novax_device_key_id")
            for (target, value) in values where target != targetDeviceID { try storage.write(target, value) }
            try destination.persistServerKeyID(keyID)
            if let value = values.first(where: { $0.0 == targetDeviceID })?.1 {
                try storage.write(targetDeviceID, value)
            }
        }
    }
    func persistServerKeyID(_ keyID: Int) throws {
        guard keyID > 0 else { throw DeviceIdentityError.invalidInput }
        let tag = storageTag("server_license_key_id")
        if let existing = try readText(tag), existing != String(keyID) { throw DeviceIdentityError.invalidIdentity }
        try saveData(Data(String(keyID).utf8), tag: tag)
    }
    func persistedServerKeyID() throws -> Int? {
        guard let text = try readText(storageTag("server_license_key_id")) else { return nil }
        guard let keyID = Int(text), keyID > 0 else { throw DeviceIdentityError.invalidIdentity }
        return keyID
    }

    /// Called only after a signature-verified server revocation or explicit
    /// admin recovery authorization. Never touches pairing, license or another
    /// license's identity, and never exports private key material to files.
    func resetAuthorizedInstallation() throws {
        try locked {
            guard licenseBinding != nil else { throw DeviceIdentityError.invalidIdentity }
            try saveData(Data("pending".utf8), tag: storageTag("authorized_recovery_pending"))
            // Remove the published enrollment marker first: a crash during
            // cleanup must not expose a partially removed enrolled identity.
            try removeData(tag: deviceKeyIdKey)
            for base in Self.identityTags where base != "novax_device_key_id" {
                try removeData(tag: storageTag(base))
            }
            try removeData(tag: storageTag("server_license_key_id"))
            signingKey = nil
            agreementKey = nil
            try removeData(tag: storageTag("authorized_recovery_pending"))
        }
    }

    var hasPendingAuthorizedRecovery: Bool {
        get throws { try readData(tag: storageTag("authorized_recovery_pending")) != nil }
    }

    /// Compatibility accessor; security-sensitive callers use installationID().
    public var installId: String { (try? installationID()) ?? "" }

    /// A rejected or interrupted challenge must not materialize a namespace.
    func existingInstallationID() throws -> String? {
        try locked {
            guard let existing = try readText(installIdKey) else { return nil }
            guard UUID(uuidString: existing) != nil else { throw DeviceIdentityError.invalidIdentity }
            return existing.lowercased()
        }
    }

    func persistInstallationID(_ candidate: String) throws {
        try locked {
            guard UUID(uuidString: candidate) != nil else { throw DeviceIdentityError.invalidInput }
            if let existing = try existingInstallationID() {
                guard existing == candidate.lowercased() else { throw DeviceIdentityError.invalidIdentity }
                return
            }
            guard try persistedEnrollmentID() == nil else { throw DeviceIdentityError.identityMissing }
            try saveData(Data(candidate.lowercased().utf8), tag: installIdKey)
        }
    }

    public func installationID() throws -> String {
        try locked {
            if let existing = try existingInstallationID() { return existing }
            // An enrolled installation cannot adopt a new installation identity.
            guard try readText(deviceKeyIdKey) == nil else { throw DeviceIdentityError.identityMissing }
            let value = UUID().uuidString.lowercased()
            try persistInstallationID(value)
            return value
        }
    }

    /// Compatibility metadata; new enrollments must call persistEnrollment() so
    /// persistence errors cannot be mistaken for a usable enrolled device.
    public var enrolledDeviceKeyId: String? {
        get { try? readText(deviceKeyIdKey) }
        set {
            if let value = newValue { try? persistEnrollment(deviceKeyId: value) }
            else { try? removeData(tag: deviceKeyIdKey) }
        }
    }

    public func persistedEnrollmentID() throws -> String? {
        guard let value = try readText(deviceKeyIdKey) else { return nil }
        guard UUID(uuidString: value) != nil else { throw DeviceIdentityError.invalidIdentity }
        return value.lowercased()
    }

    public func persistEnrollment(deviceKeyId: String) throws {
        try locked {
            guard UUID(uuidString: deviceKeyId) != nil else { throw DeviceIdentityError.invalidInput }
            if let existing = try persistedEnrollmentID(), existing != deviceKeyId.lowercased() {
                throw DeviceIdentityError.invalidIdentity
            }
            _ = try getOrCreateKey()
            _ = try getOrCreateAgreementKey()
            try saveData(Data(deviceKeyId.lowercased().utf8), tag: deviceKeyIdKey)
        }
    }

    public var assuranceLevel: AssuranceLevel {
        (try? getOrCreateKey().assurance) ?? .softwareKeychain
    }

    public func getOrCreateKey() throws -> (publicKeyX963Base64: String, assurance: AssuranceLevel) {
        try locked {
            switch try loadSigningKey() {
            case .enclave(let key): return (key.publicKey.x963Representation.base64EncodedString(), .secureEnclave)
            case .software(let key): return (key.publicKey.x963Representation.base64EncodedString(), .softwareKeychain)
            }
        }
    }

    public func getOrCreateAgreementKey() throws -> (publicKeyX963Base64: String, assurance: AssuranceLevel) {
        try locked {
            switch try loadAgreementKey() {
            case .enclave(let key): return (key.publicKey.x963Representation.base64EncodedString(), .secureEnclave)
            case .software(let key): return (key.publicKey.x963Representation.base64EncodedString(), .softwareKeychain)
            }
        }
    }

    /// Explicit revision-1 migration only. The caller first verifies the server's
    /// signed recipient_upgrade_required response, obtains a session using the
    /// existing signing key, then proves that session when enrolling this key.
    /// This path never replaces an existing, corrupt or unreadable agreement key.
    public func prepareLegacyRecipientUpgrade() throws -> (publicKeyX963Base64: String, assurance: AssuranceLevel) {
        try locked {
            guard try persistedEnrollmentID() != nil else { throw DeviceIdentityError.identityMissing }
            _ = try loadSigningKey()
            switch try loadAgreementKey(allowCreatingForLegacyUpgrade: true) {
            case .enclave(let key): return (key.publicKey.x963Representation.base64EncodedString(), .secureEnclave)
            case .software(let key): return (key.publicKey.x963Representation.base64EncodedString(), .softwareKeychain)
            }
        }
    }

    public func agreementSharedSecret(peerPublicKeyX963: Data) throws -> SharedSecret {
        try locked {
            guard peerPublicKeyX963.count == 65, peerPublicKeyX963.first == 4 else {
                throw DeviceIdentityError.invalidInput
            }
            let peer = try P256.KeyAgreement.PublicKey(x963Representation: peerPublicKeyX963)
            switch try loadAgreementKey() {
            case .enclave(let key): return try key.sharedSecretFromKeyAgreement(with: peer)
            case .software(let key): return try key.sharedSecretFromKeyAgreement(with: peer)
            }
        }
    }

    public func signEnrollment(challengeId: String, challenge: String, key: String,
                               hwid: String, installId: String, publicKeyX963: String,
                               assurance: AssuranceLevel,
                               agreementPublicKeyX963: String? = nil) throws -> String {
        let identity = try getOrCreateKey()
        guard publicKeyX963 == identity.publicKeyX963Base64, assurance == identity.assurance,
              try installationID() == installId.lowercased() else { throw DeviceIdentityError.invalidIdentity }
        var fields = [agreementPublicKeyX963 == nil ? "ASTRA-ENROLL-V2" : "ASTRA-ENROLL-V2-RECIPIENT",
                      challengeId, challenge, key.trimmingCharacters(in: .whitespacesAndNewlines),
                      hwid.trimmingCharacters(in: .whitespacesAndNewlines), installId.lowercased(),
                      publicKeyX963, assurance.rawValue]
        if let agreement = agreementPublicKeyX963 {
            guard agreement == (try getOrCreateAgreementKey()).publicKeyX963Base64 else {
                throw DeviceIdentityError.invalidIdentity
            }
            fields.append(agreement)
        }
        try validateCanonicalFields(fields)
        return try signData(Data(fields.joined(separator: "\n").utf8))
    }

    public func signRequest(method: String, path: String, bodySha256: String,
                            sessionId: String, deviceKeyId: String, nonce: String,
                            timestamp: Int64, counter: Int64) throws -> String {
        guard try persistedEnrollmentID() == deviceKeyId.lowercased() else {
            throw DeviceIdentityError.invalidIdentity
        }
        let fields = ["ASTRA-REQ-V2", method.uppercased(), path, bodySha256,
                      sessionId, deviceKeyId, nonce, String(timestamp), String(counter)]
        if sessionId.isEmpty {
            guard method.uppercased() == "POST",
                  ["/api/v2/novax/login", "/api/v2/novax/session/open", "/api/v2/device/context"].contains(path) else {
                throw DeviceIdentityError.invalidInput
            }
            try validateCanonicalFields(fields.enumerated().filter { $0.offset != 4 }.map { $0.element })
        } else {
            try validateCanonicalFields(fields)
        }
        return try signData(Data(fields.joined(separator: "\n").utf8))
    }

    private func signData(_ data: Data) throws -> String {
        try locked {
            switch try loadSigningKey() {
            case .enclave(let key): return try key.signature(for: data).rawRepresentation.base64EncodedString()
            case .software(let key): return try key.signature(for: data).rawRepresentation.base64EncodedString()
            }
        }
    }

    private func loadSigningKey() throws -> SigningKey {
        if let cached = signingKey { return cached }
        let backend = try readText(signingBackendTag)
        let seData = try readData(tag: seKeyTag)
        let softData = try readData(tag: softwareKeyTag)
        let result: SigningKey
        if let backend {
            switch backend {
            case AssuranceLevel.secureEnclave.rawValue:
                guard let seData else { throw DeviceIdentityError.identityMissing }
                result = .enclave(try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: seData))
            case AssuranceLevel.softwareKeychain.rawValue:
                guard let softData else { throw DeviceIdentityError.identityMissing }
                result = .software(try P256.Signing.PrivateKey(rawRepresentation: softData))
            default: throw DeviceIdentityError.invalidIdentity
            }
        } else if seData != nil && softData != nil {
            throw DeviceIdentityError.ambiguousIdentity
        } else if let seData {
            result = .enclave(try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: seData))
            try saveData(Data(AssuranceLevel.secureEnclave.rawValue.utf8), tag: signingBackendTag)
        } else if let softData {
            result = .software(try P256.Signing.PrivateKey(rawRepresentation: softData))
            try saveData(Data(AssuranceLevel.softwareKeychain.rawValue.utf8), tag: signingBackendTag)
        } else {
            guard try readText(deviceKeyIdKey) == nil else { throw DeviceIdentityError.identityMissing }
            let createdSE: SecureEnclave.P256.Signing.PrivateKey?
            if useSecureEnclave && SecureEnclave.isAvailable {
                createdSE = try? SecureEnclave.P256.Signing.PrivateKey(accessControl: makeAccessControl())
            } else { createdSE = nil }
            if let key = createdSE {
                try saveData(key.dataRepresentation, tag: seKeyTag)
                try saveData(Data(AssuranceLevel.secureEnclave.rawValue.utf8), tag: signingBackendTag)
                result = .enclave(key)
            } else {
                let key = P256.Signing.PrivateKey()
                try saveData(key.rawRepresentation, tag: softwareKeyTag)
                try saveData(Data(AssuranceLevel.softwareKeychain.rawValue.utf8), tag: signingBackendTag)
                result = .software(key)
            }
        }
        signingKey = result
        return result
    }

    private func loadAgreementKey(allowCreatingForLegacyUpgrade: Bool = false) throws -> AgreementKey {
        if let cached = agreementKey { return cached }
        let backend = try readText(agreementBackendTag)
        let seData = try readData(tag: agreementSETag)
        let softData = try readData(tag: agreementSoftwareTag)
        let result: AgreementKey
        if let backend {
            switch backend {
            case AssuranceLevel.secureEnclave.rawValue:
                guard let seData else { throw DeviceIdentityError.identityMissing }
                result = .enclave(try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: seData))
            case AssuranceLevel.softwareKeychain.rawValue:
                guard let softData else { throw DeviceIdentityError.identityMissing }
                result = .software(try P256.KeyAgreement.PrivateKey(rawRepresentation: softData))
            default: throw DeviceIdentityError.invalidIdentity
            }
        } else if seData != nil && softData != nil {
            throw DeviceIdentityError.ambiguousIdentity
        } else if let seData {
            result = .enclave(try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: seData))
            try saveData(Data(AssuranceLevel.secureEnclave.rawValue.utf8), tag: agreementBackendTag)
        } else if let softData {
            result = .software(try P256.KeyAgreement.PrivateKey(rawRepresentation: softData))
            try saveData(Data(AssuranceLevel.softwareKeychain.rawValue.utf8), tag: agreementBackendTag)
        } else {
            guard try readText(deviceKeyIdKey) == nil || allowCreatingForLegacyUpgrade else {
                throw DeviceIdentityError.identityMissing
            }
            let createdSE: SecureEnclave.P256.KeyAgreement.PrivateKey?
            if useSecureEnclave && SecureEnclave.isAvailable {
                createdSE = try? SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: makeAccessControl())
            } else { createdSE = nil }
            if let key = createdSE {
                try saveData(key.dataRepresentation, tag: agreementSETag)
                try saveData(Data(AssuranceLevel.secureEnclave.rawValue.utf8), tag: agreementBackendTag)
                result = .enclave(key)
            } else {
                let key = P256.KeyAgreement.PrivateKey()
                try saveData(key.rawRepresentation, tag: agreementSoftwareTag)
                try saveData(Data(AssuranceLevel.softwareKeychain.rawValue.utf8), tag: agreementBackendTag)
                result = .software(key)
            }
        }
        agreementKey = result
        return result
    }

    private func makeAccessControl() throws -> SecAccessControl {
        guard let access = SecAccessControlCreateWithFlags(nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage], nil) else {
            throw DeviceIdentityError.invalidIdentity
        }
        return access
    }

    private func validateCanonicalFields(_ fields: [String]) throws {
        guard fields.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 2048 &&
            !$0.contains("\n") && !$0.contains("\r") && !$0.contains("\0") }) else {
            throw DeviceIdentityError.invalidInput
        }
    }

    private func locked<T>(_ action: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try action()
    }

    private func readText(_ tag: String) throws -> String? {
        guard let data = try readData(tag: tag) else { return nil }
        guard let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            throw DeviceIdentityError.invalidIdentity
        }
        return value
    }

    private func readData(tag: String) throws -> Data? { try storage.read(tag) }
    private func saveData(_ data: Data, tag: String) throws { try storage.write(tag, data) }
    private func removeData(tag: String) throws { try storage.remove(tag) }
}
