//
//  AirTrafficProtocolClient.swift
//  ThreeOneOSFive
//
//  Authenticated RSD/Lockdown + AFC/AirTraffic transport backed by AirliftFFI.
//

import Foundation
import Combine
import AirliftFFI

enum AirLiftError: Error, LocalizedError {
    case tunnelNotConnected
    case pairingRequired
    case invalidTargetPath
    case socketConnectionFailed(String)
    case airTrafficHandshakeFailed(String)
    case filePayloadCreationFailed
    case verificationFailed(String)
    case remoteReadUnsupported
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .tunnelNotConnected:
            return "Đường hầm LocalDevVPN chưa kết nối."
        case .pairingRequired:
            return "Chưa có file pairing hợp lệ."
        case .invalidTargetPath:
            return "Đường dẫn đích không hợp lệ hoặc không phải đường dẫn tuyệt đối."
        case .socketConnectionFailed(let message):
            return "Không thể kết nối dịch vụ thiết bị: \(message)"
        case .airTrafficHandshakeFailed(let message):
            return "Bắt tay AirTraffic thất bại: \(message)"
        case .filePayloadCreationFailed:
            return "Không thể tạo payload AirTraffic."
        case .verificationFailed(let message):
            return "Không thể xác minh quyền ghi AirTraffic: \(message)"
        case .remoteReadUnsupported:
            return "AirliftFFI hiện không cung cấp API đọc file tùy ý; Astra chỉ xác minh canary và kết quả phiên ghi."
        case .executionFailed(let message):
            return "AirLift thất bại: \(message)"
        }
    }
}

@MainActor
final class AirTrafficProtocolClient: ObservableObject {
    static let shared = AirTrafficProtocolClient()

    enum VerificationLevel: String {
        case none = "Chưa xác minh"
        case canary = "Canary read-back + phiên ghi thành công"
        case exactBytes = "Đã đọc lại đúng từng byte"
    }

    @Published private(set) var verificationLevel: VerificationLevel = .none
    @Published fileprivate(set) var lastLogLine = ""

    private let primaryHost = "10.7.0.1"
    private init() {}

    func writeFile(data: Data, targetPath: String) async throws {
        let target = try normalizedAbsolutePath(targetPath)
        let targetURL = URL(fileURLWithPath: target)
        let directory = targetURL.deletingLastPathComponent().path
        let filename = targetURL.lastPathComponent
        guard !filename.isEmpty else { throw AirLiftError.invalidTargetPath }

        try await verifyTransportAndPairing()
        let pairingPath = try activePairingPath()
        try await configureTargetHost()
        try await verifyCanary(pairingPath: pairingPath, targetDirectory: directory)

        let stage = FileManager.default.temporaryDirectory
            .appendingPathComponent("novax-airlift-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        do {
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
            try data.write(
                to: stage.appendingPathComponent(filename),
                options: [.atomic, .completeFileProtection]
            )
        } catch {
            throw AirLiftError.filePayloadCreationFailed
        }

        try await writeDirectory(
            pairingPath: pairingPath,
            sourceDirectory: stage.path,
            targetDirectory: directory
        )

        // When a local sandbox grant happens to expose the target, perform the
        // strongest possible verification. Otherwise the FFI canary read-back
        // plus a successful authenticated AirTraffic transaction is required.
        if FileManager.default.isReadableFile(atPath: target),
           let recovered = try? Data(contentsOf: targetURL),
           recovered == data {
            verificationLevel = .exactBytes
        } else {
            verificationLevel = .canary
        }
    }

    func writeFiles(_ files: [String: Data], targetDirectory: String) async throws {
        guard !files.isEmpty else { throw AirLiftError.filePayloadCreationFailed }
        let directory = try normalizedAbsolutePath(targetDirectory)
        try await verifyTransportAndPairing()
        let pairingPath = try activePairingPath()
        try await configureTargetHost()
        try await verifyCanary(pairingPath: pairingPath, targetDirectory: directory)

        let stage = FileManager.default.temporaryDirectory
            .appendingPathComponent("novax-airlift-batch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        do {
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
            for (name, data) in files {
                guard !name.isEmpty, name == (name as NSString).lastPathComponent,
                      name != ".", name != ".." else {
                    throw AirLiftError.invalidTargetPath
                }
                try data.write(
                    to: stage.appendingPathComponent(name),
                    options: [.atomic, .completeFileProtection]
                )
            }
        } catch let error as AirLiftError {
            throw error
        } catch {
            throw AirLiftError.filePayloadCreationFailed
        }

        try await writeDirectory(
            pairingPath: pairingPath,
            sourceDirectory: stage.path,
            targetDirectory: directory
        )
        verificationLevel = .canary
    }

    func readFile(at targetPath: String) async throws -> Data {
        let target = try normalizedAbsolutePath(targetPath)
        if FileManager.default.isReadableFile(atPath: target) {
            return try Data(contentsOf: URL(fileURLWithPath: target))
        }
        throw AirLiftError.remoteReadUnsupported
    }

