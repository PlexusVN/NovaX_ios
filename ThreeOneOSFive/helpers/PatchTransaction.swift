import CryptoKit
import Darwin
import Foundation

/// Preserve the failing filesystem step and POSIX cause without exposing a
/// private container path or localized NSError text.
private struct PatchFilesystemFailure: LocalizedError {
    let operation: String
    let underlying: NSError
    var rollbackCompleted: Bool?

    var errorDescription: String? {
        var current: NSError? = underlying
        var posix: Int?
        for _ in 0..<8 {
            guard let error = current else { break }
            if error.domain == NSPOSIXErrorDomain {
                posix = error.code
                break
            }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        let reason: String
        switch posix {
        case Int(EACCES), Int(EPERM): reason = "Chưa có quyền thực hiện thao tác file này."
        case Int(ENOSPC): reason = "Không đủ dung lượng để hoàn tất thao tác file."
        case Int(EROFS): reason = "Vị trí đích đang chỉ cho phép đọc."
        case Int(ENOENT): reason = "File hoặc thư mục cần dùng không còn tồn tại."
        default: reason = "Thao tác file chưa hoàn tất."
        }
        let code = "\(underlying.domain):\(underlying.code)" +
            (posix.map { "; errno=\($0)" } ?? "")
        let rollback = rollbackCompleted.map {
            $0 ? " Đã hoàn tác giao dịch." :
                " Chưa xác nhận hoàn tác đầy đủ; bản sao lưu được giữ lại."
        } ?? ""
        return "\(reason) [\(operation); \(code)]\(rollback)"
    }
}

struct PatchTransactionReceipt: Equatable, Identifiable, Sendable {
    let id: UUID
    let projectID: UUID
    let journalURL: URL
}

enum PatchTargetChangeKind: Equatable, Sendable {
    case modified
    case missing
}

struct PatchTargetChange: Equatable, Sendable {
    let bundleID: String
    let relativePath: String
    let kind: PatchTargetChangeKind

    var displayPath: String {
        bundleID + "/" + relativePath
    }
}

struct PatchRestoreInspection: Equatable, Sendable {
    let changedTargets: [PatchTargetChange]
}

enum PatchApplicationState: Equatable {
    case off, applied, recoveryRequired
    var requiresRestore: Bool { self != .off }
}

enum PatchDisableOutcome: Equatable, Sendable {
    case restored
    case disabledWithoutRestore
}

enum PatchWriteEngine: String, Codable {
    case legacy3105
    case worseQuery
    case airLift
}

enum PatchEnginePhase: String, Codable {
    case writing
    case applied
    case recoveryRequired
    case restored
}

enum PatchBaseline: String, Codable {
    case capturedPriorState
    case unavailable
    case legacyUnknown
}

enum PatchEngineStateError: LocalizedError {
    case recoveryRequired
    case legacyAmbiguous
    case legacyTargetsUnknown
    case invalidRecord
    case airLiftNoBackup
    case unsupportedAirLiftDirectory
    case operationNotHeld
    case restoreProviderUnavailable

    var errorDescription: String? {
        switch self {
        case .recoveryRequired:
            return "Giao dịch trước chưa được khôi phục. Astra giữ nguyên bản sao lưu và chặn ghi tiếp."
        case .legacyAmbiguous:
            return "Lịch sử AirLift và bản sao lưu trực tiếp cũ không đủ để xác định bản gốc. Astra giữ nguyên dữ liệu để tránh khôi phục nhầm."
        case .legacyTargetsUnknown:
            return "Lịch sử AirLift cũ thiếu ứng dụng hoặc đường dẫn đích. Cần xác minh dữ liệu gốc trước khi ghi tiếp."
        case .invalidRecord:
            return "Thông tin giao dịch không hợp lệ. Bản sao lưu và lịch sử được giữ lại để kiểm tra."
        case .airLiftNoBackup:
            return "Lần ghi này dùng AirLift và không có bản sao lưu file trước khi ghi. Cần gói khôi phục chính thức đúng phiên bản."
        case .unsupportedAirLiftDirectory:
            return "Gói yêu cầu tạo thư mục rỗng mà AirLift chưa hỗ trợ. Chưa có dữ liệu nào được ghi."
        case .operationNotHeld:
            return "Thao tác ghi chưa giữ phiên giao dịch độc quyền."
        case .restoreProviderUnavailable:
            return "Bản sao lưu trực tiếp được giữ nguyên, nhưng cơ chế truy cập hiện tại chưa hỗ trợ khôi phục giao dịch đó."
        }
    }
}

enum AirLiftPatchCapabilities {
    static func validate(_ project: PatchProject) throws {
        guard !project.rules.isEmpty else {
            throw PatchEngineStateError.unsupportedAirLiftDirectory
        }
        guard project.directories.allSatisfy({ directory in
            project.rules.contains {
                $0.bundleID == directory.bundleID
                    && $0.relativePath.hasPrefix(directory.relativePath + "/")
            }
        }) else {
            throw PatchEngineStateError.unsupportedAirLiftDirectory
        }
    }
}

struct PatchEngineApplicationRecord: Codable, Equatable {
    let schema: Int
    let projectID: UUID
    let operationID: UUID
    let engine: PatchWriteEngine
    let baseline: PatchBaseline
    let targetKeys: [String]
    var journalID: UUID?
    var phase: PatchEnginePhase
    var completedBatches: Int
    let totalBatches: Int

    init(
        projectID: UUID,
        operationID: UUID = UUID(),
        engine: PatchWriteEngine,
        baseline: PatchBaseline,
        targetKeys: [String],
        journalID: UUID? = nil,
        phase: PatchEnginePhase = .writing,
        totalBatches: Int = 0
    ) {
        schema = 1
        self.projectID = projectID
        self.operationID = operationID
        self.engine = engine
        self.baseline = baseline
        self.targetKeys = targetKeys.sorted()
        self.journalID = journalID
        self.phase = phase
        completedBatches = 0
        self.totalBatches = totalBatches
    }

    var applicationState: PatchApplicationState {
        switch phase {
        case .writing, .recoveryRequired: return .recoveryRequired
        case .applied: return .applied
        case .restored: return .off
        }
    }

    func validate() throws {
        guard schema == 1,
              completedBatches >= 0,
              totalBatches >= completedBatches,
              !targetKeys.isEmpty,
              targetKeys == Array(Set(targetKeys)).sorted(),
              targetKeys.allSatisfy({ !$0.isEmpty && $0.contains("\0") }),
              (engine == .airLift
                  ? baseline == .unavailable && journalID == nil
                  : baseline != .unavailable && journalID != nil) else {
            throw PatchEngineStateError.invalidRecord
        }
    }
}

struct PatchEngineApplicationStore {
    let backupRoot: URL

    static let maximumRecordBytes = 2 * 1024 * 1024
    static let maximumJournalBytes = 64 * 1024 * 1024

    private var directory: URL {
        backupRoot.appendingPathComponent(".engine-applications", isDirectory: true)
    }

    private func url(_ projectID: UUID) -> URL {
        directory.appendingPathComponent(projectID.uuidString + ".plist")
    }

    private struct JournalProjection: Decodable {
        struct Target: Decodable {
            let bundleID: String
            let relativePath: String
            let containerFingerprint: Data
            var key: String { bundleID + "\0" + relativePath }
        }

        let schemaVersion: Int
        let transactionID: UUID
        let projectID: UUID
        let createdAt: Date
        let status: String
        let records: [Target]
        let createdDirectories: [Target]?
        let engineRecord: PatchEngineApplicationRecord?
        var isTerminal: Bool { status == "restored" || status == "rolledBack" }
    }

    static func encodedRecord(_ record: PatchEngineApplicationRecord) throws -> Data {
        try record.validate()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(record)
        guard data.count <= maximumRecordBytes else {
            throw PatchEngineStateError.invalidRecord
        }
        return data
    }

    private func readProjection(
        projectID: UUID,
        transactionID: UUID
    ) throws -> JournalProjection {
        let path = backupRoot
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent(transactionID.uuidString, isDirectory: true)
            .appendingPathComponent("journal.plist")
        let data = try Data(contentsOf: path)
        guard data.count <= Self.maximumJournalBytes,
              let journal = try? PropertyListDecoder().decode(JournalProjection.self, from: data),
              (1...3).contains(journal.schemaVersion),
              journal.projectID == projectID,
              journal.transactionID == transactionID,
              ["prepared", "applied", "restored", "rolledBack"].contains(journal.status) else {
            throw PatchEngineStateError.invalidRecord
        }
        for target in journal.records + (journal.createdDirectories ?? []) {
            guard try PatchPathValidator.canonicalBundleIdentifier(target.bundleID) == target.bundleID,
                  try PatchPathValidator.canonicalRelativePath(target.relativePath) == target.relativePath,
                  target.containerFingerprint.count == 32 else {
                throw PatchEngineStateError.invalidRecord
            }
        }
        if let record = journal.engineRecord {
            _ = try Self.encodedRecord(record)
            guard journal.schemaVersion == 3,
                  record.projectID == projectID,
                  record.operationID == transactionID,
                  record.journalID == transactionID,
                  record.engine != .airLift,
                  record.baseline == .capturedPriorState,
                  record.phase == .writing,
                  record.completedBatches == 0,
                  record.totalBatches == 0,
                  Set(journal.records.map(\.key)).isSubset(of: Set(record.targetKeys)),
                  (journal.createdDirectories ?? []).allSatisfy({ directory in
                      record.targetKeys.contains {
                          $0 == directory.key || $0.hasPrefix(directory.key + "/")
                      }
                  }) else {
                throw PatchEngineStateError.invalidRecord
            }
        } else if journal.schemaVersion == 3 {
            throw PatchEngineStateError.invalidRecord
        }
        return journal
    }

