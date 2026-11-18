import Foundation
import CryptoKit
// Catalog I/O fixture stays on the 3105 route; actual OS dispatch is exercised
// separately against the complete production policy and resolver.
enum ExploitSupportPolicy {
    enum AccessProvider { case legacy3105, worseQuery }
    static let currentAccessProvider = AccessProvider.legacy3105
}
@MainActor final class IOS27ContainerPreparation {
    static let shared = IOS27ContainerPreparation()
    func prepareAdditionalTargets(bundleIDs: [String]) async throws { throw CatalogCheckError.failed("device preparation must not be used") }
}

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
    static func rejectsMode(_ detail: String, _ operation: () throws -> Void) throws {
        do { try operation() } catch is CatalogFeatureModeError { return }
        throw CatalogCheckError.failed("accepted: " + detail)
    }
    static func checkFeatureModes(in folder: URL) throws {
        let manager = FileManager.default
        let root = folder.appendingPathComponent("feature-modes", isDirectory: true)
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        let ffth = root.appendingPathComponent("ffth", isDirectory: true)
        let ffmax = root.appendingPathComponent("ffmax", isDirectory: true)
        for container in [ffth, ffmax] {
            try manager.createDirectory(at: container.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        }
        func container(_ bundle: String) throws -> URL {
            if bundle == "com.dts.freefireth" { return ffth }
            if bundle == "com.dts.freefiremax" { return ffmax }
            throw CatalogCheckError.failed("unknown fixture container")
        }
        func project(_ id: UUID = UUID(), name: String, bundle: String, file: String, bytes: String) -> PatchProject {
            PatchProject(id: id, name: name, isPrivate: true, bundleIdentifiers: [bundle], rules: [
                PatchRule(bundleID: bundle, relativePath: "Documents/" + file,
                    replacementFilename: file, replacementData: Data(bytes.utf8))
            ])
        }
        let avatar = ffth.appendingPathComponent("Documents/avatar.bin")
        let otherGame = ffmax.appendingPathComponent("Documents/effects.bin")
        let manualTarget = ffth.appendingPathComponent("Documents/manual.bin")
        for target in [avatar, otherGame, manualTarget] { try Data("original".utf8).write(to: target) }
        let normalA = project(name: "Avatar modifier", bundle: "com.dts.freefireth", file: "avatar.bin", bytes: "modifier A")
        let normalB = project(name: "Other game modifier", bundle: "com.dts.freefiremax", file: "effects.bin", bytes: "modifier B")
        let manual = project(name: "Manual project", bundle: "com.dts.freefireth", file: "manual.bin", bytes: "manual replacement")
        let receiptA = try PatchTransaction.apply(project: normalA, backupRoot: backupRoot, containerResolver: container)
        let receiptB = try PatchTransaction.apply(project: normalB, backupRoot: backupRoot, containerResolver: container)
        let manualReceipt = try PatchTransaction.apply(project: manual, backupRoot: backupRoot, containerResolver: container)
        let journals = try [receiptA, receiptB, manualReceipt].map { ($0.journalURL, try Data(contentsOf: $0.journalURL)) }
        let originalBackups = try (manager.enumerator(at: backupRoot, includingPropertiesForKeys: nil)!.allObjects as! [URL])
            .filter { $0.pathExtension == "original" }.map { ($0, try Data(contentsOf: $0)) }

        let suite = "itech-feature-modes-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = CatalogPatchApplicationRegistry(defaults: defaults)
        let modes = CatalogFeatureModeRegistry(defaults: defaults)
        let a = "catalog_1_ffth", b = "catalog_2_ffmax", restore = "catalog_79_ffth"
        catalog.associate(normalA.id, with: a); catalog.markApplied(a)
        catalog.associate(normalB.id, with: b); catalog.markApplied(b)
        defaults.set("unrelated value", forKey: "not_a_catalog_projectID")
        defaults.set("not a UUID", forKey: "patch_applied_invalid_projectID")
        try check(catalog.associations() == [a: normalA.id, b: normalB.id], "association discovery includes only valid catalog projects")
        let candidates = [
            CatalogFeatureModeRegistry.Candidate(identity: a, projectID: normalA.id, isRestoration: false, isActive: true),
            CatalogFeatureModeRegistry.Candidate(identity: b, projectID: normalB.id, isRestoration: false, isActive: true)
        ]
        let transition = try modes.prepare(identity: restore, isRestoration: true, candidates: candidates)
        try check(transition.projectID != normalA.id && transition.projectID != normalB.id, "each activation receives a fresh journal project")
        try check(Set(transition.suppressedIdentities) == Set([a, b]), "restoration suppresses all catalog entries including other games and different targets")
        try check(transition.ignoredProjectIDs == Set([normalA.id, normalB.id]), "only the known catalog projects are ignored for the incoming write")
        try check(modes.overrideState(for: a) == .recoveryRequired && modes.overrideState(for: b) == .recoveryRequired
            && modes.overrideState(for: restore) == .recoveryRequired, "pending activation never claims any affected item is safely OFF")
        try check(!modes.isSuppressed(a) && !modes.isSuppressed(b), "pending state does not commit suppression early")
        try check(Data(contentsOf: avatar) == Data("modifier A".utf8), "preparing a switch never writes game files")
        try check(catalog.state(for: a, recordedState: { _ in .applied }) == .applied, "pending overlay does not erase legacy state")
        let relaunchedPending = CatalogFeatureModeRegistry(defaults: UserDefaults(suiteName: suite)!)
        try check(relaunchedPending.pendingIdentity == restore, "pending activation survives registry reconstruction")
        try check(try relaunchedPending.prepare(identity: restore, isRestoration: true, candidates: []) == transition,
            "retry reuses the same pending project and token")
        try rejectsMode("different operation during pending write") {
            _ = try relaunchedPending.prepare(identity: a, isRestoration: false, candidates: candidates)
        }
        try rejectsMode("ending a mode during an interrupted write") { try modes.deactivate(restore) }
        let stale = CatalogFeatureModeRegistry.Transition(id: UUID(), identity: transition.identity,
            projectID: transition.projectID, isRestoration: transition.isRestoration,
            suppressedIdentities: transition.suppressedIdentities, ignoredProjectIDs: transition.ignoredProjectIDs)
        try rejectsMode("different commit token") { try modes.commit(stale) }

        let restoreProject = project(transition.projectID, name: "Restore Avatar", bundle: "com.dts.freefireth", file: "avatar.bin", bytes: "restored Avatar")
        do {
            _ = try PatchTransaction.apply(project: restoreProject, backupRoot: backupRoot, containerResolver: container)
            throw CatalogCheckError.failed("default write bypassed an occupied target")
        } catch PatchPackageError.targetOccupied(_) {}
        catalog.associate(transition.projectID, with: restore)
        _ = try PatchTransaction.apply(project: restoreProject, backupRoot: backupRoot,
            ignoringProjectIDs: transition.ignoredProjectIDs, containerResolver: container, beforeWrite: { _ in
                try check(modes.overrideState(for: a) == .recoveryRequired, "writer sees pending state until the write succeeds")
            })
        catalog.markApplied(restore)
        try modes.commit(transition)
        try check(modes.pendingIdentity == nil && modes.overrideState(for: restore) == nil, "successful restoration commits the selected item")
        try check(modes.isSuppressed(a) && modes.isSuppressed(b), "successful restoration commits all other toggles OFF")
        try check(modes.isRestoration(restore) == true && modes.isRestoration(a) == false, "committed mode metadata remains available")
        for (url, bytes) in journals { try check(Data(contentsOf: url) == bytes, "switch keeps every old journal") }
        for (url, bytes) in originalBackups { try check(Data(contentsOf: url) == bytes, "switch keeps every original backup") }
        try check(PatchTransaction.latestReceipt(projectID: normalA.id, backupRoot: backupRoot) != nil,
            "superseded receipt remains available for history")
        let relaunched = CatalogFeatureModeRegistry(defaults: UserDefaults(suiteName: suite)!)
        try check(relaunched.isSuppressed(a) && relaunched.isSuppressed(b), "old active journals cannot resurrect catalog toggles after relaunch")

        let normalTransition = try relaunched.prepare(identity: a, isRestoration: false, candidates: candidates)
        try check(normalTransition.suppressedIdentities == [restore], "normal activation suppresses the restoration only")
        try check(relaunched.overrideState(for: b) == .off, "another suppressed normal item never reactivates implicitly")
        let a2 = project(normalTransition.projectID, name: "Avatar modifier again", bundle: "com.dts.freefireth", file: "avatar.bin", bytes: "modifier A again")
        catalog.associate(a2.id, with: a)
        _ = try PatchTransaction.apply(project: a2, backupRoot: backupRoot,
            ignoringProjectIDs: normalTransition.ignoredProjectIDs, containerResolver: container)
        catalog.markApplied(a); try relaunched.commit(normalTransition)
        try check(relaunched.overrideState(for: a) == nil && relaunched.isSuppressed(restore) && relaunched.isSuppressed(b),
            "normal mode clears restoration without reactivating any other normal item")
        try check(!relaunched.ignoredProjectIDs.contains(a2.id), "current activation never retires its own fresh receipt")
        let occupiedManual = project(name: "Unknown manual collision", bundle: "com.dts.freefireth", file: "manual.bin", bytes: "must not write")
        do {
            _ = try PatchTransaction.apply(project: occupiedManual, backupRoot: backupRoot,
                ignoringProjectIDs: relaunched.ignoredProjectIDs, containerResolver: container)
            throw CatalogCheckError.failed("mode switch ignored an unlisted manual project")
        } catch PatchPackageError.targetOccupied(_) {}

        let bTransition = try relaunched.prepare(identity: b, isRestoration: false, candidates: candidates)
        let b2 = project(bTransition.projectID, name: "Other game again", bundle: "com.dts.freefiremax", file: "effects.bin", bytes: "modifier B again")
        _ = try PatchTransaction.apply(project: b2, backupRoot: backupRoot,
            ignoringProjectIDs: bTransition.ignoredProjectIDs, containerResolver: container)
        catalog.associate(b2.id, with: b); catalog.markApplied(b); try relaunched.commit(bTransition)
        try check(relaunched.overrideState(for: a) == nil && relaunched.overrideState(for: b) == nil,
            "enabling one normal feature keeps an already active normal feature ON")

        let failedTransition = try relaunched.prepare(identity: restore, isRestoration: true, candidates: candidates)
        let retryProject = project(failedTransition.projectID, name: "Restore retry", bundle: "com.dts.freefireth", file: "avatar.bin", bytes: "restored after retry")
        catalog.associate(retryProject.id, with: restore)
        do {
            _ = try PatchTransaction.apply(project: retryProject, backupRoot: backupRoot,
                ignoringProjectIDs: failedTransition.ignoredProjectIDs, containerResolver: container,
                beforeWrite: { _ in throw CatalogCheckError.failed("injected activation failure") })
            throw CatalogCheckError.failed("write fault did not propagate")
        } catch PatchPackageError.applyFailed {}
        try check(Data(contentsOf: avatar) == Data("modifier A again".utf8), "failed replacement rolls back its game bytes")
        try check(relaunched.overrideState(for: a) == .recoveryRequired && relaunched.overrideState(for: b) == .recoveryRequired
            && relaunched.overrideState(for: restore) == .recoveryRequired, "failed switch remains pending instead of showing false OFF states")
        let retry = CatalogFeatureModeRegistry(defaults: UserDefaults(suiteName: suite)!)
        let retriedTransition = try retry.prepare(identity: restore, isRestoration: true, candidates: [])
        try check(retriedTransition == failedTransition, "failed activation relaunch retains its exact retry identity")
        _ = try PatchTransaction.apply(project: retryProject, backupRoot: backupRoot,
            ignoringProjectIDs: retriedTransition.ignoredProjectIDs, containerResolver: container)
        catalog.markApplied(restore); try retry.commit(retriedTransition)
        let beforeDeactivate = try Data(contentsOf: avatar)
        try retry.deactivate(restore)
        try check(Data(contentsOf: avatar) == beforeDeactivate, "manually ending restoration never rewrites an old modifier")
        try check(retry.isSuppressed(restore) && retry.isSuppressed(a) && retry.isSuppressed(b),
            "ending restoration keeps all previously suppressed items OFF")

        let legacy = "legacy_restore_ffth", legacyID = UUID()
        catalog.associate(legacyID, with: legacy); catalog.markApplied(legacy)
        try retry.deactivate(legacy, projectID: legacyID, isRestoration: true)
        try check(retry.isSuppressed(legacy) && retry.isRestoration(legacy) == true
            && retry.ignoredProjectIDs.contains(legacyID), "ending a legacy restoration imports its OFF overlay and old project")
        try check(catalog.projectID(for: legacy) == legacyID, "legacy mode OFF never deletes old associations or backups")
        defaults.set(Data("corrupted mode document".utf8), forKey: "astra_catalog_feature_modes_v1")
        try check(retry.overrideState(for: a) == .recoveryRequired && !retry.isSuppressed(a),
            "corrupt persisted mode state never reports a safe OFF overlay")
        try rejectsMode("activation with corrupt persisted mode state") {
            _ = try retry.prepare(identity: a, isRestoration: false, candidates: candidates)
        }
        print("[PASS] actual catalog modes: atomic pending/commit, all-feature exclusion, relaunch, retry, no resurrection, receipt retention, manual collision guard")
    }
    static func checkDurableFeatureModes(in folder: URL) throws {
        let manager = FileManager.default
        let root = folder.appendingPathComponent("durable-feature-modes", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "itech-durable-modes-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = root.appendingPathComponent("CatalogModes/modes-v1.json")
        let a = "catalog_1_ffth", restore = "catalog_79_ffth", oldID = UUID()
        let candidates = [CatalogFeatureModeRegistry.Candidate(identity: a, projectID: oldID,
            isRestoration: false, isActive: true)]
        let modes = CatalogFeatureModeRegistry(defaults: defaults, persistenceURL: url)
        let pending = try modes.prepare(identity: restore, isRestoration: true, candidates: candidates)
        try check(manager.fileExists(atPath: url.path), "activation intent is atomically stored before the writer can start")
        let permissions = try manager.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber
        let parentPermissions = try manager.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as! NSNumber
        try check((permissions.intValue & 0o777) == 0o600 && (parentPermissions.intValue & 0o777) == 0o700,
            "durable catalog mode document and folder keep private permissions")
        defaults.removePersistentDomain(forName: suite)
        let resumed = CatalogFeatureModeRegistry(defaults: UserDefaults(suiteName: suite)!, persistenceURL: url)
        try check(resumed.pendingIdentity == restore && resumed.projectID(for: restore) == pending.projectID,
            "losing preferences cannot lose the pending activation or its fresh project")
        try check(resumed.associations() == [a: oldID, restore: pending.projectID],
            "durable snapshot reconstructs old and pending catalog associations")
        try check(resumed.overrideState(for: a) == .recoveryRequired && resumed.overrideState(for: restore) == .recoveryRequired,
            "durable pending state stays recovery-required after preferences are lost")
        try check(try resumed.prepare(identity: restore, isRestoration: true, candidates: []) == pending,
            "durable retry preserves the original token and project ID")
        try resumed.commit(pending)
        defaults.removePersistentDomain(forName: suite)
        let committed = CatalogFeatureModeRegistry(defaults: UserDefaults(suiteName: suite)!, persistenceURL: url)
        try check(committed.pendingIdentity == nil && committed.isSuppressed(a) && committed.overrideState(for: restore) == nil,
            "committed mode survives loss of the preference cache")
        try check(committed.projectID(for: restore) == pending.projectID
            && committed.ignoredProjectIDs.contains(oldID), "committed durable IDs preserve active and suppressed receipts")
        defaults.set(Data("stale corrupted preference cache".utf8), forKey: "astra_catalog_feature_modes_v1")
        try check(committed.projectID(for: restore) == pending.projectID && committed.isSuppressed(a),
            "the atomic document wins over a corrupt preference cache")

        let migrationSuite = "itech-mode-file-migration-" + UUID().uuidString
        let migrationDefaults = UserDefaults(suiteName: migrationSuite)!
        defer { migrationDefaults.removePersistentDomain(forName: migrationSuite) }
        let legacyModes = CatalogFeatureModeRegistry(defaults: migrationDefaults)
        let oldPending = try legacyModes.prepare(identity: restore, isRestoration: true, candidates: candidates)
        let migratedURL = root.appendingPathComponent("MigratedModes/modes-v1.json")
        let migrated = CatalogFeatureModeRegistry(defaults: migrationDefaults, persistenceURL: migratedURL)
        try check(!manager.fileExists(atPath: migratedURL.path), "reading old storage does not create a mode document")
        try check(try migrated.prepare(identity: restore, isRestoration: true, candidates: []) == oldPending,
            "an old preference-only pending activation migrates without a new project")
        migrationDefaults.removePersistentDomain(forName: migrationSuite)
        let migratedRelaunch = CatalogFeatureModeRegistry(defaults: UserDefaults(suiteName: migrationSuite)!, persistenceURL: migratedURL)
        try check(migratedRelaunch.pendingIdentity == restore && migratedRelaunch.projectID(for: restore) == oldPending.projectID,
            "retry migrates preference-only intent to the atomic document before any write")

        let blockedParent = root.appendingPathComponent("not-a-directory")
        try Data("regular file blocks persistence".utf8).write(to: blockedParent)
        let gameFile = root.appendingPathComponent("game-state.bin")
        let original = Data("the existing game state".utf8)
        try original.write(to: gameFile)
        let failureSuite = "itech-mode-persist-failure-" + UUID().uuidString
        let failureDefaults = UserDefaults(suiteName: failureSuite)!
        defer { failureDefaults.removePersistentDomain(forName: failureSuite) }
        let failing = CatalogFeatureModeRegistry(defaults: failureDefaults,
            persistenceURL: blockedParent.appendingPathComponent("modes-v1.json"))
        var writerReached = false
        do {
            _ = try failing.prepare(identity: restore, isRestoration: true, candidates: candidates)
            writerReached = true
            try Data("must not be written".utf8).write(to: gameFile)
            throw CatalogCheckError.failed("an unwritable mode document allowed the writer")
        } catch CatalogFeatureModeError.persistenceFailed {}
        try check(!writerReached && Data(contentsOf: gameFile) == original,
            "failed atomic persistence stops before any game write")
        try check(failing.pendingIdentity == nil && failureDefaults.object(forKey: "astra_catalog_feature_modes_v1") == nil,
            "failed atomic persistence never publishes a preference-only intent")
        try Data("corrupt authoritative mode document".utf8).write(to: url, options: .atomic)
        try check(committed.overrideState(for: restore) == .recoveryRequired,
            "corrupt authoritative file never falls back to a stale preference cache")
        try rejectsMode("corrupt authoritative mode file") {
            _ = try committed.prepare(identity: restore, isRestoration: true, candidates: [])
        }
        print("[PASS] durable catalog modes: atomic private file, preference-loss recovery, migration, authoritative reads, failed persistence blocks writes")
    }
    static func checkFailedModeRecovery(in folder: URL) throws {
        let manager = FileManager.default
        let root = folder.appendingPathComponent("failed-mode-recovery", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "itech-failed-mode-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = root.appendingPathComponent("modes.json")
        let modes = CatalogFeatureModeRegistry(defaults: defaults, persistenceURL: url)
        let catalog = CatalogPatchApplicationRegistry(defaults: defaults)
        let normal = "catalog_67_ffth", other = "catalog_74_ffth", restore = "catalog_79_ffth"
        let oldNormal = UUID()
        catalog.associate(oldNormal, with: normal); catalog.markApplied(normal)
        let candidates = [CatalogFeatureModeRegistry.Candidate(identity: normal, projectID: oldNormal,
            isRestoration: false, isActive: true)]
        let game = root.appendingPathComponent("avatar.bin")
        let before = Data("existing modifier".utf8)
        try before.write(to: game)

        // A container/pairing lookup failure must not strand every switch or
        // commit restoration OFF overlays when no write has begun.
        let preflight = try modes.prepare(identity: restore, isRestoration: true, candidates: candidates)
        catalog.associate(preflight.projectID, with: restore)
        try modes.recordFailure(preflight, writeMayHaveStarted: false)
        try check(modes.pendingIdentity == nil && modes.projectID(for: restore) == nil,
            "pre-write failure releases the global intent without adding a false application")
        try check(modes.overrideState(for: normal) == nil && !modes.isSuppressed(normal),
            "pre-write failure keeps the prior active normal feature")
        try check(Data(contentsOf: game) == before, "pre-write recovery never changes game bytes")
        let sameItem = try modes.prepare(identity: normal, isRestoration: false, candidates: candidates)
        try modes.recordFailure(sameItem, writeMayHaveStarted: false)
        try check(modes.projectID(for: normal) == oldNormal, "pre-write failure preserves the old selected association")

        // Simulate a writer that changed one file and then failed. The intent
        // may end, but every possibly affected item retains an explicit warning.
        let partial = try modes.prepare(identity: restore, isRestoration: true, candidates: candidates)
        try Data("partially restored".utf8).write(to: game)
        try modes.recordFailure(partial, writeMayHaveStarted: true)
        try check(modes.pendingIdentity == nil && modes.requiresActivationRetry(restore),
            "partial failure stops the global lock and keeps a per-item retry marker")
        try check(modes.overrideState(for: restore) == .recoveryRequired
            && modes.overrideState(for: normal) == .recoveryRequired,
            "partial failure never marks the selected or conflicting item safely OFF")
        try check(!modes.isSuppressed(restore) && !modes.isSuppressed(normal),
            "partial failure does not claim a successful mutually exclusive switch")
        let afterFailure = try Data(contentsOf: game)
        let next = try modes.prepare(identity: other, isRestoration: false, candidates: [])
        try check(next.suppressedIdentities == [restore],
            "another normal feature can proceed after the failed restoration")
        try modes.commit(next)
        try check(modes.isSuppressed(restore) && modes.overrideState(for: other) == nil,
            "successful new activation ends the failed restore mode")
        try check(modes.requiresActivationRetry(normal), "unrelated uncertain writes keep their warning")
        try check(Data(contentsOf: game) == afterFailure, "mode bookkeeping never silently replays old files")

        // Build 15 saved intent without a progress marker. Migrate it as an
        // uncertain write after relaunch rather than demanding the same item.
        let interrupted = try modes.prepare(identity: restore, isRestoration: true, candidates: [])
        defaults.removePersistentDomain(forName: suite)
        let relaunched = CatalogFeatureModeRegistry(defaults: UserDefaults(suiteName: suite)!, persistenceURL: url)
        try check(try relaunched.recoverInterruptedActivation() == interrupted,
            "old persisted intent can be reconciled after preference loss and relaunch")
        try check(relaunched.pendingIdentity == nil && relaunched.requiresActivationRetry(restore),
            "interrupted activation remains visible without blocking the catalog")
        try check(try relaunched.recoverInterruptedActivation() == nil, "interrupted recovery is idempotent")
        try rejectsMode("stale callback after the previous activation ended") { try relaunched.commit(interrupted) }
        let repaired = try relaunched.prepare(identity: normal, isRestoration: false, candidates: [])
        try relaunched.commit(repaired)
        try check(!relaunched.requiresActivationRetry(normal) && relaunched.isSuppressed(restore),
            "successful retry clears only its own warning and suppresses restoration")
        print("[PASS] failed catalog modes: pre-write cancellation, partial-write warnings, other-item recovery, build-15 migration, no global deadlock")
    }

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
        try checkFeatureModes(in: temp)
        try checkDurableFeatureModes(in: temp)
        try checkFailedModeRecovery(in: temp)
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
