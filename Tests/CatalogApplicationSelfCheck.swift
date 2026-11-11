import Foundation
import CryptoKit

// Device-only resolution cannot run here. All apply/restore I/O uses temp folders.
enum ContainerStore {
    static func isApplicationContainerPath(_ path: String) -> Bool { false }
    static func resolveAppContainerPath(bundleID: String, allowMetadataScan: Bool = true, retainAccess: Bool = true) -> String? { nil }
    static func resolveAppContainerForPatch(bundleID: String) throws -> String { throw CatalogCheckError.failed("device resolution must not be used") }
    static func grantContainerAccess(_ path: String) -> Int64 { 0 }
}
enum WorseQueryError: Error { case appGroupUnavailable }
enum WorseQueryHelper {
    static var isAvailable: Bool { false }
    static func acquireAccess(for path: String) throws -> Int64 { throw CatalogCheckError.failed("device grant must not be used") }
}
func sandbox_extension_release_handle(_ handle: Int64) {}
enum PatchProjectLibrary {
    static func backupRootURL() throws -> URL { throw CatalogCheckError.failed("device backup root must not be used") }
}
final class DeviceIdentityService {
    static let shared = DeviceIdentityService()
    func persistedEnrollmentID() throws -> String? { throw CatalogCheckError.failed("device identity must not be used") }
    func getOrCreateAgreementKey() throws -> (publicKeyX963Base64: String, assurance: String) { throw CatalogCheckError.failed("device identity must not be used") }
    func agreementSharedSecret(peerPublicKeyX963: Data) throws -> SharedSecret { throw CatalogCheckError.failed("device identity must not be used") }
}
enum CatalogCheckError: Error { case failed(String) }
@main
struct CatalogApplicationSelfCheck {
    static func check(_ value: @autoclosure () throws -> Bool, _ detail: String) throws {
        guard try value() else { throw CatalogCheckError.failed(detail) }
    }
    static func hex(_ text: String) -> Data {
        var bytes = Data(); var i = text.startIndex
        while i < text.endIndex { let end = text.index(i, offsetBy: 2); bytes.append(UInt8(text[i..<end], radix: 16)!); i = end }
        return bytes
    }
    static func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) }
    static func main() async throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("catalog.json"))) as! [String: Any]
        let context = fixture["context"] as! [String: Any]
        let recipient = try P256.KeyAgreement.PrivateKey(rawRepresentation: hex(fixture["recipientPrivateHex"] as! String))
        let publicKey = Data(base64Encoded: fixture["signerPublicKeyPKCS1Base64"] as! String)!
        let verifier = ServerSignatureVerifier(trustedPublicKeys: ["public-catalog-test-rsa": publicKey])
        let recipientID = context["recipientId"] as! String, sessionID = context["sessionId"] as! String, nonce = context["requestNonce"] as! String
        let decoder = ProtectedArtifactDecoder(verifier: verifier, recipientIdentity: { (recipientID, recipient.publicKey.x963Representation) },
            sharedSecret: { try recipient.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: $0)) })
        let now = Date(timeIntervalSince1970: (context["now"] as! NSNumber).doubleValue)
        let manager = FileManager.default
        let temp = manager.temporaryDirectory.appendingPathComponent("astra-catalog-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: temp) }
        let entries = fixture["fixtures"] as! [[String: Any]]
        let migrationSuite = "astra-identity-migration-" + UUID().uuidString
        let migrationDefaults = UserDefaults(suiteName: migrationSuite)!
        defer { migrationDefaults.removePersistentDomain(forName: migrationSuite) }
        let migration = CatalogPatchApplicationRegistry(defaults: migrationDefaults)
        let migrationID = UUID()
        migration.associate(migrationID, with: "old-name_ffth")
        migration.markApplied("old-name_ffth")
        migration.markRecoveryRequired("old-name_ffth")
        migration.migrateIdentity(from: "old-name_ffth", to: "catalog_7_ffth")
        try check(migration.projectID(for: "catalog_7_ffth") == migrationID, "legacy project association was lost")
        try check(migration.state(for: "catalog_7_ffth", recordedState: { _ in .applied }) == .recoveryRequired,
                  "migration lost recovery state")
        try check(migration.projectID(for: "old-name_ffth") == nil, "legacy preferences were not consumed")
        migration.clear("catalog_7_ffth")
        migration.migrateIdentity(from: "old-name_ffth", to: "catalog_7_ffth")
        try check(migration.state(for: "catalog_7_ffth", recordedState: { _ in nil }) == .off,
                  "legacy flags resurrected a restored patch")
        let currentID = UUID()
        migration.associate(migrationID, with: "legacy_ffmax")
        migration.associate(currentID, with: "catalog_7_ffmax")
        migration.migrateIdentity(from: "legacy_ffmax", to: "catalog_7_ffmax")
        try check(migration.projectID(for: "catalog_7_ffmax") == currentID, "legacy migration replaced a newer association")
        print("[PASS] stable catalog identity, recovery migration, no resurrection, no association overwrite")
        for entry in entries {
            let sourceID = (entry["sourceId"] as! NSNumber).intValue, variant = entry["variant"] as! String
            do {
                let manifest = entry["signedManifest"] as! [String: Any], grant = entry["signedGrant"] as! [String: Any]
                let artifactID = (manifest["body"] as! [String: Any])["artifactId"] as! String
                let grantID = (grant["body"] as! [String: Any])["grantId"] as! String
                let ciphertext = Data(base64Encoded: entry["ciphertextBase64"] as! String)!
                let plain = try decoder.decrypt(signedManifest: json(manifest), signedGrant: json(grant), ciphertext: ciphertext,
                    recipientID: recipientID, sessionID: sessionID, requestNonce: nonce, expectedArtifactID: artifactID, expectedGrantID: grantID, now: now)
                try check(plain == Data(contentsOf: folder.appendingPathComponent("\(sourceID).3105")), "protected plaintext differs")
                var project = try PatchPackageCodec.decode(plain, password: nil).project
                project.isPrivate = true
                try check(project.allBundleIdentifiers.allSatisfy { $0 == AppSecurityConfiguration.protectedBundleID(forVariant: variant) }, "apply bundle mismatch")
                let base = temp.appendingPathComponent(String(sourceID), isDirectory: true), container = base.appendingPathComponent("container", isDirectory: true)
                try manager.createDirectory(at: container, withIntermediateDirectories: true)
                let original = Data("public original test content".utf8)
                for rule in project.rules {
                    let target = container.appendingPathComponent(rule.relativePath)
                    try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try original.write(to: target)
                }
                let receipt = try PatchTransaction.apply(project: project, backupRoot: base.appendingPathComponent("backups"), containerResolver: { _ in container })
                let backupRoot = base.appendingPathComponent("backups")
                let suite = "astra-catalog-check-" + UUID().uuidString
                let defaults = UserDefaults(suiteName: suite)!
                defer { defaults.removePersistentDomain(forName: suite) }
                let registry = CatalogPatchApplicationRegistry(defaults: defaults)
                let catalogID = "fixture_\(sourceID)_\(variant)"
                let lookup: (UUID) -> PatchApplicationState? = { id in
                    PatchTransaction.latestRecordedApplicationState(projectID: id, backupRoot: backupRoot)
                }
                registry.associate(project.id, with: catalogID)
                // The process died after the journal was committed and before
                // its separate UI boolean was persisted: ON must be recovered.
                try check(registry.state(for: catalogID, recordedState: lookup) == .applied, "journal must recover missing ON flag")
                let relaunched = CatalogPatchApplicationRegistry(defaults: defaults)
                try check(relaunched.state(for: catalogID, recordedState: lookup) == .applied, "relaunch lost applied state")
                let oldJournal = try Data(contentsOf: receipt.journalURL)
                try check(PatchTransaction.inspectExistingApplication(receipt: receipt, project: project, containerResolver: { _ in container }) == .applied,
                    "existing identical application must be adopted")
                try check(Data(contentsOf: receipt.journalURL) == oldJournal, "adopting an application overwrote its journal")
                var differentRelease = project
                differentRelease.rules[0].replacementData.append(0)
                try check(PatchTransaction.inspectExistingApplication(receipt: receipt, project: differentRelease, containerResolver: { _ in container }) == .recoveryRequired,
                    "different release must require restore")
                for rule in project.rules { try check(Data(contentsOf: container.appendingPathComponent(rule.relativePath)) == rule.replacementData, "apply bytes differ") }
                let backupFiles = manager.enumerator(at: receipt.journalURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)!.allObjects as! [URL]
                try check(!backupFiles.contains { $0.pathExtension == "applied" }, "private plaintext cached in backup")
                let firstTarget = container.appendingPathComponent(project.rules[0].relativePath)
                try original.write(to: firstTarget)
                try check(PatchTransaction.inspectExistingApplication(receipt: receipt, project: project, containerResolver: { _ in container }) == .recoveryRequired,
                    "changed target must not be silently marked applied")
                try project.rules[0].replacementData.write(to: firstTarget)
                registry.markRecoveryRequired(catalogID)
                do {
                    try PatchTransaction.restore(receipt: receipt, containerResolver: { _ in container }, beforeWrite: { _ in throw CatalogCheckError.failed("injected restore failure") })
                    throw CatalogCheckError.failed("restore fault did not propagate")
                } catch PatchPackageError.restoreFailed {}
                try check(registry.state(for: catalogID, recordedState: lookup) == .recoveryRequired, "failed restore erased recovery state")
                try check(PatchTransaction.latestReceipt(projectID: project.id, backupRoot: backupRoot) != nil, "failed restore discarded receipt")
                // Also cover the interrupted/prepared journal that used to be
                // presented as OFF even though another Apply was forbidden.
                var journal = try PropertyListSerialization.propertyList(from: oldJournal, format: nil) as! [String: Any]
                journal["status"] = "prepared"
                try PropertyListSerialization.data(fromPropertyList: journal, format: .binary, options: 0).write(to: receipt.journalURL)
                try check(PatchTransaction.recordedApplicationState(receipt: receipt) == .recoveryRequired, "prepared journal must show recovery")
                try check(PatchTransaction.inspectExistingApplication(receipt: receipt, project: project, containerResolver: { _ in container }) == .recoveryRequired,
                    "prepared journal must never be adopted as applied")
                try PatchTransaction.restore(receipt: receipt, containerResolver: { _ in container })
                for rule in project.rules { try check(Data(contentsOf: container.appendingPathComponent(rule.relativePath)) == original, "restore bytes differ") }
                // A committed restore wins over stale UI flags, including a
                // process interruption before the preference cleanup.
                registry.markApplied(catalogID)
                try check(registry.state(for: catalogID, recordedState: lookup) == .off, "restored journal must override stale ON flag")
                registry.clear(catalogID)
                try check(registry.projectID(for: catalogID) == nil, "successful restore did not clear catalog association")
                let commitProject = project
                let revokedBackups = base.appendingPathComponent("revoked-backups")
                do {
                    _ = try await DirectPatchExecutor.run(validation: {}) {
                        try PatchTransaction.apply(project: commitProject, backupRoot: revokedBackups, containerResolver: { _ in container }, beforeWrite: { index in
                            if index == 0 { NotificationCenter.default.post(name: Notification.Name("AstraNetworkAccessInvalidated"), object: nil) }
                        })
                    }
                    throw CatalogCheckError.failed("revoked transaction returned success")
                } catch PatchPackageError.applyFailed {}
                for rule in project.rules {
                    try check(Data(contentsOf: container.appendingPathComponent(rule.relativePath)) == original, "revocation left patched bytes instead of rolling back")
                }
                print("[PASS] catalog \(sourceID): CryptoKit, apply/restore, missing flag recovery, existing receipt adoption, interrupted restore")
            } catch { print("[FAIL] catalog \(sourceID): \(String(reflecting: error))"); throw error }
        }
        print("[PASS] \(entries.count) actual catalog packages: complete protected decode/apply/restore")
    }
}