    private func latestBoundJournal(_ projectID: UUID) throws -> JournalProjection? {
        let root = backupRoot.appendingPathComponent(projectID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        var journals: [JournalProjection] = []
        for child in try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) {
            guard let transactionID = UUID(uuidString: child.lastPathComponent),
                  FileManager.default.fileExists(
                      atPath: child.appendingPathComponent("journal.plist").path
                  ) else { continue }
            journals.append(try readProjection(projectID: projectID, transactionID: transactionID))
        }
        let unfinished = journals.filter { !$0.isTerminal }
        guard unfinished.count <= 1 else { throw PatchEngineStateError.invalidRecord }
        if let pending = unfinished.first {
            guard !journals.contains(where: {
                $0.isTerminal && $0.createdAt > pending.createdAt
            }) else {
                throw PatchEngineStateError.invalidRecord
            }
            return pending.engineRecord == nil ? nil : pending
        }
        return journals.sorted { $0.createdAt > $1.createdAt }.first.flatMap {
            $0.engineRecord == nil ? nil : $0
        }
    }

    func read(_ projectID: UUID) throws -> PatchEngineApplicationRecord? {
        let target = url(projectID)
        var sidecar: PatchEngineApplicationRecord?
        if FileManager.default.fileExists(atPath: target.path) {
            let data = try Data(contentsOf: target)
            guard data.count <= Self.maximumRecordBytes,
                  let record = try? PropertyListDecoder().decode(
                      PatchEngineApplicationRecord.self,
                      from: data
                  ),
                  record.projectID == projectID else {
                throw PatchEngineStateError.invalidRecord
            }
            try record.validate()
            sidecar = record
        }

        guard let journal = try latestBoundJournal(projectID),
              var bound = journal.engineRecord else {
            return sidecar
        }
        if let sidecar, sidecar.engine == .airLift, journal.isTerminal {
            return sidecar
        }
        if let sidecar {
            if sidecar.journalID == bound.journalID {
                guard sidecar.operationID == bound.operationID,
                      sidecar.engine == bound.engine,
                      sidecar.baseline == bound.baseline,
                      sidecar.targetKeys == bound.targetKeys else {
                    throw PatchEngineStateError.invalidRecord
                }
            } else {
                guard sidecar.engine != .airLift,
                      sidecar.baseline != .legacyUnknown,
                      let previousID = sidecar.journalID,
                      sidecar.operationID == previousID else {
                    throw PatchEngineStateError.invalidRecord
                }
                let previous = try readProjection(
                    projectID: projectID,
                    transactionID: previousID
                )
                guard previous.isTerminal,
                      previous.createdAt <= journal.createdAt else {
                    throw PatchEngineStateError.invalidRecord
                }
            }
        }
        switch journal.status {
        case "prepared": bound.phase = .recoveryRequired
        case "applied": bound.phase = .applied
        default: bound.phase = .restored
        }
        return bound
    }

    func save(_ record: PatchEngineApplicationRecord) throws {
        let data = try Self.encodedRecord(record)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(record.projectID), options: .atomic)
    }

    func requireResolvedLegacyHistory(defaults: UserDefaults = .standard) throws {
        let prefix = "airlift.applied."
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            guard (value as? NSNumber)?.boolValue == true || value as? Bool == true else {
                continue
            }
            guard let projectID = UUID(uuidString: String(key.dropFirst(prefix.count))),
                  try read(projectID) != nil else {
                throw PatchEngineStateError.legacyTargetsUnknown
            }
        }
    }

    func requireNoUnbackedOverlap(
        projectID: UUID,
        targetKeys: [String],
        includingBackedApplications: Bool = false
    ) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for item in try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) where item.pathExtension == "plist" {
            guard let id = UUID(uuidString: item.deletingPathExtension().lastPathComponent),
                  let record = try read(id) else {
                throw PatchEngineStateError.invalidRecord
            }
            guard record.phase != .restored,
                  includingBackedApplications || record.engine == .airLift else {
                continue
            }
            if record.projectID == projectID || record.targetKeys.contains(where: { old in
                targetKeys.contains {
                    old == $0 || old.hasPrefix($0 + "/") || $0.hasPrefix(old + "/")
                }
            }) {
                throw PatchEngineStateError.recoveryRequired
            }
        }
    }

    static func reconcile(
        record: PatchEngineApplicationRecord?,
        journal: PatchApplicationState?,
        legacyAirLift: Bool
    ) -> PatchApplicationState? {
        if let record {
            if record.engine == .airLift { return record.applicationState }
            guard let journal else { return .recoveryRequired }
            if journal == .off { return .off }
            return record.phase == .restored ? .recoveryRequired : journal
        }
        if legacyAirLift && journal != nil { return .recoveryRequired }
        if legacyAirLift { return .applied }
        return journal
    }

    static func requireDirectRestore(
        record: PatchEngineApplicationRecord?,
        receiptID: UUID?,
        journal: PatchApplicationState?,
        legacyAirLift: Bool
    ) throws {
        if let record {
            guard record.engine != .airLift,
                  record.baseline != .legacyUnknown else {
                throw PatchEngineStateError.airLiftNoBackup
            }
            guard record.journalID == receiptID || journal == .off else {
                throw PatchEngineStateError.invalidRecord
            }
            return
        }
        if legacyAirLift {
            if journal != nil { throw PatchEngineStateError.legacyAmbiguous }
            throw PatchEngineStateError.airLiftNoBackup
        }
    }
}

actor PatchFilesystemGate {
    static let shared = PatchFilesystemGate()

    private var owner: UUID?
    private var waiters: [(UUID, CheckedContinuation<UUID, Error>)] = []

    func acquire() async throws -> UUID {
        try Task.checkCancellation()
        let id = UUID()
        return try await withTaskCancellationHandler(
            operation: {
                if owner == nil {
                    owner = id
                    return id
                }
                return try await withCheckedThrowingContinuation {
                    waiters.append((id, $0))
                }
            },
            onCancel: { Task { await self.cancel(id) } }
        )
    }

    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.1.resume(throwing: CancellationError())
    }

    func validate(_ id: UUID) throws {
        try Task.checkCancellation()
        guard owner == id else { throw PatchEngineStateError.operationNotHeld }
    }

    func release(_ id: UUID) {
        guard owner == id else { return }
        if waiters.isEmpty {
            owner = nil
        } else {
            let next = waiters.removeFirst()
            owner = next.0
            next.1.resume(returning: next.0)
        }
    }
}

@MainActor
func withExclusivePatchOperation<T>(
    _ operation: @MainActor (UUID) async throws -> T
) async throws -> T {
    let id = try await PatchFilesystemGate.shared.acquire()
    do {
        try await PatchFilesystemGate.shared.validate(id)
        let result = try await operation(id)
        await PatchFilesystemGate.shared.release(id)
        return result
    } catch {
        await PatchFilesystemGate.shared.release(id)
        throw error
    }
}

/// Preferences associate catalog items with transaction journals, which own the
/// backups. A missing preference flag must never hide an existing transaction.
struct CatalogPatchApplicationRegistry {
    let defaults: UserDefaults
    private let prefix = "astra_patch_applied_"
    func projectID(for identity: String) -> UUID? {
        defaults.string(forKey: prefix + identity + "_projectID").flatMap(UUID.init(uuidString:))
    }
    func associate(_ projectID: UUID, with identity: String) {
        defaults.set(projectID.uuidString, forKey: prefix + identity + "_projectID")
    }
    /// Include hidden catalog entries: an item disappearing from the latest
    /// catalog must not lose its saved project association during a mode switch.
    func associations() -> [String: UUID] {
        let suffix = "_projectID"
        var values: [String: UUID] = [:]
        for (key, value) in defaults.dictionaryRepresentation()
            where key.hasPrefix(prefix) && key.hasSuffix(suffix) {
            let identity = String(key.dropFirst(prefix.count).dropLast(suffix.count))
            if !identity.isEmpty, let text = value as? String, let id = UUID(uuidString: text) {
                values[identity] = id
            }
        }
        return values
    }
    /// Adopt legacy slug-based preferences without deleting their journal or
    /// overwriting a newer stable association. Repeat calls are harmless.
    func migrateIdentity(from legacy: String, to stable: String) {
        guard legacy != stable else { return }
        let oldID = projectID(for: legacy), currentID = projectID(for: stable)
        guard currentID == nil || currentID == oldID else { return }
        if let oldID { associate(oldID, with: stable) }
        for suffix in ["", "_recovery"] where defaults.bool(forKey: prefix + legacy + suffix) {
            defaults.set(true, forKey: prefix + stable + suffix)
        }
        // Preference keys only; the transaction journal/backups are untouched.
        // Leaving old ON flags would resurrect them after a successful restore.
        clear(legacy)
    }
    func markApplied(_ identity: String) {
        defaults.set(true, forKey: prefix + identity)
        defaults.removeObject(forKey: prefix + identity + "_recovery")
    }
    func markRecoveryRequired(_ identity: String) {
        defaults.set(true, forKey: prefix + identity + "_recovery")
    }
    func clear(_ identity: String) {
        for suffix in ["", "_projectID", "_recovery"] { defaults.removeObject(forKey: prefix + identity + suffix) }
    }
    func state(for identity: String, recordedState: (UUID) -> PatchApplicationState?) -> PatchApplicationState {
        if let id = projectID(for: identity), let state = recordedState(id) {
            if state == .off { return .off }
            return defaults.bool(forKey: prefix + identity + "_recovery") ? .recoveryRequired : state
        }
        return defaults.bool(forKey: prefix + identity) || defaults.bool(forKey: prefix + identity + "_recovery")
            ? .recoveryRequired : .off
    }
}

enum CatalogFeatureModeError: LocalizedError {
    case pendingOperation, invalidState, staleTransition, persistenceFailed
    var errorDescription: String? {
        switch self {
        case .pendingOperation:
            return "Một lần bật chức năng chưa hoàn tất. Hãy thử lại đúng chức năng đang cần khôi phục trước khi chuyển mục khác."
        case .invalidState, .persistenceFailed:
            return "Chưa lưu được trạng thái chức năng an toàn. Hãy mở lại ứng dụng rồi thử lại."
        case .staleTransition:
            return "Thao tác đã thay đổi. Hãy làm mới trạng thái chức năng rồi thử lại."
        }
    }
}