    func resolveAppContainer(bundleID: String) async throws -> String {
        guard !bundleID.isEmpty else { throw AirLiftError.invalidTargetPath }
        try await verifyTransportAndPairing()
        let pairingPath = try activePairingPath()
        try await configureTargetHost()

        let result: FFIStringResult = await runBlocking(name: "Astra.AirLift.FindContainer") {
            var output: UnsafeMutablePointer<CChar>?
            var error: UnsafeMutablePointer<CChar>?
            let code = pairingPath.withCString { pairing in
                bundleID.withCString { bundle in
                    al_find_app_container(pairing, bundle, novaAirLiftLogCallback, nil, &output, &error)
                }
            }
            let value = Self.consumeString(&output)
            let message = Self.consumeString(&error)
            return FFIStringResult(code: code, value: value, error: message)
        }
        guard result.code == 0, !result.value.isEmpty else {
            throw AirLiftError.executionFailed(
                result.error.isEmpty ? "Không tìm thấy container của \(bundleID)." : result.error
            )
        }
        return result.value
    }

    private func verifyTransportAndPairing() async throws {
        let tunnel = AirLiftTunnelManager.shared
        await tunnel.verifyLoopbackService()
        guard tunnel.isOperational else {
            throw AirLiftError.socketConnectionFailed(
                tunnel.lastErrorMessage ?? "Hãy mở ứng dụng LocalDevVPN, bật tunnel rồi thử lại."
            )
        }
        _ = try activePairingPath()
    }

    private func activePairingPath() throws -> String {
        let pairing = AirLiftPairingManager.shared
        guard pairing.status == .ready,
              let path = pairing.pairingFilePath,
              FileManager.default.fileExists(atPath: path) else {
            throw AirLiftError.pairingRequired
        }
        return path
    }

    private func configureTargetHost() async throws {
        let code = primaryHost.withCString { al_set_target_host($0) }
        guard code == 0 else {
            throw AirLiftError.socketConnectionFailed("Không thể đặt host LocalDevVPN \(primaryHost).")
        }
    }

    private func verifyCanary(pairingPath: String, targetDirectory: String) async throws {
        verificationLevel = .none
        let result: FFIStringResult = await runBlocking(name: "Astra.AirLift.Canary") {
            var json: UnsafeMutablePointer<CChar>?
            var error: UnsafeMutablePointer<CChar>?
            let code = pairingPath.withCString { pairing in
                targetDirectory.withCString { target in
                    al_exploit_run(pairing, target, novaAirLiftLogCallback, nil, &json, &error)
                }
            }
            return FFIStringResult(
                code: code,
                value: Self.consumeString(&json),
                error: Self.consumeString(&error)
            )
        }
        guard result.code == 0 else {
            throw AirLiftError.verificationFailed(result.error.isEmpty ? "canary bị từ chối" : result.error)
        }
        guard let data = result.value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["airTrafficSucceeded"] as? Bool == true,
              object["exactBytesRecovered"] as? Bool == true else {
            throw AirLiftError.verificationFailed("engine không xác nhận byte canary đọc lại.")
        }
        verificationLevel = .canary
    }

    private func writeDirectory(
        pairingPath: String,
        sourceDirectory: String,
        targetDirectory: String
    ) async throws {
        let result: FFIVoidResult = await runBlocking(name: "Astra.AirLift.Write") {
            var error: UnsafeMutablePointer<CChar>?
            let code = pairingPath.withCString { pairing in
                sourceDirectory.withCString { source in
                    targetDirectory.withCString { target in
                        al_exploit_write_dir(
                            pairing, source, target,
                            novaAirLiftLogCallback, nil, &error
                        )
                    }
                }
            }
            return FFIVoidResult(code: code, error: Self.consumeString(&error))
        }
        guard result.code == 0 else {
            throw AirLiftError.executionFailed(
                result.error.isEmpty ? "AirTraffic không xác nhận phiên ghi." : result.error
            )
        }
    }

    private func normalizedAbsolutePath(_ path: String) throws -> String {
        let value = (path as NSString).standardizingPath
        guard value.hasPrefix("/"), value != "/", !value.contains("\0") else {
            throw AirLiftError.invalidTargetPath
        }
        return value
    }

    private func runBlocking<T: Sendable>(name: String, _ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(returning: work())
            }
            thread.name = name
            thread.stackSize = 8 * 1_024 * 1_024
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    private nonisolated static func consumeString(_ pointer: inout UnsafeMutablePointer<CChar>?) -> String {
        guard let value = pointer else { return "" }
        let string = String(cString: value)
        al_string_free(value)
        pointer = nil
        return string
    }
}

private struct FFIStringResult: Sendable {
    let code: Int32
    let value: String
    let error: String
}

private struct FFIVoidResult: Sendable {
    let code: Int32
    let error: String
}

private let novaAirLiftLogCallback: ALLogCallback = { _, message in
    guard let message else { return }
    let line = String(cString: message)
    log("airlift: \(line)")
    Task { @MainActor in
        AirTrafficProtocolClient.shared.lastLogLine = line
    }
}
