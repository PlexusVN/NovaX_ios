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
            objectWillChange.send()
            AirTrafficProtocolClient.shared.resetSession()
            if useAirLiftForAll {
                Task {
                    _ = await AirTrafficProtocolClient.shared.checkRealAirLiftHealth()
                }
            }
        }
    }
    
    var isAirLiftActive: Bool {
        if useAirLiftForAll { return true }
        // Auto-enable when kernel exploit / direct container access is unavailable
        // (sandboxed without sandbox escape) or on iOS 17+, whenever AirLift pairing or tunnel is active.
        if !KernelExploit.hasSandboxAccess() || ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 17 {
            if AirLiftPairingManager.shared.status.isPaired || AirLiftTunnelManager.shared.isOperational {
                return true
            }
        }
        return false
    }
    
    private init() {}

    private func airLiftAppliedKey(_ projectID: UUID) -> String {
        "airlift.applied.\(projectID.uuidString)"
    }

    func isProjectAppliedThroughAirLift(_ projectID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: airLiftAppliedKey(projectID))
    }
    
    /// Writes or replaces a file in the destination path using the optimal engine.
    func writeFile(data: Data, toPath destinationPath: String) async throws {
        if isAirLiftActive {
            guard isAirTrafficEngineLinked else {
                throw AirLiftError.executionFailed("AirTraffic engine chưa được liên kết; thao tác ghi đã bị chặn an toàn.")
            }
            log("storage: routing write via AirLift provider for \(destinationPath)")
            try await AirTrafficProtocolClient.shared.writeFile(data: data, targetPath: destinationPath)
        } else {
            log("storage: routing write via Direct/Kernel provider for \(destinationPath)")
            let url = URL(fileURLWithPath: destinationPath)
            let parent = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parent.path) {
                try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            try data.write(to: url, options: .atomic)
        }
    }
    
    /// Reads a file from a path using the optimal engine.
    func readFile(atPath path: String) async throws -> Data {
        if isAirLiftActive {
            guard isAirTrafficEngineLinked else {
                throw AirLiftError.executionFailed("AirTraffic engine chưa được liên kết; thao tác đọc đã bị chặn an toàn.")
            }
            return try await AirTrafficProtocolClient.shared.readFile(at: path)
        } else {
            return try Data(contentsOf: URL(fileURLWithPath: path))
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
        guard isAirLiftActive, isAirTrafficEngineLinked else {
            throw AirLiftError.executionFailed("AirLift chưa được bật trong Cài đặt.")
        }
        try PatchPackageCodec.validate(project)
        guard !project.rules.isEmpty else { throw PatchPackageError.invalidProject }

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
            try await AirTrafficProtocolClient.shared.writeFiles(
                files,
                targetDirectory: destination
            )
        }

        UserDefaults.standard.set(true, forKey: airLiftAppliedKey(project.id))
        objectWillChange.send()
    }
}