/// A catalog mode switch never deletes transaction journals or original backups.
/// The durable pending record keeps an interrupted write visible until the same
/// activation is retried. Only a successful write may commit the OFF overlays.
struct CatalogFeatureModeRegistry {
    struct Candidate {
        let identity: String
        let projectID: UUID
        let isRestoration: Bool
        let isActive: Bool
    }
    struct Transition: Codable, Equatable {
        let id: UUID
        let identity: String
        let projectID: UUID
        let isRestoration: Bool
        let suppressedIdentities: [String]
        let ignoredProjectIDs: Set<UUID>
    }
    private struct Entry: Codable {
        let projectID: UUID
        let isRestoration: Bool
        var isActive: Bool
        // Optional for documents created by build 15. A failed/uncertain write
        // stays visible without blocking every other catalog operation.
        var needsActivationRetry: Bool? = nil
    }
    private struct Pending: Codable {
        let transition: Transition
        let snapshot: [String: Entry]
    }
    private struct State: Codable {
        var version = 1
        var entries: [String: Entry] = [:]
        var ignoredProjectIDs: Set<UUID> = []
        var pending: Pending?
    }

    let defaults: UserDefaults
    private let persistenceURL: URL?
    private let key = "astra_catalog_feature_modes_v1"

    init(defaults: UserDefaults, persistenceURL: URL? = nil) {
        self.defaults = defaults
        self.persistenceURL = persistenceURL
    }

    var pendingIdentity: String? { (try? load())?.pending?.transition.identity }
    var ignoredProjectIDs: Set<UUID> {
        guard let state = try? load() else { return [] }
        return state.pending?.transition.ignoredProjectIDs ?? state.ignoredProjectIDs
    }
    func projectID(for identity: String) -> UUID? {
        guard let state = try? load() else { return nil }
        if let pending = state.pending {
            if pending.transition.identity == identity { return pending.transition.projectID }
            if let entry = pending.snapshot[identity] { return entry.projectID }
        }
        return state.entries[identity]?.projectID
    }
    /// The durable mode document can reconstruct catalog associations when an
    /// old preference write was lost after a process interruption.
    func associations() -> [String: UUID] {
        guard let state = try? load() else { return [:] }
        var values = state.entries.mapValues(\.projectID)
        if let pending = state.pending {
            for (identity, entry) in pending.snapshot { values[identity] = entry.projectID }
            values[pending.transition.identity] = pending.transition.projectID
        }
        return values
    }
    func isRestoration(_ identity: String) -> Bool? {
        guard let state = try? load() else { return nil }
        if let pending = state.pending {
            if pending.transition.identity == identity { return pending.transition.isRestoration }
            if let entry = pending.snapshot[identity] { return entry.isRestoration }
        }
        return state.entries[identity]?.isRestoration
    }
    func isSuppressed(_ identity: String) -> Bool {
        overrideState(for: identity) == .off
    }
    func requiresActivationRetry(_ identity: String) -> Bool {
        guard let state = try? load() else { return false }
        if state.pending?.transition.identity == identity { return true }
        guard let entry = state.entries[identity] else { return false }
        return entry.isActive && entry.needsActivationRetry == true
    }
    func overrideState(for identity: String) -> PatchApplicationState? {
        guard let state = try? load() else { return .recoveryRequired }
        if let pending = state.pending {
            let transition = pending.transition
            if transition.identity == identity || transition.suppressedIdentities.contains(identity) {
                return .recoveryRequired
            }
        }
        guard let entry = state.entries[identity] else { return nil }
        if !entry.isActive { return .off }
        return entry.needsActivationRetry == true ? .recoveryRequired : nil
    }

    func prepare(identity: String, isRestoration: Bool, candidates: [Candidate]) throws -> Transition {
        guard validIdentity(identity) else { throw CatalogFeatureModeError.invalidState }
        var state = try load()
        if let pending = state.pending {
            guard pending.transition.identity == identity,
                  pending.transition.isRestoration == isRestoration else {
                throw CatalogFeatureModeError.pendingOperation
            }
            // A pending record from older preference-only storage must be
            // written atomically before its interrupted activation may retry.
            try save(state)
            return pending.transition
        }
        var snapshot = state.entries
        var imported = Set<String>()
        for candidate in candidates {
            guard validIdentity(candidate.identity), imported.insert(candidate.identity).inserted else {
                throw CatalogFeatureModeError.invalidState
            }
            if let entry = snapshot[candidate.identity] {
                // Saved OFF overlays win over legacy ON flags, even after a
                // relaunch or a later catalog refresh. Metadata may change role.
                snapshot[candidate.identity] = Entry(projectID: entry.projectID,
                    isRestoration: candidate.isRestoration, isActive: entry.isActive,
                    needsActivationRetry: entry.needsActivationRetry)
            } else {
                snapshot[candidate.identity] = Entry(projectID: candidate.projectID,
                    isRestoration: candidate.isRestoration, isActive: candidate.isActive)
            }
        }
        let suppressed = snapshot.keys.filter { other in
            other != identity && snapshot[other]!.isActive
                && (isRestoration || snapshot[other]!.isRestoration)
        }.sorted()
        var ignored = state.ignoredProjectIDs
        for (other, entry) in snapshot where !entry.isActive || suppressed.contains(other) || other == identity {
            ignored.insert(entry.projectID)
        }
        let transition = Transition(id: UUID(), identity: identity, projectID: UUID(),
            isRestoration: isRestoration, suppressedIdentities: suppressed, ignoredProjectIDs: ignored)
        state.pending = Pending(transition: transition, snapshot: snapshot)
        try save(state)
        return transition
    }

    func commit(_ transition: Transition) throws {
        var state = try load()
        guard let pending = state.pending, pending.transition == transition else {
            throw CatalogFeatureModeError.staleTransition
        }
        var entries = pending.snapshot
        for identity in transition.suppressedIdentities {
            entries[identity]?.isActive = false
        }
        entries[transition.identity] = Entry(projectID: transition.projectID,
            isRestoration: transition.isRestoration, isActive: true)
        state.entries = entries
        state.ignoredProjectIDs = transition.ignoredProjectIDs
        state.pending = nil
        try save(state)
    }

    /// Resolve a failed activation without claiming that its files are restored.
    /// Before I/O the old state can be retained exactly; after possible writes,
    /// keep the selected/affected items as recovery-required, not false OFF.
    func recordFailure(_ transition: Transition, writeMayHaveStarted: Bool) throws {
        var state = try load()
        guard let pending = state.pending, pending.transition == transition else {
            throw CatalogFeatureModeError.staleTransition
        }
        var entries = pending.snapshot
        if writeMayHaveStarted {
            for identity in transition.suppressedIdentities {
                entries[identity]?.needsActivationRetry = true
            }
            if let previous = entries[transition.identity] {
                state.ignoredProjectIDs.insert(previous.projectID)
            }
            entries[transition.identity] = Entry(projectID: transition.projectID,
                isRestoration: transition.isRestoration, isActive: true, needsActivationRetry: true)
        }
        state.entries = entries
        state.pending = nil
        try save(state)
    }

    /// On launch/retry no process from the old activation is still running.
    /// Build-15 intent has no write-progress marker, so reconcile conservatively.
    /// Backup journals are retained; the per-item warning survives re-launch.
    @discardableResult
    func recoverInterruptedActivation() throws -> Transition? {
        guard let transition = try load().pending?.transition else { return nil }
        try recordFailure(transition, writeMayHaveStarted: true)
        return transition
    }

    /// Ending a mode changes catalog state only. It must never replay an old
    /// modifier or remove the transaction's backups underneath the user's files.
    func deactivate(_ identity: String, projectID: UUID? = nil, isRestoration: Bool? = nil) throws {
        var state = try load()
        guard state.pending == nil else { throw CatalogFeatureModeError.pendingOperation }
        guard validIdentity(identity) else { throw CatalogFeatureModeError.invalidState }
        guard let entry = state.entries[identity] ?? projectID.flatMap({ project in
            isRestoration.map { Entry(projectID: project, isRestoration: $0, isActive: false) }
        }) else { return }
        state.entries[identity] = Entry(projectID: entry.projectID,
            isRestoration: entry.isRestoration, isActive: false)
        state.ignoredProjectIDs.insert(entry.projectID)
        try save(state)
    }

    private func validIdentity(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512
            && !value.contains("\0") && !value.contains("\n") && !value.contains("\r")
    }
    private func load() throws -> State {
        let data: Data
        if let persistenceURL, FileManager.default.fileExists(atPath: persistenceURL.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: persistenceURL.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      let size = attributes[.size] as? NSNumber, size.int64Value <= 4 * 1024 * 1024 else {
                    throw CatalogFeatureModeError.invalidState
                }
                data = try Data(contentsOf: persistenceURL)
            } catch { throw CatalogFeatureModeError.invalidState }
        } else {
            guard let object = defaults.object(forKey: key) else { return State() }
            guard let stored = object as? Data else { throw CatalogFeatureModeError.invalidState }
            data = stored
        }
        guard data.count <= 4 * 1024 * 1024,
              let state = try? JSONDecoder().decode(State.self, from: data), state.version == 1,
              state.entries.keys.allSatisfy(validIdentity),
              state.pending.map({ pending in
                  validIdentity(pending.transition.identity)
                      && pending.snapshot.keys.allSatisfy(validIdentity)
                      && Set(pending.transition.suppressedIdentities).count == pending.transition.suppressedIdentities.count
                      && pending.transition.suppressedIdentities.allSatisfy({ pending.snapshot[$0]?.isActive == true })
                      && !pending.transition.suppressedIdentities.contains(pending.transition.identity)
              }) ?? true else { throw CatalogFeatureModeError.invalidState }
        return state
    }
    private func save(_ state: State) throws {
        guard let data = try? JSONEncoder().encode(state), data.count <= 4 * 1024 * 1024 else {
            throw CatalogFeatureModeError.persistenceFailed
        }
        if let persistenceURL {
            do {
                try FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try data.write(to: persistenceURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: persistenceURL.path)
            } catch { throw CatalogFeatureModeError.persistenceFailed }
        }
        defaults.set(data, forKey: key)
        // With a durable file, preferences are a compatibility cache. A lost
        // cache write must never override or invalidate the committed document.
        if persistenceURL == nil, defaults.data(forKey: key) != data {
            throw CatalogFeatureModeError.persistenceFailed
        }
    }
}

