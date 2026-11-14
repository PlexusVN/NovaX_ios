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

/// Normalize only a damaged saved Secure Enclave key, at the key-use boundary.
/// A storage, authentication, entitlement or temporary token failure must keep
/// its original error and cannot authorize an identity replacement.
enum StoredSecureEnclaveKeyPolicy {
    static func perform<T>(_ operation: () throws -> T) throws -> T {
        do { return try operation() }
        catch {
            if isCorruptedKey(error) { throw DeviceIdentityError.invalidIdentity }
            throw error
        }
    }

    static func isCorruptedKey(_ error: Error) -> Bool {
        var current = error as NSError
        // Security can wrap the token's parsing error in errSecParam/errSecDecode.
        // Do not walk through unknown, locked, authentication or canceled errors.
        for _ in 0..<6 {
            if current.domain == "CryptoTokenKit" { return current.code == -3 }
            guard current.domain == NSOSStatusErrorDomain,
                  current.code == -50 || current.code == -26275,
                  let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
            current = underlying
        }
        return false
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
    private var storedSecureEnclaveKeyCorrupted = false

    let licenseBinding: String?
    private let recoveryGeneration: String?
    private let storage: DeviceIdentityStorage
    private let useSecureEnclave: Bool
    private static let identityTags = ["novax_device_install_id", "novax_device_key_id",
        "novax_software_p256_key", "novax_se_p256_key", "novax_signing_backend_v2",
        "novax_agreement_software_p256_v2", "novax_agreement_se_p256_v2", "novax_agreement_backend_v2"]

    private convenience init() { self.init(namespace: nil) }
    init(namespace: String?, storage: DeviceIdentityStorage = .keychain, useSecureEnclave: Bool = true) {
        self.licenseBinding = namespace; self.recoveryGeneration = nil
        self.storage = storage; self.useSecureEnclave = useSecureEnclave
    }
    private init(binding: String, recoveryGeneration: String, storage: DeviceIdentityStorage,
                 useSecureEnclave: Bool) {
        self.licenseBinding = binding; self.recoveryGeneration = recoveryGeneration
        self.storage = storage; self.useSecureEnclave = useSecureEnclave
    }
    static func canonicalLicense(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
    static func binding(forLicense value: String) -> String {
        SHA256.hash(data: Data(canonicalLicense(value).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func scoped(to binding: String, storage: DeviceIdentityStorage = .keychain,
                       useSecureEnclave: Bool = true) throws -> DeviceIdentityService {
        guard binding.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else { throw DeviceIdentityError.invalidInput }
        let base = DeviceIdentityService(namespace: binding, storage: storage, useSecureEnclave: useSecureEnclave)
        guard let generation = try base.readGeneration("active_generation_v1") else { return base }
        let selected = base.recoveryIdentity(generation)
        _ = try selected.validatedRecoveryRecord()
        guard try selected.persistedEnrollmentID() != nil else { throw DeviceIdentityError.invalidIdentity }
        return selected
    }
    /// Recovery control must remain readable when the selected generation has
    /// lost a private key. This handle never loads, creates or replaces keys.
    static func recoveryController(for binding: String, storage: DeviceIdentityStorage = .keychain,
                                   useSecureEnclave: Bool = true) throws -> DeviceIdentityService {
        guard binding.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            throw DeviceIdentityError.invalidInput
        }
        return DeviceIdentityService(namespace: binding, storage: storage, useSecureEnclave: useSecureEnclave)
    }
    func recoveryController() throws -> DeviceIdentityService {
        guard let licenseBinding else { throw DeviceIdentityError.invalidInput }
        return try Self.recoveryController(for: licenseBinding, storage: storage, useSecureEnclave: useSecureEnclave)
    }
    /// Read the selected generation's scope without parsing its private keys.
    func recoveryExpectedServerKeyID() throws -> Int? {
        if let generation = try readGeneration("active_generation_v1"),
           let keyID = try recoveryIdentity(generation).persistedServerKeyID() { return keyID }
        return try persistedServerKeyID()
    }
    /// Partial Keychain loss is an existing identity, not first enrollment.
    /// Check before getOrCreateKey so missing material cannot be regenerated
    /// in the old namespace without administrator-authorized recovery.
    func hasRememberedIdentity() throws -> Bool {
        for base in Self.identityTags + ["server_license_key_id"] {
            if try readData(tag: storageTag(base)) != nil { return true }
        }
        return false
    }
    /// Only first enrollment can finish interrupted key creation. The marker
    /// proves a verified challenge found this namespace pristine before any
    /// key write. Submission is recorded BEFORE enrollment can reach the server.
    private struct InitialEnrollmentRecord: Codable {
        let installationID: String
        let licenseBinding: String
        let submitted: Bool
    }
    private func initialEnrollmentRecord() throws -> InitialEnrollmentRecord? {
        guard let data = try readData(tag: storageTag("initial_enrollment_v1")) else { return nil }
        guard data.count <= 1024, let record = try? JSONDecoder().decode(InitialEnrollmentRecord.self, from: data),
              recoveryGeneration == nil, record.licenseBinding == licenseBinding,
              UUID(uuidString: record.installationID)?.uuidString.lowercased() == record.installationID else {
            throw DeviceIdentityError.invalidIdentity
        }
        return record
    }
    func initialEnrollmentInstallationID() throws -> String? {
        try initialEnrollmentRecord()?.installationID
    }
    func prepareInitialEnrollment(installationID: String) throws -> Bool {
        try locked {
            if let pending = try initialEnrollmentRecord() {
                guard !pending.submitted else { return false }
                guard pending.installationID == installationID,
                      try persistedEnrollmentID() == nil, try persistedServerKeyID() == nil else {
                    throw DeviceIdentityError.invalidIdentity
                }
                return true
            }
            guard try hasRememberedIdentity() == false else { return false }
            guard recoveryGeneration == nil, let licenseBinding,
                  UUID(uuidString: installationID)?.uuidString.lowercased() == installationID else {
                throw DeviceIdentityError.invalidInput
            }
            let record = InitialEnrollmentRecord(installationID: installationID, licenseBinding: licenseBinding, submitted: false)
            try saveData(JSONEncoder().encode(record), tag: storageTag("initial_enrollment_v1"))
            return true
        }
    }
    func finishInitialEnrollmentPreparation(installationID: String) throws {
        try locked {
            guard let pending = try initialEnrollmentRecord(), !pending.submitted else { return }
            guard pending.installationID == installationID else { throw DeviceIdentityError.invalidIdentity }
            _ = try existingResumeMaterial()
            // A failed write aborts the request; after submission, key loss can
            // never be mistaken for an interrupted, unsubmitted first install.
            let submitted = InitialEnrollmentRecord(installationID: installationID,
                licenseBinding: pending.licenseBinding, submitted: true)
            try saveData(JSONEncoder().encode(submitted), tag: storageTag("initial_enrollment_v1"))
        }
    }
    private func storageTag(_ base: String) -> String {
        guard let licenseBinding else { return base }
        let prefix = "astra.identity.v3.\(licenseBinding)"
        return recoveryGeneration.map { "\(prefix).generation.\($0).\(base)" } ?? "\(prefix).\(base)"
    }

    private struct RecoveryRecord: Codable, Equatable {
        let version: Int
        let generation: String
        let licenseBinding: String
        let keyID: Int
        let hwidHash: String
        let signingFingerprint: String
        let agreementFingerprint: String
    }
    private func recoveryControlTag(_ suffix: String) throws -> String {
        guard let licenseBinding,
              licenseBinding.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            throw DeviceIdentityError.invalidInput
        }
        return "astra.identity.v3.\(licenseBinding).\(suffix)"
    }
    private func readGeneration(_ suffix: String) throws -> String? {
        guard let text = try readText(recoveryControlTag(suffix)) else { return nil }
        guard UUID(uuidString: text)?.uuidString.lowercased() == text else {
            throw DeviceIdentityError.invalidIdentity
        }
        return text
    }
    private func recoveryIdentity(_ generation: String) -> DeviceIdentityService {
        DeviceIdentityService(binding: licenseBinding!, recoveryGeneration: generation,
                              storage: storage, useSecureEnclave: useSecureEnclave)
    }
    private static func recoveryHWIDHash(_ hwid: String) throws -> String {
        let value = hwid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty, value.utf8.count <= 255,
              !value.contains("\r"), !value.contains("\n"), !value.contains("\0") else {
            throw DeviceIdentityError.invalidInput
        }
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func publicFingerprint(_ base64: String) throws -> String {
        guard let bytes = Data(base64Encoded: base64), bytes.count == 65, bytes.first == 4 else {
            throw DeviceIdentityError.invalidIdentity
        }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    private static func storedSoftwareSigningKey(_ data: Data) throws -> P256.Signing.PrivateKey {
        // Storage errors have already propagated. Only parsing the saved raw
        // scalar is normalized; Secure Enclave availability errors stay intact.
        do { return try P256.Signing.PrivateKey(rawRepresentation: data) }
        catch { throw DeviceIdentityError.invalidIdentity }
    }
    private static func storedSoftwareAgreementKey(_ data: Data) throws -> P256.KeyAgreement.PrivateKey {
        do { return try P256.KeyAgreement.PrivateKey(rawRepresentation: data) }
        catch { throw DeviceIdentityError.invalidIdentity }
    }
    private static func storedSecureEnclaveSigningKey(_ data: Data) throws -> SecureEnclave.P256.Signing.PrivateKey {
        try StoredSecureEnclaveKeyPolicy.perform {
            try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)
        }
    }
    private static func storedSecureEnclaveAgreementKey(_ data: Data) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        try StoredSecureEnclaveKeyPolicy.perform {
            try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: data)
        }
    }
    /// This path never creates keys or backend markers. A published recovery
    /// candidate with lost/corrupt material must not silently rotate its keys.
    private func existingRecoveryPublicKeys() throws -> (signing: String, agreement: String) {
        guard recoveryGeneration != nil else { throw DeviceIdentityError.invalidIdentity }
        let signingBackend = try readText(signingBackendTag)
        let agreementBackend = try readText(agreementBackendTag)
        let signingSE = try readData(tag: seKeyTag), signingSoftware = try readData(tag: softwareKeyTag)
        let agreementSE = try readData(tag: agreementSETag), agreementSoftware = try readData(tag: agreementSoftwareTag)
        let signing: String
        switch signingBackend {
        case AssuranceLevel.secureEnclave.rawValue:
            guard let signingSE, signingSoftware == nil else { throw DeviceIdentityError.invalidIdentity }
            signing = try Self.storedSecureEnclaveSigningKey(signingSE)
                .publicKey.x963Representation.base64EncodedString()
        case AssuranceLevel.softwareKeychain.rawValue:
            guard let signingSoftware, signingSE == nil else { throw DeviceIdentityError.invalidIdentity }
            signing = try Self.storedSoftwareSigningKey(signingSoftware)
                .publicKey.x963Representation.base64EncodedString()
        default: throw DeviceIdentityError.identityMissing
        }
        let agreement: String
        switch agreementBackend {
        case AssuranceLevel.secureEnclave.rawValue:
            guard let agreementSE, agreementSoftware == nil else { throw DeviceIdentityError.invalidIdentity }
            agreement = try Self.storedSecureEnclaveAgreementKey(agreementSE)
                .publicKey.x963Representation.base64EncodedString()
        case AssuranceLevel.softwareKeychain.rawValue:
            guard let agreementSoftware, agreementSE == nil else { throw DeviceIdentityError.invalidIdentity }
            agreement = try Self.storedSoftwareAgreementKey(agreementSoftware)
                .publicKey.x963Representation.base64EncodedString()
        default: throw DeviceIdentityError.identityMissing
        }
        guard signing != agreement else { throw DeviceIdentityError.invalidIdentity }
        return (signing, agreement)
    }
    private func validatedRecoveryRecord() throws -> RecoveryRecord {
        guard let generation = recoveryGeneration, let licenseBinding,
              let data = try readData(tag: storageTag("recovery_record_v1")), data.count <= 2048,
              let shape = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(shape.keys) == Set(["version", "generation", "licenseBinding", "keyID", "hwidHash",
                                      "signingFingerprint", "agreementFingerprint"]),
              let record = try? JSONDecoder().decode(RecoveryRecord.self, from: data),
              record.version == 1, record.generation == generation,
              record.licenseBinding == licenseBinding, record.keyID > 0,
              UUID(uuidString: generation)?.uuidString.lowercased() == generation,
              [record.hwidHash, record.signingFingerprint, record.agreementFingerprint].allSatisfy({
                  $0.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
              }), record.signingFingerprint != record.agreementFingerprint,
              try existingInstallationID() == generation,
              try persistedServerKeyID() == record.keyID else { throw DeviceIdentityError.invalidIdentity }
        let keys = try existingRecoveryPublicKeys()
        guard try Self.publicFingerprint(keys.signing) == record.signingFingerprint,
              try Self.publicFingerprint(keys.agreement) == record.agreementFingerprint else {
            throw DeviceIdentityError.invalidIdentity
        }
        return record
    }
    /// Read-only. A marker is published only after an authorized challenge has
    /// prepared durable material. It permits exact-key enrollment retry after
    /// a committed enrollment consumes its ticket but its HTTP response is lost.
    func pendingRecoveryCandidate(hwid: String) throws -> DeviceIdentityService? {
        try locked {
            guard let generation = try readGeneration("pending_recovery_v1") else { return nil }
            if try readGeneration("active_generation_v1") == generation { return nil }
            let candidate = recoveryIdentity(generation)
            let record = try candidate.validatedRecoveryRecord()
            guard record.hwidHash == (try Self.recoveryHWIDHash(hwid)) else {
                throw DeviceIdentityError.invalidIdentity
            }
            return candidate
        }
    }
    /// Call only after verifying a fresh signed recovery_authorized=true
    /// challenge for this exact license, HWID, server key ID and installation.
    /// No enrolled data or old private key is deleted or overwritten.
    func prepareRecoveryCandidate(installationID: String, keyID: Int,
                                  hwid: String, replacingUnreadablePending: Bool = false) throws -> DeviceIdentityService {
        try locked {
            guard keyID > 0, let licenseBinding,
                  UUID(uuidString: installationID)?.uuidString.lowercased() == installationID,
                  installationID != (try readGeneration("active_generation_v1")),
                  installationID != (try existingInstallationID()) else {
                throw DeviceIdentityError.invalidInput
            }
            let hwidHash = try Self.recoveryHWIDHash(hwid)
            if let existingKeyID = try recoveryExpectedServerKeyID(), existingKeyID != keyID {
                throw DeviceIdentityError.invalidIdentity
            }
            do {
                if let pending = try pendingRecoveryCandidate(hwid: hwid) {
                    guard try pending.existingInstallationID() == installationID,
                          try pending.persistedServerKeyID() == keyID else { throw DeviceIdentityError.ambiguousIdentity }
                    return pending
                }
            } catch {
                // Caller must first verify a NEW administrator ticket. Only an
                // unreadable candidate may be superseded; all archived data and
                // the old pointer survive until the replacement is durable.
                switch error {
                case DeviceIdentityError.identityMissing, DeviceIdentityError.invalidIdentity:
                    guard replacingUnreadablePending else { throw error }
                default: throw error
                }
            }
            let candidate = recoveryIdentity(installationID)
            try candidate.persistInstallationID(installationID)
            try candidate.persistServerKeyID(keyID)
            let signing = try candidate.getOrCreateKey().publicKeyX963Base64
            let agreement = try candidate.getOrCreateAgreementKey().publicKeyX963Base64
            let record = RecoveryRecord(version: 1, generation: installationID, licenseBinding: licenseBinding,
                keyID: keyID, hwidHash: hwidHash, signingFingerprint: try Self.publicFingerprint(signing),
                agreementFingerprint: try Self.publicFingerprint(agreement))
            try candidate.saveData(JSONEncoder().encode(record), tag: candidate.storageTag("recovery_record_v1"))
            _ = try candidate.validatedRecoveryRecord()
            // Publish LAST: no server enrollment may be sent before this returns.
            try saveData(Data(installationID.utf8), tag: recoveryControlTag("pending_recovery_v1"))
            return candidate
        }
    }
    /// Call only after a signed enrollment response proves this candidate's
    /// device ID, revision and recipient fingerprint under the unchanged auth context.
    /// Publishing the active generation is one atomic Keychain item update.
    @discardableResult
    func promoteRecoveryCandidate(_ candidate: DeviceIdentityService, deviceKeyID: String,
                                  keyID: Int, hwid: String) throws -> DeviceIdentityService {
        try locked {
            guard candidate.licenseBinding == licenseBinding, let generation = candidate.recoveryGeneration,
                  UUID(uuidString: deviceKeyID) != nil,
                  try readGeneration("pending_recovery_v1") == generation else {
                throw DeviceIdentityError.invalidIdentity
            }
            let durable = recoveryIdentity(generation)
            let record = try durable.validatedRecoveryRecord()
            guard record == (try candidate.validatedRecoveryRecord()), record.keyID == keyID,
                  record.hwidHash == (try Self.recoveryHWIDHash(hwid)) else { throw DeviceIdentityError.invalidIdentity }
            try durable.persistEnrollment(deviceKeyId: deviceKeyID)
            _ = try durable.validatedRecoveryRecord()
            try saveData(Data(generation.utf8), tag: recoveryControlTag("active_generation_v1"))
            // Cleanup is optional after the commit. A stale completed pending
            // marker is ignored by pendingRecoveryCandidate, even after a crash.
            try? removeData(tag: recoveryControlTag("pending_recovery_v1"))
            return durable
        }
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

    /// Possession check for resuming an existing installation. This path cannot
    /// create a missing private key, even when enrollment metadata was lost.
    func existingResumeMaterial() throws -> (signing: String, agreement: String, assurance: AssuranceLevel) {
        try locked {
            guard try readData(tag: seKeyTag) != nil || readData(tag: softwareKeyTag) != nil,
                  try readData(tag: agreementSETag) != nil || readData(tag: agreementSoftwareTag) != nil else {
                throw DeviceIdentityError.identityMissing
            }
            let signing = try getOrCreateKey()
            let agreement = try getOrCreateAgreementKey()
            return (signing.publicKeyX963Base64, agreement.publicKeyX963Base64, signing.assurance)
        }
    }

    /// Unlike first enrollment, resume can prove the original keys without a
    /// locally remembered installation UUID. It signs a fresh server challenge;
    /// no metadata is changed until the signed resume response is validated.
    func signResumeEnrollment(challengeID: String, challenge: String, key: String,
                              hwid: String, installationID: String) throws -> String {
        let material = try existingResumeMaterial()
        guard UUID(uuidString: installationID) != nil else { throw DeviceIdentityError.invalidInput }
        let fields = ["ASTRA-ENROLL-V2-RECIPIENT", challengeID, challenge,
                      key.trimmingCharacters(in: .whitespacesAndNewlines),
                      hwid.trimmingCharacters(in: .whitespacesAndNewlines), installationID.lowercased(),
                      material.signing, material.assurance.rawValue, material.agreement]
        try validateCanonicalFields(fields)
        return try signData(Data(fields.joined(separator: "\n").utf8))
    }

    /// Call only after verifying nonce/purpose/signature and the exact license,
    /// server key ID and BOTH public-key fingerprints in a resume response.
    /// This repairs metadata only. Private keys and recovery generations survive.
    func acceptResumedEnrollment(deviceKeyID: String, installationID: String, keyID: Int,
                                 signingFingerprint: String, agreementFingerprint: String) throws {
        try locked {
            guard UUID(uuidString: deviceKeyID) != nil, UUID(uuidString: installationID) != nil,
                  keyID > 0 else { throw DeviceIdentityError.invalidInput }
            let material = try existingResumeMaterial()
            guard try Self.publicFingerprint(material.signing) == signingFingerprint,
                  try Self.publicFingerprint(material.agreement) == agreementFingerprint,
                  recoveryGeneration == nil || recoveryGeneration == installationID.lowercased() else {
                throw DeviceIdentityError.invalidIdentity
            }
            try persistServerKeyID(keyID)
            // Publish the device reference last. Interrupted metadata writes can
            // repeat this same-key handshake; no old private material is erased.
            try saveData(Data(installationID.lowercased().utf8), tag: installIdKey)
            try saveData(Data(deviceKeyID.lowercased().utf8), tag: deviceKeyIdKey)
        }
    }

    /// Metadata from the pinned-TLS enrollment endpoint, after matching license
    /// scope and BOTH key fingerprints. Keeps private keys/generations intact.
    /// A restored database may assign a new numeric license/device reference;
    /// the active server entitlement and the same private keys remain decisive.
    func acceptCanonicalEnrollment(deviceKeyID: String, installationID: String, keyID: Int,
                                   signingFingerprint: String, agreementFingerprint: String) throws {
        try locked {
            guard licenseBinding != nil, UUID(uuidString: deviceKeyID) != nil,
                  UUID(uuidString: installationID) != nil, keyID > 0 else { throw DeviceIdentityError.invalidInput }
            let material = try existingResumeMaterial()
            guard try Self.publicFingerprint(material.signing) == signingFingerprint,
                  try Self.publicFingerprint(material.agreement) == agreementFingerprint,
                  recoveryGeneration == nil || recoveryGeneration == installationID.lowercased() else {
                throw DeviceIdentityError.invalidIdentity
            }
            try saveData(Data(String(keyID).utf8), tag: storageTag("server_license_key_id"))
            try saveData(Data(installationID.lowercased().utf8), tag: installIdKey)
            try saveData(Data(deviceKeyID.lowercased().utf8), tag: deviceKeyIdKey)
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
            case .enclave(let key):
                return try withStoredSecureEnclaveKey { try key.sharedSecretFromKeyAgreement(with: peer) }
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
            case .enclave(let key):
                return try withStoredSecureEnclaveKey { try key.signature(for: data).rawRepresentation.base64EncodedString() }
            case .software(let key): return try key.signature(for: data).rawRepresentation.base64EncodedString()
            }
        }
    }

    /// An imported key's public point can remain readable after its private
    /// token fails. Keep the definitive failure in this instance so the next
    /// explicit operation cannot open another session with that unusable key.
    /// The archive is untouched; replacement still requires server recovery.
    func withStoredSecureEnclaveKey<T>(_ operation: () throws -> T) throws -> T {
        try locked {
            guard !storedSecureEnclaveKeyCorrupted else { throw DeviceIdentityError.invalidIdentity }
            do { return try StoredSecureEnclaveKeyPolicy.perform(operation) }
            catch DeviceIdentityError.invalidIdentity {
                storedSecureEnclaveKeyCorrupted = true
                throw DeviceIdentityError.invalidIdentity
            }
        }
    }

    private func loadSigningKey() throws -> SigningKey {
        guard !storedSecureEnclaveKeyCorrupted else { throw DeviceIdentityError.invalidIdentity }
        if let cached = signingKey { return cached }
        let backend = try readText(signingBackendTag)
        let seData = try readData(tag: seKeyTag)
        let softData = try readData(tag: softwareKeyTag)
        let result: SigningKey
        if let backend {
            switch backend {
            case AssuranceLevel.secureEnclave.rawValue:
                guard let seData else { throw DeviceIdentityError.identityMissing }
                result = .enclave(try Self.storedSecureEnclaveSigningKey(seData))
            case AssuranceLevel.softwareKeychain.rawValue:
                guard let softData else { throw DeviceIdentityError.identityMissing }
                result = .software(try Self.storedSoftwareSigningKey(softData))
            default: throw DeviceIdentityError.invalidIdentity
            }
        } else if seData != nil && softData != nil {
            throw DeviceIdentityError.ambiguousIdentity
        } else if let seData {
            result = .enclave(try Self.storedSecureEnclaveSigningKey(seData))
            try saveData(Data(AssuranceLevel.secureEnclave.rawValue.utf8), tag: signingBackendTag)
        } else if let softData {
            result = .software(try Self.storedSoftwareSigningKey(softData))
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
        guard !storedSecureEnclaveKeyCorrupted else { throw DeviceIdentityError.invalidIdentity }
        if let cached = agreementKey { return cached }
        let backend = try readText(agreementBackendTag)
        let seData = try readData(tag: agreementSETag)
        let softData = try readData(tag: agreementSoftwareTag)
        let result: AgreementKey
        if let backend {
            switch backend {
            case AssuranceLevel.secureEnclave.rawValue:
                guard let seData else { throw DeviceIdentityError.identityMissing }
                result = .enclave(try Self.storedSecureEnclaveAgreementKey(seData))
            case AssuranceLevel.softwareKeychain.rawValue:
                guard let softData else { throw DeviceIdentityError.identityMissing }
                result = .software(try Self.storedSoftwareAgreementKey(softData))
            default: throw DeviceIdentityError.invalidIdentity
            }
        } else if seData != nil && softData != nil {
            throw DeviceIdentityError.ambiguousIdentity
        } else if let seData {
            result = .enclave(try Self.storedSecureEnclaveAgreementKey(seData))
            try saveData(Data(AssuranceLevel.secureEnclave.rawValue.utf8), tag: agreementBackendTag)
        } else if let softData {
            result = .software(try Self.storedSoftwareAgreementKey(softData))
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
