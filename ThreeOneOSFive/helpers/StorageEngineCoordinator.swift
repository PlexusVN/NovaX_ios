//
//  StorageEngineCoordinator.swift
//  ThreeOneOSFive
//
//  Created by NovaX AirLift Integration on 03/10/2026.
//  Coordinates dual-engine I/O: Direct/Kernel Exploit vs AirLift Loopback.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class StorageEngineCoordinator: ObservableObject {
    static let shared = StorageEngineCoordinator()
    
    @AppStorage("useAirLiftForAll") var useAirLiftForAll: Bool = false {
        didSet {
            objectWillChange.send()
        }
    }
    
    var isAirLiftActive: Bool {
        if useAirLiftForAll { return true }
        // Auto-enable for iOS 27+ if direct write is restricted
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            return true
        }
        return false
    }
    
    private init() {}
    
    /// Writes or replaces a file in the destination path using the optimal engine.
    func writeFile(data: Data, toPath destinationPath: String) async throws {
        if isAirLiftActive {
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
}