enum PatchTransaction {
    private enum Status: String, Codable {
        case prepared
        case applied
        case rolledBack
        case restored
    }

    private struct Record: Codable {
        let ruleID: UUID
        let bundleID: String
        let relativePath: String
        let containerFingerprint: Data
        let originalExisted: Bool
        let backupFilename: String?
        let originalDigest: Data?
        let replacementDigest: Data
        let appliedFilename: String?
    }

    private struct DirectoryRecord: Codable {
        let bundleID: String
        let relativePath: String
        let containerFingerprint: Data
    }

    private struct Journal: Codable {
        let schemaVersion: Int
        let transactionID: UUID
        let projectID: UUID
        let createdAt: Date
        var status: Status
        let records: [Record]
        let createdDirectories: [DirectoryRecord]?
        let engineRecord: PatchEngineApplicationRecord?
    }

    private struct ResolvedRule {
        let rule: PatchRule
        let containerRoot: URL
        let target: URL
    }

    private struct ResolvedDirectory {
        let bundleID: String
        let relativePath: String
        let containerRoot: URL
        let target: URL
    }

    private struct ResolvedRecord {
        let record: Record
        let target: URL
    }

    private struct CurrentFileSnapshot {
        let target: URL
        let existed: Bool
        let snapshotURL: URL?
    }

    private enum AppliedSource {
        case file(URL)
        case data(Data)
    }

    private static let minimumSchemaVersion = 1
    private static let schemaVersion = 3
    private static let journalFilename = "journal.plist"

    /// A catalog mode transition may acknowledge specific older project writes
    /// as superseded. Exclusions affect occupancy only; their journals/backups
    /// remain intact, and callers omitting them retain the normal collision gate.
    static func apply(
        project: PatchProject,
        backupRoot: URL,
        ignoringProjectIDs: Set<UUID> = [],
        engine: PatchWriteEngine = .legacy3105,
        containerResolver: (String) throws -> URL,
        beforeWrite: ((Int) throws -> Void)? = nil,
        beforeProvenanceWrite: (() throws -> Void)? = nil,
        fileManager: FileManager = .default
    ) throws -> PatchTransactionReceipt {
        try DirectPatchExecutionContext.check()
        guard !project.rules.isEmpty || !project.directories.isEmpty else {
            throw PatchPackageError.invalidProject
        }
        guard latestReceipt(
            projectID: project.id,
            backupRoot: backupRoot,
            fileManager: fileManager
        ) == nil else {
            throw PatchPackageError.projectAlreadyApplied
        }

        let engineStore = PatchEngineApplicationStore(backupRoot: backupRoot)
        try engineStore.requireResolvedLegacyHistory()
        let previousEngine = try engineStore.read(project.id)
        let legacyAirLift = UserDefaults.standard.bool(
            forKey: "airlift.applied.\(project.id.uuidString)"
        )
        if previousEngine == nil && legacyAirLift {
            throw PatchEngineStateError.airLiftNoBackup
        }
        let engineTargets = (
            project.rules.map { $0.bundleID + "\0" + $0.relativePath }
                + project.directories.map { $0.bundleID + "\0" + $0.relativePath }
        ).sorted()
        try engineStore.requireNoUnbackedOverlap(
            projectID: project.id,
            targetKeys: engineTargets
        )
        let transactionID = UUID()
        var engineRecord = PatchEngineApplicationRecord(
            projectID: project.id,
            operationID: transactionID,
            engine: engine,
            baseline: .capturedPriorState,
            targetKeys: engineTargets,
            journalID: transactionID
        )
        _ = try PatchEngineApplicationStore.encodedRecord(engineRecord)

        var roots: [String: URL] = [:]
        var resolvedRules: [ResolvedRule] = []
        var resolvedDirectories: [ResolvedDirectory] = []
        var targetKeys = Set<String>()

        func resolvedRoot(for bundleID: String) throws -> URL {
            if let cached = roots[bundleID] { return cached }
            let root = PatchPathValidator.canonicalFileURL(try containerResolver(bundleID))
            roots[bundleID] = root
            return root
        }

        var requestedDirectories = Set<String>()
        for directory in project.directories {
            let bundleID = try PatchPathValidator.canonicalBundleIdentifier(directory.bundleID)
            guard bundleID == directory.bundleID else { throw PatchPackageError.invalidProject }
            requestedDirectories.insert(bundleID + "\0" + directory.relativePath)
        }
        for rule in project.rules {
            let components = try PatchPathValidator.canonicalRelativePath(rule.relativePath)
                .split(separator: "/").map(String.init)
            guard components.count > 1 else { continue }
            for count in 1..<components.count {
                requestedDirectories.insert(
                    rule.bundleID + "\0" + components.prefix(count).joined(separator: "/")
                )
            }
        }

        for key in requestedDirectories.sorted(by: directoryKeySort) {
            let parts = key.split(separator: "\0", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw PatchPackageError.invalidProject }
            let bundleID = try PatchPathValidator.canonicalBundleIdentifier(String(parts[0]))
            let relativePath = try PatchPathValidator.canonicalRelativePath(String(parts[1]))
            let root = try resolvedRoot(for: bundleID)
            let target = try PatchPathValidator.resolveContainedTargetURL(
                relativePath: relativePath,
                containerRoot: root
            )
            try validateDirectoryTarget(
                target,
                relativePath: relativePath,
                containerRoot: root,
                fileManager: fileManager
            )
            resolvedDirectories.append(ResolvedDirectory(
                bundleID: bundleID,
                relativePath: relativePath,
                containerRoot: root,
                target: target
            ))
        }

        for rule in project.rules {
            let bundleID = try PatchPathValidator.canonicalBundleIdentifier(rule.bundleID)
            guard bundleID == rule.bundleID else { throw PatchPackageError.invalidProject }
            let root = try resolvedRoot(for: rule.bundleID)
            let target = try PatchPathValidator.resolveContainedTargetURL(
                relativePath: rule.relativePath,
                containerRoot: root
            )
            let targetKey = target.path
            guard targetKeys.insert(targetKey).inserted else {
                throw PatchPackageError.duplicateTarget
            }
            try validateFileTarget(
                target,
                relativePath: rule.relativePath,
                containerRoot: root,
                allowMissingParents: true,
                fileManager: fileManager
            )
            resolvedRules.append(ResolvedRule(rule: rule, containerRoot: root, target: target))
        }

        let occupied = appliedTargetKeys(
            backupRoot: backupRoot,
            excludingProjectID: project.id,
            excludingProjectIDs: ignoringProjectIDs,
            fileManager: fileManager
        )
        for resolved in resolvedRules {
            let occupancyKey = resolved.rule.bundleID + "\0" + resolved.rule.relativePath
            if occupied.contains(occupancyKey) {
                throw PatchPackageError.targetOccupied(
                    resolved.rule.bundleID + "/" + resolved.rule.relativePath
                )
            }
        }

        let transactionDirectory = backupRoot
            .appendingPathComponent(project.id.uuidString, isDirectory: true)
            .appendingPathComponent(transactionID.uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: transactionDirectory, withIntermediateDirectories: true)
        } catch {
            throw failedApply(error, operation: "backup-directory")
        }

        var records: [Record] = []
        let createdDirectories = resolvedDirectories.compactMap { resolved -> DirectoryRecord? in
            guard !fileManager.fileExists(atPath: resolved.target.path) else { return nil }
            return DirectoryRecord(
                bundleID: resolved.bundleID,
                relativePath: resolved.relativePath,
                containerFingerprint: containerFingerprint(resolved.containerRoot)
            )
        }
        do {
            for resolved in resolvedRules {
                try DirectPatchExecutionContext.check()
                let existed = fileManager.fileExists(atPath: resolved.target.path)
                let backupFilename = existed ? "\(resolved.rule.id.uuidString).original" : nil
                let appliedFilename = project.isPrivate
                    ? nil
                    : "\(resolved.rule.id.uuidString).applied"
                var originalDigest: Data?
                if let backupFilename {
                    let backupURL = transactionDirectory.appendingPathComponent(backupFilename)
                    try fileOperation("backup-copy") {
                        try fileManager.copyItem(at: resolved.target, to: backupURL)
                    }
                    originalDigest = try fileOperation("backup-read") {
                        try digestFile(backupURL)
                    }
                }
                let replacementDigest = digest(resolved.rule.replacementData)
                if let appliedFilename {
                    let appliedURL = transactionDirectory.appendingPathComponent(appliedFilename)
                    try fileOperation("applied-payload-write") {
                        try resolved.rule.replacementData.write(to: appliedURL, options: .atomic)
                    }
                    guard try fileOperation("applied-payload-verify", {
                        try digestFile(appliedURL)
                    }) == replacementDigest else {
                        throw PatchPackageError.applyFailed
                    }
                }
                records.append(Record(
                    ruleID: resolved.rule.id,
                    bundleID: resolved.rule.bundleID,
                    relativePath: resolved.rule.relativePath,
                    containerFingerprint: containerFingerprint(resolved.containerRoot),
                    originalExisted: existed,
                    backupFilename: backupFilename,
                    originalDigest: originalDigest,
                    replacementDigest: replacementDigest,
                    appliedFilename: appliedFilename
                ))
            }
        } catch let error as PatchPackageError {
            throw error
        } catch {
            throw failedApply(error, operation: "backup")
        }

