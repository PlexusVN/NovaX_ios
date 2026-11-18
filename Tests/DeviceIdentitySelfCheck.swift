// macOS CLI test of the production identity implementation. Storage is injected;
// no login Keychain items, production keys or network endpoints are accessed.
import Foundation
import CryptoKit
import Security

private enum CheckError: Error { case failed(String); case injectedWriteFailure }
private final class MemoryIdentityStore {
    var values: [String: Data] = [:]
    var failingTag: String?
    lazy var storage = DeviceIdentityStorage(read: { [unowned self] in values[$0] },
        write: { [unowned self] tag, data in
            if tag == failingTag { throw CheckError.injectedWriteFailure }
            values[tag] = data
        }, remove: { [unowned self] in values.removeValue(forKey: $0) })
    func identity(_ binding: String?) -> DeviceIdentityService {
        DeviceIdentityService(namespace: binding, storage: storage, useSecureEnclave: false)
    }
}

@main
struct DeviceIdentitySelfCheck {
    static var checks = 0
    static func require(_ value: Bool, _ name: String) throws {
        guard value else { throw CheckError.failed(name) }
        checks += 1
    }
    static func rejects(_ name: String, _ action: () throws -> Void) throws {
        do { try action() } catch { checks += 1; return }
        throw CheckError.failed("accepted: " + name)
    }
    static func main() throws {
        let a = DeviceIdentityService.binding(forLicense: " KEY-A ")
        let b = DeviceIdentityService.binding(forLicense: "KEY-B")
        try require(a == DeviceIdentityService.binding(forLicense: "key-a"), "canonical license binding")
        try require(a != b, "different licenses have distinct bindings")
        let memory = MemoryIdentityStore()
        let pendingID = UUID().uuidString.lowercased()
        let noChallengeIdentity = memory.identity(a)
        try require(try noChallengeIdentity.existingInstallationID() == nil, "readonly pending installation is absent")
        try require(memory.values.isEmpty, "rejected challenge creates no persistent namespace")
        try noChallengeIdentity.persistInstallationID(pendingID)
        try require(try memory.identity(a).existingInstallationID() == pendingID, "authorized challenge persists chosen installation")
        try rejects("installation cannot be silently replaced") {
            try noChallengeIdentity.persistInstallationID(UUID().uuidString.lowercased())
        }
        let identityA = memory.identity(a)
        let signingA = try identityA.getOrCreateKey().publicKeyX963Base64
        let agreementA = try identityA.getOrCreateAgreementKey().publicKeyX963Base64
        let installationA = try identityA.installationID()
        let idA = UUID().uuidString.lowercased()
        try identityA.persistEnrollment(deviceKeyId: idA)
        try identityA.persistServerKeyID(7)
        let identityB = memory.identity(b)
        try require(try identityB.persistedEnrollmentID() == nil, "B never inherits A enrollment")
        try require(try identityB.getOrCreateKey().publicKeyX963Base64 != signingA, "per-license signing key")
        try require(try identityB.getOrCreateAgreementKey().publicKeyX963Base64 != agreementA, "per-license agreement key")
        try require(try identityB.installationID() != installationA, "per-license installation")
        let returningA = memory.identity(a)
        try require(try returningA.getOrCreateKey().publicKeyX963Base64 == signingA, "switch back preserves A signing key")
        try require(try returningA.getOrCreateAgreementKey().publicKeyX963Base64 == agreementA, "switch back preserves A agreement key")
        try require(try returningA.persistedEnrollmentID() == idA, "switch back preserves A enrollment")
        try rejects("different signed server key binding") { try returningA.persistServerKeyID(8) }

        let legacyMemory = MemoryIdentityStore()
        let legacy = legacyMemory.identity(nil)
        let legacySigning = try legacy.getOrCreateKey().publicKeyX963Base64
        let legacyAgreement = try legacy.getOrCreateAgreementKey().publicKeyX963Base64
        let legacyInstall = try legacy.installationID()
        let legacyID = UUID().uuidString.lowercased()
        try legacy.persistEnrollment(deviceKeyId: legacyID)
        try legacy.migrateLegacy(to: a, expectedDeviceID: legacyID, keyID: 7)
        let migrated = legacyMemory.identity(a)
        try require(try migrated.getOrCreateKey().publicKeyX963Base64 == legacySigning, "migration preserves exact signing identity")
        try require(try migrated.getOrCreateAgreementKey().publicKeyX963Base64 == legacyAgreement, "migration preserves exact recipient identity")
        try require(try migrated.installationID() == legacyInstall, "migration preserves installation")
        try require(try migrated.persistedEnrollmentID() == legacyID, "migration preserves device ID")
        try require(try legacy.persistedEnrollmentID() == legacyID, "migration preserves legacy archive")
        try require(try legacyMemory.identity(b).persistedEnrollmentID() == nil, "signed A migration cannot enroll B")
        try rejects("wrong legacy device ID") { try legacy.migrateLegacy(to: b, expectedDeviceID: UUID().uuidString, keyID: 7) }
        _ = try legacyMemory.identity(b).getOrCreateKey()
        let beforeConflict = legacyMemory.values
        try rejects("conflicting namespace") { try legacy.migrateLegacy(to: b, expectedDeviceID: legacyID, keyID: 7) }
        try require(legacyMemory.values == beforeConflict, "conflicting namespace remains unchanged")

        let interrupted = MemoryIdentityStore()
        let old = interrupted.identity(nil)
        _ = try old.getOrCreateKey(); _ = try old.getOrCreateAgreementKey(); _ = try old.installationID()
        let oldID = UUID().uuidString.lowercased()
        try old.persistEnrollment(deviceKeyId: oldID)
        interrupted.failingTag = "astra.identity.v3.\(a).novax_signing_backend_v2"
        try rejects("interrupted migration") { try old.migrateLegacy(to: a, expectedDeviceID: oldID, keyID: 7) }
        try require(try interrupted.identity(a).persistedEnrollmentID() == nil, "partial migration never publishes device ID")
        interrupted.failingTag = nil
        try old.migrateLegacy(to: a, expectedDeviceID: oldID, keyID: 7)
        try require(try interrupted.identity(a).persistedEnrollmentID() == oldID, "interrupted migration can retry")

        let pending = MemoryIdentityStore()
        let enrollmentPending = pending.identity(a)
        let pendingSigning = try enrollmentPending.getOrCreateKey().publicKeyX963Base64
        let pendingAgreement = try enrollmentPending.getOrCreateAgreementKey().publicKeyX963Base64
        let pendingInstall = try enrollmentPending.installationID()
        let retried = pending.identity(a)
        try require(try retried.getOrCreateKey().publicKeyX963Base64 == pendingSigning, "lost response reuses signing key")
        try require(try retried.getOrCreateAgreementKey().publicKeyX963Base64 == pendingAgreement, "lost response reuses recipient key")
        try require(try retried.installationID() == pendingInstall, "lost response reuses installation")
        try require(try retried.persistedEnrollmentID() == nil, "lost response does not invent enrollment ID")
        print("Device identity self-check: \(checks) checks passed")
    }
}
