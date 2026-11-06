// macOS CLI test of staged device-credential recovery. No production Keychain,
// credentials, network or device-pairing implementation is accessed.
import Foundation
import CryptoKit
import Security

private enum RecoveryCheckError: Error { case failed(String), injectedFailure }
private final class RecoveryMemoryStore {
    var values: [String: Data] = [:]
    var writes = 0
    var failTag: String?
    var failRemove = false
    lazy var storage = DeviceIdentityStorage(read: { [unowned self] in values[$0] },
        write: { [unowned self] tag, data in
            if tag == failTag { throw RecoveryCheckError.injectedFailure }
            writes += 1; values[tag] = data
        }, remove: { [unowned self] tag in
            if failRemove { throw RecoveryCheckError.injectedFailure }
            values.removeValue(forKey: tag)
        })
    func identity(_ binding: String) -> DeviceIdentityService {
        DeviceIdentityService(namespace: binding, storage: storage, useSecureEnclave: false)
    }
    func selected(_ binding: String) throws -> DeviceIdentityService {
        try DeviceIdentityService.scoped(to: binding, storage: storage, useSecureEnclave: false)
    }
}

@main
struct DeviceRecoverySelfCheck {
    static var checks = 0
    static func require(_ condition: Bool, _ name: String) throws {
        guard condition else { throw RecoveryCheckError.failed(name) }
        checks += 1
    }
    static func rejects(_ name: String, _ operation: () throws -> Void) throws {
        do { try operation() } catch { checks += 1; return }
        throw RecoveryCheckError.failed("accepted: " + name)
    }
    static func main() throws {
        let binding = DeviceIdentityService.binding(forLicense: "RECOVERY-SELF-CHECK-A")
        let otherBinding = DeviceIdentityService.binding(forLicense: "RECOVERY-SELF-CHECK-B")
        let hwid = "10000000-0000-4000-8000-000000000001"
        let otherHWID = "10000000-0000-4000-8000-000000000002"
        let prefix = "astra.identity.v3.\(binding)."
        let activeTag = prefix + "active_generation_v1"
        let pendingTag = prefix + "pending_recovery_v1"
        let store = RecoveryMemoryStore()
        let old = store.identity(binding)
        let oldSigning = try old.getOrCreateKey().publicKeyX963Base64
        let oldAgreement = try old.getOrCreateAgreementKey().publicKeyX963Base64
        let oldInstall = try old.installationID()
        let oldDevice = UUID().uuidString.lowercased()
        try old.persistEnrollment(deviceKeyId: oldDevice)
        try old.persistServerKeyID(7)
        let original = store.values
        let originalWrites = store.writes
        try require(try old.pendingRecoveryCandidate(hwid: hwid) == nil, "no pending recovery")
        try require(try store.selected(binding).persistedEnrollmentID() == oldDevice, "default namespace unchanged")
        try require(store.writes == originalWrites && store.values == original, "readonly lookup never writes")
        try rejects("reuse old installation is rejected") {
            _ = try old.prepareRecoveryCandidate(installationID: oldInstall, keyID: 7, hwid: hwid)
        }
        try rejects("different server license ID is rejected before any write") {
            _ = try old.prepareRecoveryCandidate(installationID: UUID().uuidString.lowercased(), keyID: 8, hwid: hwid)
        }
        try require(store.values == original, "invalid recovery context preserves every old item")

        let generation = UUID().uuidString.lowercased()
        let candidate = try old.prepareRecoveryCandidate(installationID: generation, keyID: 7, hwid: hwid)
        let newSigning = try candidate.getOrCreateKey().publicKeyX963Base64
        let newAgreement = try candidate.getOrCreateAgreementKey().publicKeyX963Base64
        try require(newSigning != oldSigning && newAgreement != oldAgreement, "fresh signing and recipient keys")
        try require(newSigning != newAgreement, "distinct key purposes")
        try require(try candidate.existingInstallationID() == generation, "fresh durable installation UUID")
        try require(try candidate.persistedEnrollmentID() == nil, "stage never invents enrolled device ID")
        try require(try store.selected(binding).persistedEnrollmentID() == oldDevice, "stage does not switch active identity")
        try require(original.allSatisfy { store.values[$0.key] == $0.value }, "stage preserves old key material")
        let savedCandidate = store.values
        let writesAfterPreparation = store.writes
        let resumed = try store.identity(binding).pendingRecoveryCandidate(hwid: hwid)!
        try require(try resumed.getOrCreateKey().publicKeyX963Base64 == newSigning, "lost enrollment response reuses signing key")
        try require(try resumed.getOrCreateAgreementKey().publicKeyX963Base64 == newAgreement, "lost response reuses recipient key")
        try require(try resumed.existingInstallationID() == generation, "lost response reuses install UUID")
        try require(store.writes == writesAfterPreparation, "resume and material checks are readonly")
        try rejects("wrong HWID cannot resume pending identity") { _ = try old.pendingRecoveryCandidate(hwid: otherHWID) }
        try rejects("pending candidate cannot be replaced") {
            _ = try old.prepareRecoveryCandidate(installationID: UUID().uuidString.lowercased(), keyID: 7, hwid: hwid)
        }
        try require(store.values == savedCandidate, "failed resume leaves stage intact")

        let newDevice = UUID().uuidString.lowercased()
        store.failTag = activeTag
        try rejects("failed atomic pointer publish") {
            _ = try old.promoteRecoveryCandidate(resumed, deviceKeyID: newDevice, keyID: 7, hwid: hwid)
        }
        try require(try store.selected(binding).persistedEnrollmentID() == oldDevice, "failed publish retains active old device")
        let retry = try old.pendingRecoveryCandidate(hwid: hwid)!
        try require(try retry.persistedEnrollmentID() == newDevice, "committed enrollment ID survives failed pointer write")
        store.failTag = nil
        store.failRemove = true
        let promoted = try old.promoteRecoveryCandidate(retry, deviceKeyID: newDevice, keyID: 7, hwid: hwid)
        try require(try promoted.persistedEnrollmentID() == newDevice, "promotion selects signed device ID")
        try require(try store.selected(binding).getOrCreateKey().publicKeyX963Base64 == newSigning, "new launch selects committed signing key")
        try require(try store.selected(binding).getOrCreateAgreementKey().publicKeyX963Base64 == newAgreement, "new launch selects committed recipient key")
        try require(try old.pendingRecoveryCandidate(hwid: hwid) == nil, "completed stale pending marker ignored after interrupted cleanup")
        try require(original.allSatisfy { store.values[$0.key] == $0.value }, "promotion retains original archive")
        try require(try store.selected(otherBinding).persistedEnrollmentID() == nil, "promotion never affects another license")
        store.failRemove = false

        let committed = store.values
        for badPointer in ["../other", "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA", "not-a-uuid"] {
            store.values[activeTag] = Data(badPointer.utf8)
            let before = store.values
            try rejects("malformed active pointer") { _ = try store.selected(binding) }
            try require(store.values == before, "malformed pointer cannot write or silently fall back")
        }
        store.values = committed
        let generationPrefix = prefix + "generation.\(generation)."
        for suffix in ["novax_software_p256_key", "novax_agreement_software_p256_v2", "recovery_record_v1"] {
            store.values.removeValue(forKey: generationPrefix + suffix)
            let before = store.values
            try rejects("missing published key/record") { _ = try store.selected(binding) }
            try require(store.values == before, "missing material never causes key creation")
            store.values = committed
        }
        store.values[generationPrefix + "novax_agreement_software_p256_v2"] = P256.KeyAgreement.PrivateKey().rawRepresentation
        let tampered = store.values
        try rejects("candidate material fingerprint differs from published record") { _ = try store.selected(binding) }
        try require(store.values == tampered, "fingerprint rejection is readonly")
        store.values = committed

        // A failed preparation before publishing pending cannot lead to an
        // enrollment request. The initial active identity remains authoritative.
        let interrupted = RecoveryMemoryStore()
        let first = interrupted.identity(binding)
        _ = try first.getOrCreateKey(); _ = try first.getOrCreateAgreementKey()
        _ = try first.installationID(); try first.persistServerKeyID(7)
        try first.persistEnrollment(deviceKeyId: oldDevice)
        let beforeInterrupted = interrupted.values
        let stagedID = UUID().uuidString.lowercased()
        interrupted.failTag = pendingTag
        try rejects("interrupted preparation cannot publish incomplete stage") {
            _ = try first.prepareRecoveryCandidate(installationID: stagedID, keyID: 7, hwid: hwid)
        }
        try require(try first.pendingRecoveryCandidate(hwid: hwid) == nil, "failed preparation has no resumable marker")
        try require(try interrupted.selected(binding).persistedEnrollmentID() == oldDevice, "interrupted preparation retains active device")
        try require(beforeInterrupted.allSatisfy { interrupted.values[$0.key] == $0.value }, "interrupted preparation preserves old keys")
        interrupted.failTag = nil
        let ready = try first.prepareRecoveryCandidate(installationID: stagedID, keyID: 7, hwid: hwid)
        try require(try ready.existingInstallationID() == stagedID, "authorized same candidate preparation can retry")
        try rejects("wrong license cannot promote prepared candidate") {
            _ = try interrupted.identity(otherBinding).promoteRecoveryCandidate(ready, deviceKeyID: newDevice, keyID: 7, hwid: hwid)
        }
        try rejects("wrong server key ID cannot promote") {
            _ = try first.promoteRecoveryCandidate(ready, deviceKeyID: newDevice, keyID: 8, hwid: hwid)
        }
        try rejects("wrong HWID cannot promote") {
            _ = try first.promoteRecoveryCandidate(ready, deviceKeyID: newDevice, keyID: 7, hwid: otherHWID)
        }
        try require(try interrupted.selected(binding).persistedEnrollmentID() == oldDevice, "rejected promotion never switches identity")
        print("Device recovery self-check: \(checks) checks passed")
    }
}