        let journalURL = transactionDirectory.appendingPathComponent(journalFilename)
        var journal = Journal(
            schemaVersion: schemaVersion,
            transactionID: transactionID,
            projectID: project.id,
            createdAt: Date(),
            status: .prepared,
            records: records,
            createdDirectories: createdDirectories,
            engineRecord: engineRecord
        )
        do {
            try writeJournal(journal, to: journalURL)
        } catch {
            throw failedApply(error, operation: "journal-write")
        }

        // The prepared journal already owns the exact provenance. If the
        // mutable project index write is interrupted, it can be reconstructed.
        try fileOperation("provenance-write") {
            try beforeProvenanceWrite?()
            try engineStore.save(engineRecord)
        }

        do {
            for resolved in resolvedDirectories where !fileManager.fileExists(atPath: resolved.target.path) {
                try DirectPatchExecutionContext.check()
                try fileOperation("target-directory-create") {
                    try fileManager.createDirectory(
                        at: resolved.target,
                        withIntermediateDirectories: false
                    )
                }
            }
            for (index, resolved) in resolvedRules.enumerated() {
                try DirectPatchExecutionContext.check()
                try beforeWrite?(index)
                try atomicWrite(
                    resolved.rule.replacementData,
                    to: resolved.target,
                    preservingExistingAttributes: true,
                    fileManager: fileManager
                )
                guard try fileOperation("target-readback", {
                    try digestFile(resolved.target)
                }) == records[index].replacementDigest else {
                    throw PatchPackageError.applyFailed
                }
            }
            try DirectPatchExecutionContext.check()
            journal.status = .applied
            try writeJournal(journal, to: journalURL)
            engineRecord.phase = .applied
            try fileOperation("provenance-write") {
                try engineStore.save(engineRecord)
            }
            return PatchTransactionReceipt(
                id: transactionID,
                projectID: project.id,
                journalURL: journalURL
            )
        } catch {
            var failure = filesystemFailure(error, operation: "transaction-write")
            do {
                try restoreRecords(
                    records,
                    transactionDirectory: transactionDirectory,
                    roots: roots,
                    requirePatchedDigest: false,
                    createdDirectories: createdDirectories,
                    fileManager: fileManager
                )
                journal.status = .rolledBack
                try writeJournal(journal, to: journalURL)
                engineRecord.phase = .restored
                try engineStore.save(engineRecord)
                failure?.rollbackCompleted = true
            } catch {
                // Preserve the prepared journal and backups for explicit recovery.
                if failure == nil {
                    failure = filesystemFailure(error, operation: "rollback")
                }
                engineRecord.phase = .recoveryRequired
                try? engineStore.save(engineRecord)
                failure?.rollbackCompleted = false
            }
            if let failure { throw failure }
            throw PatchPackageError.applyFailed
        }
    }

    static func inspectRestore(
        receipt: PatchTransactionReceipt,
        containerResolver: (String) throws -> URL,
        fileManager: FileManager = .default
    ) throws -> PatchRestoreInspection {
        let backupRoot = receipt.journalURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let store = PatchEngineApplicationStore(backupRoot: backupRoot)
        try PatchEngineApplicationStore.requireDirectRestore(
            record: try store.read(receipt.projectID),
            receiptID: receipt.id,
            journal: try recordedApplicationState(receipt: receipt),
            legacyAirLift: UserDefaults.standard.bool(
                forKey: "airlift.applied.\(receipt.projectID.uuidString)"
            )
        )
        do {
            let journal = try activeJournal(for: receipt)
            guard journal.status == .applied else {
                return PatchRestoreInspection(changedTargets: [])
            }
            let roots = try resolvedRoots(
                journal: journal,
                containerResolver: containerResolver
            )
            let resolved = try resolvedRecords(
                journal.records,
                transactionDirectory: receipt.journalURL.deletingLastPathComponent(),
                roots: roots,
                fileManager: fileManager
            )
            return PatchRestoreInspection(
                changedTargets: try changedTargets(in: resolved, fileManager: fileManager)
            )
        } catch {
            throw PatchPackageError.restoreFailed
        }
    }

    static func restore(
        receipt: PatchTransactionReceipt,
        allowChangedTargets: Bool = false,
        containerResolver: (String) throws -> URL,
        beforeWrite: ((Int) throws -> Void)? = nil,
        fileManager: FileManager = .default
    ) throws {
        let backupRoot = receipt.journalURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let engineStore = PatchEngineApplicationStore(backupRoot: backupRoot)
        let engineRecord = try engineStore.read(receipt.projectID)
        try PatchEngineApplicationStore.requireDirectRestore(
            record: engineRecord,
            receiptID: receipt.id,
            journal: try recordedApplicationState(receipt: receipt),
            legacyAirLift: UserDefaults.standard.bool(
                forKey: "airlift.applied.\(receipt.projectID.uuidString)"
            )
        )
        do {
            var journal = try activeJournal(for: receipt)
            let transactionDirectory = receipt.journalURL.deletingLastPathComponent()
            let roots = try resolvedRoots(
                journal: journal,
                containerResolver: containerResolver
            )
            let resolved = try resolvedRecords(
                journal.records,
                transactionDirectory: transactionDirectory,
                roots: roots,
                allowMissingParents: journal.status == .prepared,
                fileManager: fileManager
            )
            let changes = journal.status == .applied
                ? try changedTargets(in: resolved, fileManager: fileManager)
                : []
            if !changes.isEmpty, !allowChangedTargets {
                throw PatchPackageError.restoreTargetsChanged(changes.map(\.displayPath))
            }
            let createdDirectoryURLs = try resolvedCreatedDirectories(
                journal.createdDirectories ?? [],
                roots: roots,
                fileManager: fileManager
            )

            try withCurrentStateRecovery(
                resolved,
                transactionDirectory: transactionDirectory,
                fileManager: fileManager
            ) {
                for (index, item) in resolved.reversed().enumerated() {
                    try DirectPatchExecutionContext.check()
                    try beforeWrite?(index)
                    if item.record.originalExisted {
                        let backup = transactionDirectory.appendingPathComponent(
                            item.record.backupFilename!
                        )
                        try atomicCopy(backup, to: item.target, fileManager: fileManager)
                    } else if fileManager.fileExists(atPath: item.target.path) {
                        try fileManager.removeItem(at: item.target)
                    }
                }
                try verifyRestoredRecords(resolved)
                try DirectPatchExecutionContext.check()
                journal.status = .restored
                try writeJournal(journal, to: receipt.journalURL)
            }

            removeEmptyCreatedDirectories(createdDirectoryURLs, fileManager: fileManager)
            var restored = engineRecord ?? PatchEngineApplicationRecord(
                projectID: receipt.projectID,
                operationID: receipt.id,
                engine: .legacy3105,
                baseline: .capturedPriorState,
                targetKeys: journal.records.map { $0.bundleID + "\0" + $0.relativePath }
                    + (journal.createdDirectories ?? []).map {
                        $0.bundleID + "\0" + $0.relativePath
                    },
                journalID: receipt.id
            )
            restored.phase = .restored
            try engineStore.save(restored)
        } catch let error as PatchPackageError {
            if case .restoreTargetsChanged = error { throw error }
            throw PatchPackageError.restoreFailed
        } catch {
            throw PatchPackageError.restoreFailed
        }
    }

    static func resetToAppliedState(
        receipt: PatchTransactionReceipt,
        fallbackProject: PatchProject? = nil,
        containerResolver: (String) throws -> URL,
        beforeWrite: ((Int) throws -> Void)? = nil,
        fileManager: FileManager = .default
    ) throws {
        let backupRoot = receipt.journalURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let store = PatchEngineApplicationStore(backupRoot: backupRoot)
        try PatchEngineApplicationStore.requireDirectRestore(
            record: try store.read(receipt.projectID),
            receiptID: receipt.id,
            journal: try recordedApplicationState(receipt: receipt),
            legacyAirLift: UserDefaults.standard.bool(
                forKey: "airlift.applied.\(receipt.projectID.uuidString)"
            )
        )
        do {
            let journal = try activeJournal(for: receipt)
            guard journal.status == .applied else {
                throw PatchPackageError.resetFailed
            }
            let transactionDirectory = receipt.journalURL.deletingLastPathComponent()
            let roots = try resolvedRoots(
                journal: journal,
                containerResolver: containerResolver
            )
            let resolved = try resolvedRecords(
                journal.records,
                transactionDirectory: transactionDirectory,
                roots: roots,
                fileManager: fileManager
            )
            let fallbackRules = Dictionary(
                uniqueKeysWithValues: (fallbackProject?.rules ?? []).map { ($0.id, $0) }
            )
            let sources = try resolved.map { item -> AppliedSource in
                if let filename = item.record.appliedFilename {
                    let source = transactionDirectory.appendingPathComponent(filename)
                    guard fileManager.fileExists(atPath: source.path),
                          try digestFile(source) == item.record.replacementDigest else {
                        throw PatchPackageError.resetFailed
                    }
                    return .file(source)
                }
                guard let rule = fallbackRules[item.record.ruleID],
                      rule.bundleID == item.record.bundleID,
                      rule.relativePath == item.record.relativePath,
                      digest(rule.replacementData) == item.record.replacementDigest else {
                    throw PatchPackageError.resetFailed
                }
                return .data(rule.replacementData)
            }

            try withCurrentStateRecovery(
                resolved,
                transactionDirectory: transactionDirectory,
                fileManager: fileManager
            ) {
                for (index, item) in resolved.enumerated() {
                    try DirectPatchExecutionContext.check()
                    try beforeWrite?(index)
                    switch sources[index] {
                    case .file(let source):
                        try atomicCopy(
                            source,
                            to: item.target,
                            preservingExistingAttributes: true,
                            fileManager: fileManager
                        )
                    case .data(let data):
                        try atomicWrite(
                            data,
                            to: item.target,
                            preservingExistingAttributes: true,
                            fileManager: fileManager
                        )
                    }
                    guard try digestFile(item.target) == item.record.replacementDigest else {
                        throw PatchPackageError.resetFailed
                    }
                }
                try DirectPatchExecutionContext.check()
            }
        } catch {
            throw PatchPackageError.resetFailed
        }
    }

    static func latestReceipt(
        projectID: UUID,
        backupRoot: URL,
        fileManager: FileManager = .default
    ) -> PatchTransactionReceipt? {
        let projectDirectory = backupRoot.appendingPathComponent(projectID.uuidString, isDirectory: true)
        guard let directories = try? fileManager.contentsOfDirectory(
            at: projectDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let validJournals: [(journal: Journal, url: URL)] = directories.compactMap { directory in
            let url = directory.appendingPathComponent(journalFilename)
            guard let journal = try? readJournal(url),
                  (minimumSchemaVersion...schemaVersion).contains(journal.schemaVersion),
                  journal.status == .applied || journal.status == .prepared else { return nil }
            return (journal, url)
        }

        guard let latest = validJournals.sorted(by: { $0.journal.createdAt > $1.journal.createdAt }).first else {
            return nil
        }

        return PatchTransactionReceipt(
            id: latest.journal.transactionID,
            projectID: latest.journal.projectID,
            journalURL: latest.url
        )
    }

    static func recordedApplicationState(receipt: PatchTransactionReceipt) throws -> PatchApplicationState {
        let journal = try activeJournal(for: receipt)
        return journal.status == .applied ? .applied : .recoveryRequired
    }

    static func latestRecordedApplicationState(projectID: UUID, backupRoot: URL,
                                               fileManager: FileManager = .default) -> PatchApplicationState? {
        let directory = backupRoot.appendingPathComponent(projectID.uuidString, isDirectory: true)
        guard let transactions = try? fileManager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        let journals = transactions.compactMap { transaction -> Journal? in
            guard let journal = try? readJournal(transaction.appendingPathComponent(journalFilename)),
                  (minimumSchemaVersion...schemaVersion).contains(journal.schemaVersion),
                  journal.projectID == projectID, transaction.lastPathComponent == journal.transactionID.uuidString else { return nil }
            return journal
        }
        guard let journal = journals.max(by: { $0.createdAt < $1.createdAt }) else { return nil }
        switch journal.status {
        case .applied: return .applied
        case .prepared: return .recoveryRequired
        case .restored, .rolledBack: return .off
        }
    }

    /// Adopt a previous successful write without overwriting its original
    /// backup. A pending, changed or different release requires explicit restore.
    static func inspectExistingApplication(
        receipt: PatchTransactionReceipt,
        project: PatchProject,
        containerResolver: (String) throws -> URL,
        fileManager: FileManager = .default
    ) throws -> PatchApplicationState {
        let journal = try activeJournal(for: receipt)
        guard project.id == journal.projectID else { throw PatchPackageError.invalidProject }
        guard journal.status == .applied, journal.records.count == project.rules.count,
              Set(project.rules.map(\.id)).count == project.rules.count else { return .recoveryRequired }
        let rules = Dictionary(uniqueKeysWithValues: project.rules.map { ($0.id, $0) })
        guard journal.records.allSatisfy({ record in
            guard let rule = rules[record.ruleID] else { return false }
            return rule.bundleID == record.bundleID && rule.relativePath == record.relativePath
                && digest(rule.replacementData) == record.replacementDigest
        }) else { return .recoveryRequired }
        let roots = try resolvedRoots(journal: journal, containerResolver: containerResolver)
        let records = try resolvedRecords(journal.records, transactionDirectory: receipt.journalURL.deletingLastPathComponent(),
            roots: roots, fileManager: fileManager)
        return try changedTargets(in: records, fileManager: fileManager).isEmpty ? .applied : .recoveryRequired
    }

    static func appliedTargetKeys(
        backupRoot: URL,
        excludingProjectID: UUID? = nil,
        excludingProjectIDs: Set<UUID> = [],
        fileManager: FileManager = .default
    ) -> Set<String> {
        guard let projectDirectories = try? fileManager.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var keys = Set<String>()
        for directory in projectDirectories {
            guard let projectID = UUID(uuidString: directory.lastPathComponent),
                  projectID != excludingProjectID,
                  !excludingProjectIDs.contains(projectID),
                  let receipt = latestReceipt(
                    projectID: projectID,
                    backupRoot: backupRoot,
                    fileManager: fileManager
                  ),
                  let journal = try? readJournal(receipt.journalURL),
                  journal.status == .applied || journal.status == .prepared
            else { continue }
            for record in journal.records {
                keys.insert(record.bundleID + "\0" + record.relativePath)
            }
        }
        return keys
    }

    static func requiredBundleIdentifiers(for receipt: PatchTransactionReceipt) throws -> [String] {
        let journal = try readJournal(receipt.journalURL)
        guard (minimumSchemaVersion...schemaVersion).contains(journal.schemaVersion),
              journal.transactionID == receipt.id,
              journal.projectID == receipt.projectID else {
            throw PatchPackageError.restoreFailed
        }
        var seen = Set<String>()
        return (journal.records.map(\.bundleID) + (journal.createdDirectories ?? []).map(\.bundleID))
            .filter { seen.insert($0).inserted }
    }

    private static func activeJournal(for receipt: PatchTransactionReceipt) throws -> Journal {
        let journal = try readJournal(receipt.journalURL)
        guard (minimumSchemaVersion...schemaVersion).contains(journal.schemaVersion),
              journal.transactionID == receipt.id,
              journal.projectID == receipt.projectID,
              journal.status == .applied || journal.status == .prepared else {
            throw PatchPackageError.restoreFailed
        }
        return journal
    }

    private static func resolvedRoots(
        journal: Journal,
        containerResolver: (String) throws -> URL
    ) throws -> [String: URL] {
        var roots: [String: URL] = [:]
        let identities = journal.records.map { ($0.bundleID, $0.containerFingerprint) }
            + (journal.createdDirectories ?? []).map { ($0.bundleID, $0.containerFingerprint) }
        for (bundleID, expectedFingerprint) in identities {
            if let root = roots[bundleID] {
                guard containerFingerprint(root) == expectedFingerprint else {
                    throw PatchPackageError.restoreFailed
                }
                continue
            }
            let root = PatchPathValidator.canonicalFileURL(try containerResolver(bundleID))
            guard containerFingerprint(root) == expectedFingerprint else {
                throw PatchPackageError.restoreFailed
            }
            roots[bundleID] = root
        }
        return roots
    }

    private static func resolvedRecords(
        _ records: [Record],
        transactionDirectory: URL,
        roots: [String: URL],
        allowMissingParents: Bool = false,
        fileManager: FileManager
    ) throws -> [ResolvedRecord] {
        try records.map { record in
            guard let root = roots[record.bundleID],
                  containerFingerprint(root) == record.containerFingerprint else {
                throw PatchPackageError.restoreFailed
            }
            let target = try PatchPathValidator.resolveContainedTargetURL(
                relativePath: record.relativePath,
                containerRoot: root
            )
            try validateFileTarget(
                target,
                relativePath: record.relativePath,
                containerRoot: root,
                allowMissingParents: allowMissingParents,
                fileManager: fileManager
            )
            if record.originalExisted {
                guard let backupFilename = record.backupFilename,
                      let expectedDigest = record.originalDigest else {
                    throw PatchPackageError.restoreFailed
                }
                let backup = transactionDirectory.appendingPathComponent(backupFilename)
                guard fileManager.fileExists(atPath: backup.path),
                      try digestFile(backup) == expectedDigest else {
                    throw PatchPackageError.restoreFailed
                }
            }
            return ResolvedRecord(record: record, target: target)
        }
    }

    private static func changedTargets(
        in resolved: [ResolvedRecord],
        fileManager: FileManager
    ) throws -> [PatchTargetChange] {
        try resolved.compactMap { item in
            guard fileManager.fileExists(atPath: item.target.path) else {
                return PatchTargetChange(
                    bundleID: item.record.bundleID,
                    relativePath: item.record.relativePath,
                    kind: .missing
                )
            }
            guard try digestFile(item.target) != item.record.replacementDigest else {
                return nil
            }
            return PatchTargetChange(
                bundleID: item.record.bundleID,
                relativePath: item.record.relativePath,
                kind: .modified
            )
        }
    }

    private static func resolvedCreatedDirectories(
        _ directories: [DirectoryRecord],
        roots: [String: URL],
        fileManager: FileManager
    ) throws -> [URL] {
        try directories.map { directory in
            guard let root = roots[directory.bundleID],
                  containerFingerprint(root) == directory.containerFingerprint else {
                throw PatchPackageError.restoreFailed
            }
            let target = try PatchPathValidator.resolveContainedTargetURL(
                relativePath: directory.relativePath,
                containerRoot: root
            )
            if fileManager.fileExists(atPath: target.path) {
                let values = try target.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                guard values.isSymbolicLink != true, values.isDirectory == true else {
                    throw PatchPackageError.restoreFailed
                }
            }
            return target
        }
    }

    private static func withCurrentStateRecovery(
        _ resolved: [ResolvedRecord],
        transactionDirectory: URL,
        fileManager: FileManager,
        operation: () throws -> Void
    ) throws {
        let recoveryDirectory = transactionDirectory.appendingPathComponent(
            ".recovery-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: recoveryDirectory, withIntermediateDirectories: false)
        var snapshots: [CurrentFileSnapshot] = []
        do {
            for (index, item) in resolved.enumerated() {
                guard fileManager.fileExists(atPath: item.target.path) else {
                    snapshots.append(CurrentFileSnapshot(
                        target: item.target,
                        existed: false,
                        snapshotURL: nil
                    ))
                    continue
                }
                let snapshotURL = recoveryDirectory.appendingPathComponent("\(index).current")
                try fileManager.copyItem(at: item.target, to: snapshotURL)
                guard try digestFile(snapshotURL) == digestFile(item.target) else {
                    throw PatchPackageError.restoreFailed
                }
                snapshots.append(CurrentFileSnapshot(
                    target: item.target,
                    existed: true,
                    snapshotURL: snapshotURL
                ))
            }
        } catch {
            try? fileManager.removeItem(at: recoveryDirectory)
            throw error
        }

        do {
            try operation()
        } catch {
            do {
                for snapshot in snapshots.reversed() {
                    if snapshot.existed, let snapshotURL = snapshot.snapshotURL {
                        try atomicCopy(snapshotURL, to: snapshot.target, fileManager: fileManager)
                    } else if fileManager.fileExists(atPath: snapshot.target.path) {
                        try fileManager.removeItem(at: snapshot.target)
                    }
                }
                try? fileManager.removeItem(at: recoveryDirectory)
            } catch {
                // Keep the recovery directory when rollback cannot complete.
                throw PatchPackageError.restoreFailed
            }
            throw error
        }
        try? fileManager.removeItem(at: recoveryDirectory)
    }

    private static func removeEmptyCreatedDirectories(
        _ directories: [URL],
        fileManager: FileManager
    ) {
        for directory in directories.reversed() {
            guard fileManager.fileExists(atPath: directory.path),
                  let values = try? directory.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                  ),
                  values.isSymbolicLink != true,
                  values.isDirectory == true,
                  let contents = try? fileManager.contentsOfDirectory(atPath: directory.path),
                  contents.isEmpty else { continue }
            try? fileManager.removeItem(at: directory)
        }
    }

    private static func verifyRestoredRecords(_ resolved: [ResolvedRecord]) throws {
        for item in resolved {
            var info = stat()
            let result = item.target.path.withCString { lstat($0, &info) }
            if item.record.originalExisted {
                guard result == 0,
                      (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
                      let expected = item.record.originalDigest,
                      try fileOperation("restore-target-readback", {
                          try digestFile(item.target)
                      }) == expected else {
                    throw PatchPackageError.restoreFailed
                }
            } else {
                guard result < 0, errno == ENOENT else {
                    throw PatchPackageError.restoreFailed
                }
            }
        }
    }

    private static func restoreRecords(
        _ records: [Record],
        transactionDirectory: URL,
        roots: [String: URL],
        requirePatchedDigest: Bool,
        createdDirectories: [DirectoryRecord],
        fileManager: FileManager
    ) throws {
        var createdDirectoryURLs: [URL] = []
        for directory in createdDirectories {
            guard let root = roots[directory.bundleID],
                  containerFingerprint(root) == directory.containerFingerprint else {
                throw PatchPackageError.restoreFailed
            }
            let target = try PatchPathValidator.resolveContainedTargetURL(
                relativePath: directory.relativePath,
                containerRoot: root
            )
            if fileManager.fileExists(atPath: target.path) {
                let values = try target.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                guard values.isSymbolicLink != true, values.isDirectory == true else {
                    throw PatchPackageError.restoreFailed
                }
            }
            createdDirectoryURLs.append(target)
        }

        var restored: [ResolvedRecord] = []
        for record in records.reversed() {
            guard let root = roots[record.bundleID],
                  containerFingerprint(root) == record.containerFingerprint else {
                throw PatchPackageError.restoreFailed
            }
            let target = try PatchPathValidator.resolveContainedTargetURL(
                relativePath: record.relativePath,
                containerRoot: root
            )
            try validateFileTarget(
                target,
                relativePath: record.relativePath,
                containerRoot: root,
                allowMissingParents: true,
                fileManager: fileManager
            )

            if record.originalExisted {
                guard let backupFilename = record.backupFilename,
                      let expectedDigest = record.originalDigest else {
                    throw PatchPackageError.restoreFailed
                }
                let backup = transactionDirectory.appendingPathComponent(backupFilename)
                guard fileManager.fileExists(atPath: backup.path),
                      try digestFile(backup) == expectedDigest else {
                    throw PatchPackageError.restoreFailed
                }
                if requirePatchedDigest {
                    guard fileManager.fileExists(atPath: target.path),
                          try digestFile(target) == record.replacementDigest else {
                        throw PatchPackageError.restoreFailed
                    }
                }
                try atomicCopy(backup, to: target, fileManager: fileManager)
            } else {
                if requirePatchedDigest {
                    guard fileManager.fileExists(atPath: target.path),
                          try digestFile(target) == record.replacementDigest else {
                        throw PatchPackageError.restoreFailed
                    }
                }
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
            }
            restored.append(ResolvedRecord(record: record, target: target))
        }
        try verifyRestoredRecords(restored)

        for directory in createdDirectoryURLs.reversed() {
            guard fileManager.fileExists(atPath: directory.path),
                  let values = try? directory.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                  ),
                  values.isSymbolicLink != true,
                  values.isDirectory == true,
                  let contents = try? fileManager.contentsOfDirectory(atPath: directory.path),
                  contents.isEmpty else { continue }
            try? fileManager.removeItem(at: directory)
        }
    }

    private static func validateFileTarget(
        _ target: URL,
        relativePath: String,
        containerRoot: URL,
        allowMissingParents: Bool,
        fileManager: FileManager
    ) throws {
        let components = try PatchPathValidator.canonicalRelativePath(relativePath)
            .split(separator: "/")
            .map(String.init)
        var cursor = PatchPathValidator.canonicalFileURL(containerRoot)
        for component in components.dropLast() {
            cursor.appendPathComponent(component, isDirectory: true)
            guard fileManager.fileExists(atPath: cursor.path) else {
                if allowMissingParents { break }
                throw PatchPackageError.applyFailed
            }
            let values = try cursor.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw PatchPackageError.symbolicLinkUnsupported
            }
            guard values.isDirectory == true else {
                throw PatchPackageError.applyFailed
            }
        }
        if fileManager.fileExists(atPath: target.path) {
            let values = try target.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw PatchPackageError.symbolicLinkUnsupported
            }
            guard values.isDirectory != true else {
                throw PatchPackageError.applyFailed
            }
        }
    }

    private static func validateDirectoryTarget(
        _ target: URL,
        relativePath: String,
        containerRoot: URL,
        fileManager: FileManager
    ) throws {
        let components = try PatchPathValidator.canonicalRelativePath(relativePath)
            .split(separator: "/").map(String.init)
        var cursor = PatchPathValidator.canonicalFileURL(containerRoot)
        for component in components {
            cursor.appendPathComponent(component, isDirectory: true)
            guard fileManager.fileExists(atPath: cursor.path) else { break }
            let values = try cursor.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw PatchPackageError.symbolicLinkUnsupported
            }
            guard values.isDirectory == true else {
                throw PatchPackageError.applyFailed
            }
        }
        if fileManager.fileExists(atPath: target.path) {
            let values = try target.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, values.isDirectory == true else {
                throw PatchPackageError.applyFailed
            }
        }
    }

    private static func directoryKeySort(_ lhs: String, _ rhs: String) -> Bool {
        let leftDepth = lhs.filter { $0 == "/" }.count
        let rightDepth = rhs.filter { $0 == "/" }.count
        return leftDepth == rightDepth ? lhs < rhs : leftDepth < rightDepth
    }

    private static func atomicWrite(
        _ data: Data,
        to target: URL,
        preservingExistingAttributes: Bool,
        fileManager: FileManager
    ) throws {
        let staging = target.deletingLastPathComponent()
            .appendingPathComponent(".3105-patch-\(UUID().uuidString)")
        var attributes: [FileAttributeKey: Any] = [:]
        if preservingExistingAttributes,
           let current = try? fileManager.attributesOfItem(atPath: target.path) {
            if let permissions = current[.posixPermissions] { attributes[.posixPermissions] = permissions }
            if let protection = current[.protectionKey] { attributes[.protectionKey] = protection }
        }
        let created = try createWritableStage(staging)
        var descriptor = created.descriptor
        defer {
            if descriptor >= 0 { close(descriptor) }
            try? fileManager.removeItem(at: staging)
        }
        if attributes[.posixPermissions] == nil {
            attributes[.posixPermissions] = NSNumber(value: Int(created.defaultPermissions))
        }
        try fileOperation("staging-write") { try writeAll(data, to: descriptor) }
        // Keep the writable descriptor open even when final metadata makes the
        // stage read-only. Reopening a 0444 stage would fail before fsync.
        if !attributes.isEmpty {
            try fileOperation("staging-attributes") {
                try fileManager.setAttributes(attributes, ofItemAtPath: staging.path)
            }
        }
        try synchronizeAndClose(&descriptor)
        try commitStage(staging, to: target)
    }

    private static func atomicCopy(
        _ source: URL,
        to target: URL,
        preservingExistingAttributes: Bool = false,
        fileManager: FileManager
    ) throws {
        let staging = target.deletingLastPathComponent()
            .appendingPathComponent(".3105-restore-\(UUID().uuidString)")
        var descriptor = try createWritableStage(staging).descriptor
        defer {
            if descriptor >= 0 { close(descriptor) }
            try? fileManager.removeItem(at: staging)
        }
        try fileOperation("restore-stage-copy") {
            let sourceDescriptor = open(source.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            guard sourceDescriptor >= 0 else { throw posixFailure() }
            defer { close(sourceDescriptor) }
#if canImport(Darwin)
            guard fcopyfile(
                sourceDescriptor,
                descriptor,
                nil,
                copyfile_flags_t(COPYFILE_ALL)
            ) == 0 else { throw posixFailure() }
#else
            var buffer = [UInt8](repeating: 0, count: 1_024 * 1_024)
            while true {
                let count = read(sourceDescriptor, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                guard count >= 0 else { throw posixFailure() }
                if count == 0 { break }
                try writeAll(Data(buffer.prefix(count)), to: descriptor)
            }
            let copied = try fileManager.attributesOfItem(atPath: source.path)
            var metadata: [FileAttributeKey: Any] = [:]
            for key in [FileAttributeKey.posixPermissions, .creationDate, .modificationDate] {
                if let value = copied[key] { metadata[key] = value }
            }
            try fileManager.setAttributes(metadata, ofItemAtPath: staging.path)
#endif
        }
        if preservingExistingAttributes,
           let current = try? fileManager.attributesOfItem(atPath: target.path) {
            var attributes: [FileAttributeKey: Any] = [:]
            if let permissions = current[.posixPermissions] {
                attributes[.posixPermissions] = permissions
            }
            if let protection = current[.protectionKey] {
                attributes[.protectionKey] = protection
            }
            if !attributes.isEmpty {
                try fileOperation("restore-stage-attributes") {
                    try fileManager.setAttributes(attributes, ofItemAtPath: staging.path)
                }
            }
        }
        try synchronizeAndClose(&descriptor)
        try commitStage(staging, to: target)
    }

    private static func createWritableStage(
        _ staging: URL
    ) throws -> (descriptor: Int32, defaultPermissions: mode_t) {
        try fileOperation("staging-create") {
            let descriptor = open(
                staging.path,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode_t(0o666)
            )
            guard descriptor >= 0 else { throw posixFailure() }
            do {
                var metadata = stat()
                try fileOperation("staging-stat") {
                    guard fstat(descriptor, &metadata) == 0 else { throw posixFailure() }
                }
                try fileOperation("staging-private-mode") {
                    guard fchmod(descriptor, mode_t(0o600)) == 0 else { throw posixFailure() }
                }
                return (descriptor, mode_t(metadata.st_mode & 0o7777))
            } catch {
                close(descriptor)
                unlink(staging.path)
                throw error
            }
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = write(
                    descriptor,
                    base.advanced(by: offset),
                    buffer.count - offset
                )
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else {
                    throw posixFailure(count == 0 ? EIO : errno)
                }
                offset += count
            }
        }
    }

    private static func synchronizeAndClose(_ descriptor: inout Int32) throws {
        try fileOperation("staging-sync") {
            while fsync(descriptor) != 0 {
                if errno == EINTR { continue }
                throw posixFailure()
            }
        }
        let current = descriptor
        descriptor = -1
        try fileOperation("staging-close") {
            guard close(current) == 0 else { throw posixFailure() }
        }
    }

    private static func commitStage(_ staging: URL, to target: URL) throws {
        try fileOperation("target-rename") {
            guard rename(staging.path, target.path) == 0 else { throw posixFailure() }
        }
    }

    private static func posixFailure(_ code: Int32 = errno) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: nil)
    }

    private static func filesystemFailure(
        _ error: Error,
        operation: String
    ) -> PatchFilesystemFailure? {
        if let known = error as? PatchFilesystemFailure { return known }
        let underlying = error as NSError
        guard underlying.domain == NSPOSIXErrorDomain ||
            (underlying.domain == NSCocoaErrorDomain &&
                (underlying.code == NSFileNoSuchFileError ||
                    underlying.code == NSFileLockingError ||
                    (256...1023).contains(underlying.code))) else { return nil }
        return PatchFilesystemFailure(operation: operation, underlying: underlying)
    }

    private static func failedApply(_ error: Error, operation: String) -> Error {
        if let failure = filesystemFailure(error, operation: operation) { return failure }
        return PatchPackageError.applyFailed
    }

    private static func fileOperation<T>(
        _ operation: String,
        _ work: () throws -> T
    ) throws -> T {
        do {
            return try work()
        } catch {
            if let failure = filesystemFailure(error, operation: operation) {
                throw failure
            }
            throw error
        }
    }

    private static func writeJournal(_ journal: Journal, to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(journal)
        guard data.count <= PatchEngineApplicationStore.maximumJournalBytes else {
            throw PatchEngineStateError.invalidRecord
        }
        try fileOperation("journal-write") {
            try data.write(to: url, options: .atomic)
        }
    }

    private static func readJournal(_ url: URL) throws -> Journal {
        let data = try Data(contentsOf: url)
        guard data.count <= PatchEngineApplicationStore.maximumJournalBytes else {
            throw PatchEngineStateError.invalidRecord
        }
        return try PropertyListDecoder().decode(Journal.self, from: data)
    }

    private static func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private static func digestFile(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_024 * 1_024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize())
    }

    private static func containerFingerprint(_ url: URL) -> Data {
        digest(Data(PatchPathValidator.canonicalFileURL(url).path.utf8))
    }
}

