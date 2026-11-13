//
//  StorageEngineCoordinator.swift
//  ThreeOneOSFive
//
//  Created by Astra AirLift Integration on 03/10/2026.
//  Coordinates dual-engine I/O: Direct/Kernel Exploit vs AirLift Loopback.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class StorageEngineCoordinator: ObservableObject {
    static let shared = StorageEngineCoordinator()

    /// AirliftFFI is statically linked into the application target. Runtime
    /// operations still fail closed unless tunnel, pairing and canary checks pass.
    let isAirTrafficEngineLinked = true

    @AppStorage("useAirLiftForAll") var useAirLiftForAll: Bool = false {
        didSet {
            let required = ExploitSupportPolicy.currentStorageMode == .airLift
            guard useAirLiftForAll == required else {
                useAirLiftForAll = required
                return
            }
            objectWillChange.send()
            guard isAirLiftActive else { return }
            AirTrafficProtocolClient.shared.resetSession()
            if useAirLiftForAll {
                Task {
                    _ = await AirTrafficProtocolClient.shared.checkRealAirLiftHealth()
                }
            }
        }
    }

    var isAirLiftActive: Bool {
        ExploitSupportPolicy.currentStorageMode == .airLift
    }

    private init() {
        let required = ExploitSupportPolicy.currentStorageMode == .airLift
        if useAirLiftForAll != required {
            useAirLiftForAll = required
        }
    }

    private func airLiftAppliedKey(_ projectID: UUID) -> String {
        "airlift.applied.\(projectID.uuidString)"
    }

    func isProjectAppliedThroughAirLift(_ projectID: UUID) -> Bool {
        do {
            if let record = try applicationStore().read(projectID) {
                return record.engine == .airLift && record.phase != .restored
            }
        } catch { return true } // Unknown provenance must not become OFF.
        return UserDefaults.standard.bool(forKey: airLiftAppliedKey(projectID))
    }

    func applicationStore() throws -> PatchEngineApplicationStore {
        PatchEngineApplicationStore(backupRoot: try PatchProjectLibrary.backupRootURL())
    }

    func projectApplicationState(_ projectID: UUID) -> PatchApplicationState? {
        do {
            return PatchEngineApplicationStore.reconcile(record: try applicationStore().read(projectID),
                journal: DevicePatchService.recordedApplicationState(projectID: projectID),
                legacyAirLift: UserDefaults.standard.bool(forKey: airLiftAppliedKey(projectID)))
        } catch { return .recoveryRequired }
    }

    /// Writes or replaces a file in the destination path using the optimal engine.
    func writeFile(data: Data, toPath destinationPath: String) async throws {
        try await withExclusivePatchOperation { operationID in
            try await self.writeFileInOperation(data: data, toPath: destinationPath, operationID: operationID)
        }
    }

    func writeFileInOperation(data: Data, toPath destinationPath: String, operationID: UUID) async throws {
        try await PatchFilesystemGate.shared.validate(operationID)
        try await AppIntegrityRuntime.shared.requireAllowed(force:true)
        let networkGeneration = try await NetworkAccessGate.shared.requireAllowed()
        try Task.checkCancellation()
        try NetworkAccessGate.shared.validateGeneration(networkGeneration)

        // 1. Ưu tiên ghi trực tiếp qua WorseQuery trên thiết bị (Không cần pairing máy tính)
        guard ExploitSupportPolicy.currentStorageMode != .unsupported else {
            throw WorseQueryError.unsupportedOS(AppInfo.osBuild)
        }
        if ExploitSupportPolicy.currentAccessProvider == .worseQuery {
            guard WorseQueryHelper.isScopeSupported(for: destinationPath) else { throw WorseQueryError.invalidPath(destinationPath) }
            guard WorseQueryHelper.isAvailable else { throw WorseQueryError.appGroupUnavailable }
            log("storage: routing write via on-device WorseQuery provider for \(destinationPath)")
            try await DirectPatchExecutor.run(validation: { try NetworkAccessGate.shared.validateGeneration(networkGeneration) }) {
                try IntegrityCommitBarrier.withCommit {
                    try WorseQueryHelper.writeFile(data: data, to: destinationPath)
                }
            }
            return
        }

        if isAirLiftActive {
            guard isAirTrafficEngineLinked else {
                throw AirLiftError.executionFailed("AirTraffic engine chưa được liên kết; thao tác ghi đã bị chặn an toàn.")
            }
            log("storage: routing write via AirLift provider for \(destinationPath)")
            do {
                try await AirTrafficProtocolClient.shared.writeFile(data: data, targetPath: destinationPath)
            } catch {
                if let airLiftError = error as? AirLiftError, airLiftError.requiresRePairing {
                    AirLiftGatekeeperManager.shared.triggerRePair(reason: "Pairing AirLift không còn hợp lệ: \(airLiftError.localizedDescription)")
                }
                throw error
            }
        } else {
            log("storage: routing write via Direct/Kernel provider for \(destinationPath)")
            let url = URL(fileURLWithPath: destinationPath)
            try await DirectPatchExecutor.run(validation: { try NetworkAccessGate.shared.validateGeneration(networkGeneration) }) {
                let handle = ContainerStore.grantContainerAccess(destinationPath)
                defer { if handle >= 0 { sandbox_extension_release_handle(handle) } }
                let parent = url.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: parent.path) {
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                try IntegrityCommitBarrier.withCommit { try data.write(to:url,options:.atomic) }
            }
        }
    }

    /// Reads a file from a path using the optimal engine.
    func readFile(atPath path: String) async throws -> Data {
        // 1. Ưu tiên đọc trực tiếp qua WorseQuery trên thiết bị
        guard ExploitSupportPolicy.currentStorageMode != .unsupported else {
            throw WorseQueryError.unsupportedOS(AppInfo.osBuild)
        }
        if ExploitSupportPolicy.currentAccessProvider == .worseQuery {
            guard WorseQueryHelper.isScopeSupported(for: path) else { throw WorseQueryError.invalidPath(path) }
            guard WorseQueryHelper.isAvailable else { throw WorseQueryError.appGroupUnavailable }
            log("storage: routing read via on-device WorseQuery provider for \(path)")
            return try await DirectPatchExecutor.run(validation: {}) { try WorseQueryHelper.readFile(at: path) }
        }
        if isAirLiftActive {
            guard isAirTrafficEngineLinked else {
                throw AirLiftError.executionFailed("AirTraffic engine chưa được liên kết; thao tác đọc đã bị chặn an toàn.")
            }
            return try await AirTrafficProtocolClient.shared.readFile(at: path)
        } else {
            return try await DirectPatchExecutor.run(validation: {}) {
                let handle = ContainerStore.grantContainerAccess(path)
                defer { if handle >= 0 { sandbox_extension_release_handle(handle) } }
                return try Data(contentsOf: URL(fileURLWithPath: path))
            }
        }
    }

    /// Injects a mod/patch file directly into a game or app container.
    func deployGamePatch(sourceFile: URL, targetContainerPath: String, destinationRelativePath: String) async throws {
        let fileData = try Data(contentsOf: sourceFile)
        let fullDestination = (targetContainerPath as NSString).appendingPathComponent(destinationRelativePath)
        try await writeFile(data: fileData, toPath: fullDestination)
    }

    /// Applies a complete .3105 project through the on-device AirTraffic path.
    /// Rules sharing a destination directory are sent in one batch. Every batch
    /// requires an authenticated tunnel and a successful canary read-back first.
    func applyPatchProject(_ project: PatchProject) async throws {
        try await withExclusivePatchOperation { operationID in
            try await self.applyPatchProjectInOperation(project, operationID: operationID)
        }
    }

    /// Caller already owns the shared filesystem operation. Never reacquire it.
    func applyPatchProjectInOperation(_ project: PatchProject, operationID: UUID) async throws {
        try await PatchFilesystemGate.shared.validate(operationID)
        try await AppIntegrityRuntime.shared.requireAllowed(force:true)
        try PatchPackageCodec.validate(project)

        // 1. Nếu worse_query sẵn sàng trên máy, áp dụng patch trực tiếp không cần AirLift
        guard ExploitSupportPolicy.currentStorageMode != .unsupported else {
            throw WorseQueryError.unsupportedOS(AppInfo.osBuild)
        }
        if ExploitSupportPolicy.currentStorageMode == .direct {
            // Direct access must use the journalled transaction, just like the
            // catalog path. Never mark these writes as an AirLift application.
            let roots = try await DevicePatchService.prepareContainers(bundleIDs: project.allBundleIdentifiers)
            let networkGeneration = try await NetworkAccessGate.shared.requireAllowed()
            try Task.checkCancellation()
            try NetworkAccessGate.shared.validateGeneration(networkGeneration)
            _ = try await DirectPatchExecutor.run(validation: { try NetworkAccessGate.shared.validateGeneration(networkGeneration) }) {
                try IntegrityCommitBarrier.withCommit { try DevicePatchService.apply(project: project, preparedContainers: roots) }
            }
            return
        }

        guard isAirLiftActive, isAirTrafficEngineLinked else {
            throw AirLiftError.executionFailed("AirLift chưa được bật trong Cài đặt.")
        }
        try AirLiftPatchCapabilities.validate(project)
        let store = try applicationStore()
        try store.requireResolvedLegacyHistory()
        let previousRecord = try store.read(project.id)
        guard previousRecord == nil || previousRecord?.phase == .restored,
              previousRecord != nil || !UserDefaults.standard.bool(forKey: airLiftAppliedKey(project.id)),
              DevicePatchService.recordedApplicationState(projectID: project.id) != .applied,
              DevicePatchService.recordedApplicationState(projectID: project.id) != .recoveryRequired else {
            throw PatchEngineStateError.recoveryRequired
        }
        let targets = (project.rules.map { $0.bundleID + "\0" + $0.relativePath }
            + project.directories.map { $0.bundleID + "\0" + $0.relativePath }).sorted()
        try store.requireNoUnbackedOverlap(projectID: project.id, targetKeys: targets, includingBackedApplications: true)
        let occupied = try DevicePatchService.activeTargetKeys()
        guard !targets.contains(where: { target in occupied.contains(where: {
            target == $0 || target.hasPrefix($0 + "/") || $0.hasPrefix(target + "/")
        }) }) else { throw PatchEngineStateError.recoveryRequired }

        struct BatchKey: Hashable {
            let bundleID: String
            let relativeDirectory: String
        }

        var batches: [BatchKey: [String: Data]] = [:]
        for rule in project.rules {
            let bundleID = try PatchPathValidator.canonicalBundleIdentifier(rule.bundleID)
            let relativePath = try PatchPathValidator.canonicalRelativePath(rule.relativePath)
            let relativeDirectory = (relativePath as NSString).deletingLastPathComponent
            let filename = (relativePath as NSString).lastPathComponent
            let key = BatchKey(bundleID: bundleID, relativeDirectory: relativeDirectory)
            var files = batches[key, default: [:]]
            guard files[filename] == nil else { throw PatchPackageError.duplicateTarget }
            files[filename] = rule.replacementData
            batches[key] = files
        }

        var containers: [String: String] = [:]
        for bundleID in Set(batches.keys.map(\.bundleID)) {
            containers[bundleID] = try await AirTrafficProtocolClient.shared
                .resolveAppContainer(bundleID: bundleID)
        }

        var record = PatchEngineApplicationRecord(projectID: project.id, operationID: operationID,
            engine: .airLift, baseline: .unavailable, targetKeys: targets, totalBatches: batches.count)
        var completedBatches = 0
        var dispatchStarted = false
        for key in batches.keys.sorted(by: {
            if $0.bundleID != $1.bundleID { return $0.bundleID < $1.bundleID }
            return $0.relativeDirectory < $1.relativeDirectory
        }) {
            guard let root = containers[key.bundleID], let files = batches[key] else {
                throw PatchPackageError.targetAppUnavailable(key.bundleID)
            }
            let destination = key.relativeDirectory.isEmpty
                ? root
                : (root as NSString).appendingPathComponent(key.relativeDirectory)
            do {
                let networkGeneration = try await NetworkAccessGate.shared.requireAllowed()
                try Task.checkCancellation()
                try NetworkAccessGate.shared.validateGeneration(networkGeneration)
                // Persist before native dispatch, including the first batch.
                // Timeout/cancellation cannot prove no bytes were written.
                record.phase = .writing
                try store.save(record)
                dispatchStarted = true
                try await AirTrafficProtocolClient.shared.writeFiles(
                    files,
                    targetDirectory: destination
                )
                completedBatches += 1
                record.completedBatches = completedBatches
                try store.save(record)
            } catch {
                if dispatchStarted {
                    record.phase = .recoveryRequired
                    try? store.save(record) // Earlier durable writing state remains on failure.
                }
                if let airLiftError = error as? AirLiftError, airLiftError.requiresRePairing {
                    AirLiftGatekeeperManager.shared.triggerRePair(reason: "Pairing AirLift không còn hợp lệ: \(airLiftError.localizedDescription)")
                }
                if completedBatches > 0 {
                    throw AirLiftError.executionFailed(
                        "Đã ghi \(completedBatches) nhóm file trước khi thao tác dừng. Gói có thể được áp dụng một phần; cần kiểm tra lại trước khi tiếp tục. \(error.localizedDescription)"
                    )
                }
                throw error
            }
        }

        record.phase = .applied
        try store.save(record)
        UserDefaults.standard.set(true, forKey: airLiftAppliedKey(project.id))
        objectWillChange.send()
    }
}