// MARK: - Device Patch Service

enum DevicePatchService {
    static func activeTargetKeys() throws -> Set<String> {
        PatchTransaction.appliedTargetKeys(
            backupRoot: try PatchProjectLibrary.backupRootURL(),
            excludingProjectID: nil
        )
    }

    static func prepareContainers(bundleIDs: [String]) async throws -> [String: URL] {
        if ExploitSupportPolicy.currentAccessProvider == .worseQuery {
            try await IOS27ContainerPreparation.shared.prepareAdditionalTargets(
                bundleIDs: bundleIDs
            )
        }
        let work = Task.detached(priority: .userInitiated) {
            var roots: [String: URL] = [:]
            for bundleID in bundleIDs {
                try Task.checkCancellation()
                let path = try ContainerStore.resolveAppContainerForPatch(bundleID: bundleID)
                guard ContainerStore.isApplicationContainerPath(path) else {
                    throw PatchPackageError.targetAppUnavailable(bundleID)
                }
                roots[bundleID] = URL(fileURLWithPath: path, isDirectory: true)
            }
            return roots
        }
        return try await withTaskCancellationHandler(
            operation: { try await work.value },
            onCancel: { work.cancel() }
        )
    }

    static func prepareContainers(
        receipt: PatchTransactionReceipt
    ) async throws -> [String: URL] {
        try await prepareContainers(
            bundleIDs: PatchTransaction.requiredBundleIdentifiers(for: receipt)
        )
    }

    static func recordedApplicationState(projectID: UUID) -> PatchApplicationState? {
        guard let root = try? PatchProjectLibrary.backupRootURL() else { return nil }
        return PatchTransaction.latestRecordedApplicationState(projectID: projectID, backupRoot: root)
    }

    static func inspectExistingApplication(
        receipt: PatchTransactionReceipt,
        project: PatchProject,
        preparedContainers: [String: URL]? = nil
    ) throws -> PatchApplicationState {
        try withResolvedContainers(
            bundleIDs: project.allBundleIdentifiers,
            prepared: preparedContainers
        ) { roots in
            try PatchTransaction.inspectExistingApplication(receipt: receipt, project: project, containerResolver: { bundleID in
                guard let root = roots[bundleID] else { throw PatchPackageError.targetAppUnavailable(bundleID) }
                return root
            })
        }
    }

    static func apply(
        project: PatchProject,
        ignoringProjectIDs: Set<UUID> = [],
        preparedContainers: [String: URL]? = nil
    ) throws -> PatchTransactionReceipt {
        let bundleIDs = orderedBundleIdentifiers(in: project)
        return try withResolvedContainers(
            bundleIDs: bundleIDs,
            prepared: preparedContainers
        ) { roots in
            try PatchTransaction.apply(
                project: project,
                backupRoot: try PatchProjectLibrary.backupRootURL(),
                ignoringProjectIDs: ignoringProjectIDs,
                engine: WorseQueryHelper.isAvailable ? .worseQuery : .legacy3105,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func inspectRestore(
        receipt: PatchTransactionReceipt,
        preparedContainers: [String: URL]? = nil
    ) throws -> PatchRestoreInspection {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        return try withResolvedContainers(
            bundleIDs: bundleIDs,
            prepared: preparedContainers
        ) { roots in
            try PatchTransaction.inspectRestore(
                receipt: receipt,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func restore(
        receipt: PatchTransactionReceipt,
        allowChangedTargets: Bool = false,
        preparedContainers: [String: URL]? = nil
    ) throws {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        try withResolvedContainers(
            bundleIDs: bundleIDs,
            prepared: preparedContainers
        ) { roots in
            try PatchTransaction.restore(
                receipt: receipt,
                allowChangedTargets: allowChangedTargets,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func resetToAppliedState(
        receipt: PatchTransactionReceipt,
        project: PatchProject
    ) throws {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.resetToAppliedState(
                receipt: receipt,
                fallbackProject: project,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func latestReceipt(projectID: UUID) -> PatchTransactionReceipt? {
        guard let backupRoot = try? PatchProjectLibrary.backupRootURL() else { return nil }
        return PatchTransaction.latestReceipt(projectID: projectID, backupRoot: backupRoot)
    }

    private static func orderedBundleIdentifiers(in project: PatchProject) -> [String] {
        project.allBundleIdentifiers
    }

    private static func withResolvedContainers<T>(
        bundleIDs: [String],
        prepared: [String: URL]? = nil,
        operation: ([String: URL]) throws -> T
    ) throws -> T {
        var roots: [String: URL] = [:]
        var handles: [Int64] = []
        defer {
            handles.reversed().forEach { sandbox_extension_release_handle($0) }
        }

        for bundleID in bundleIDs {
            try DirectPatchExecutionContext.check()
            let path: String
            if let prepared {
                guard let root = prepared[bundleID] else {
                    throw PatchPackageError.targetAppUnavailable(bundleID)
                }
                path = root.path
            } else {
                path = try ContainerStore.resolveAppContainerForPatch(bundleID: bundleID)
            }
            guard ContainerStore.isApplicationContainerPath(path) else {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            if WorseQueryHelper.isAvailable {
                handles.append(try WorseQueryHelper.acquireAccess(for: path))
            } else {
                guard ExploitSupportPolicy.currentAccessProvider == .legacy3105 else {
                    throw WorseQueryError.appGroupUnavailable
                }
                let handle = ContainerStore.grantContainerAccess(path)
                if handle >= 0 { handles.append(handle) }
            }
            roots[bundleID] = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: path, isDirectory: true))
        }
        return try operation(roots)
    }
}
