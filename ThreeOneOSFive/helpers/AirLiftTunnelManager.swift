//
//  AirLiftTunnelManager.swift
//  ThreeOneOSFive
//
//  Owns the LocalDevVPN-style packet tunnel and verifies that it can actually
//  reach the device service. A green VPN icon alone is not treated as proof.
//

import Foundation
import NetworkExtension
import Combine
import Darwin

@MainActor
final class AirLiftTunnelManager: ObservableObject {
    static let shared = AirLiftTunnelManager()

    enum TunnelStatus: String {
        case disconnected = "Chưa kết nối"
        case connecting = "Đang kết nối..."
        case connected = "VPN đã kết nối"
        case disconnecting = "Đang ngắt..."
        case checking = "Đang kiểm tra trạng thái..."
        case invalid = "Chưa cấu hình"

        var isConnected: Bool { self == .connected }
    }

    enum ServiceStatus: String {
        case unavailable = "Chưa kiểm tra dịch vụ"
        case checking = "Đang kiểm tra RSD/lockdownd qua 10.7.0.1..."
        case reachable = "Dịch vụ RSD/lockdownd đã sẵn sàng"
        case unreachable = "Không nhận được phản hồi RSD/lockdownd"
    }

    @Published var status: TunnelStatus = .checking
    @Published var serviceStatus: ServiceStatus = .unavailable
    @Published var isEnabled = false
    @Published var lastErrorMessage: String?

    var isServiceReachable: Bool { serviceStatus == .reachable }
    var isOperational: Bool { status == .connected && isServiceReachable }

    private var tunnelManager: NETunnelProviderManager?
    private var cancellables = Set<AnyCancellable>()
    private var serviceProbeTask: Task<Void, Never>?

    private let tunnelDescription = "NovaX Local Tunnel"
    private let peerAddress = "10.7.0.1"
    private let lockdownPort: UInt16 = 62078
    private let rsdPort: UInt16 = 49152

    private var tunnelBundleID: String {
        let mainID = Bundle.main.bundleIdentifier ?? "com.apple.mobile.MobileHouseArrest"
        return "\(mainID).TunnelProv"
    }

    private init() {
        observeTunnelNotifications()
        Task { await refreshTunnelManager() }
    }

    func refreshTunnelManager() async {
        status = .checking
        lastErrorMessage = nil

        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()

            // Never take ownership of another app's VPN configuration. The old
            // fuzzy match could select any manager containing "TunnelProv".
            if let existing = managers.first(where: { manager in
                let bundleID = (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                return bundleID == tunnelBundleID
            }) {
                tunnelManager = existing
                isEnabled = existing.isEnabled
                updateStatus(from: existing.connection.status)
                if existing.connection.status == .connected {
                    scheduleServiceProbe()
                }
            } else {
                guard isTunnelExtensionEmbedded else {
                    throw tunnelError(
                        code: -10,
                        message: "Không tìm thấy TunnelProv.appex trong ứng dụng. Hãy build lại target NovaX cùng extension TunnelProv."
                    )
                }
                let manager = try await createDefaultManager()
                tunnelManager = manager
                isEnabled = manager.isEnabled
                updateStatus(from: manager.connection.status)
            }
        } catch {
            status = .invalid
            serviceStatus = .unavailable
            lastErrorMessage = error.localizedDescription
        }
    }

    private var isTunnelExtensionEmbedded: Bool {
        guard let pluginsURL = Bundle.main.builtInPlugInsURL else { return false }
        return FileManager.default.fileExists(
            atPath: pluginsURL.appendingPathComponent("TunnelProv.appex").path
        )
    }

    private func makeProtocolConfiguration() -> NETunnelProviderProtocol {
        let configuration = NETunnelProviderProtocol()
        configuration.providerBundleIdentifier = tunnelBundleID
        configuration.serverAddress = peerAddress
        configuration.providerConfiguration = [
            "TunnelIfaceIP": "10.7.1.1/32",
            "TunnelPeerIP": "10.7.0.1/32"
        ]
        return configuration
    }

    private func createDefaultManager() async throws -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        manager.protocolConfiguration = makeProtocolConfiguration()
        manager.localizedDescription = tunnelDescription
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        return manager
    }

    func startTunnel() async throws {
        lastErrorMessage = nil
        serviceStatus = .unavailable

        if tunnelManager == nil {
            await refreshTunnelManager()
        }
        guard let manager = tunnelManager else {
            throw tunnelError(code: -1, message: lastErrorMessage ?? "Không tìm thấy cấu hình tunnel NovaX.")
        }

        try await startTunnelWithManager(manager)
        try await waitForConnected(manager, timeout: 15)
        await verifyLoopbackService()
    }

    private func startTunnelWithManager(_ manager: NETunnelProviderManager) async throws {
        try await manager.loadFromPreferences()

        guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol,
              proto.providerBundleIdentifier == tunnelBundleID else {
            throw tunnelError(code: -2, message: "Cấu hình VPN không trỏ tới extension \(tunnelBundleID).")
        }

        manager.localizedDescription = tunnelDescription
        manager.protocolConfiguration = makeProtocolConfiguration()
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        isEnabled = manager.isEnabled

        if manager.connection.status == .connected {
            updateStatus(from: .connected)
            return
        }

        status = .connecting
        let options: [String: NSObject] = [
            "TunnelIfaceIP": "10.7.1.1/32" as NSString,
            "TunnelPeerIP": "10.7.0.1/32" as NSString
        ]
        try manager.connection.startVPNTunnel(options: options)
    }

    private func waitForConnected(_ manager: NETunnelProviderManager, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch manager.connection.status {
            case .connected:
                updateStatus(from: .connected)
                return
            case .disconnected, .invalid:
                throw tunnelError(code: -3, message: "iOS đã dừng tunnel trước khi kết nối hoàn tất.")
            default:
                break
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        manager.connection.stopVPNTunnel()
        throw tunnelError(code: -4, message: "Tunnel không chuyển sang Connected sau \(Int(timeout)) giây.")
    }

    func verifyLoopbackService() async {
        guard status == .connected else {
            serviceStatus = .unavailable
            return
        }

        serviceStatus = .checking
        let host = peerAddress
        let port = lockdownPort
        let remoteServicePort = rsdPort
        let result = await Task.detached(priority: .utility) {
            let lockdown = Self.queryLockdown(host: host, port: port)
            if lockdown.ok { return lockdown }
            if Self.canConnectTCP(host: host, port: remoteServicePort) {
                return .init(ok: true, message: "RSD đang lắng nghe trên cổng \(remoteServicePort).")
            }
            return .init(
                ok: false,
                message: "\(lockdown.message) RSD \(host):\(remoteServicePort) cũng không kết nối được."
            )
        }.value

        if result.ok {
            serviceStatus = .reachable
            lastErrorMessage = nil
        } else {
            serviceStatus = .unreachable
            lastErrorMessage = result.message
        }
    }

    func stopTunnel() {
        serviceProbeTask?.cancel()
        serviceProbeTask = nil
        serviceStatus = .unavailable
        tunnelManager?.connection.stopVPNTunnel()
    }

    func toggleTunnel() async {
        if status.isConnected {
            stopTunnel()
        } else {
            do {
                try await startTunnel()
            } catch {
                lastErrorMessage = error.localizedDescription
                status = .disconnected
                serviceStatus = .unreachable
            }
        }
    }

    private func updateStatus(from neStatus: NEVPNStatus) {
        switch neStatus {
        case .connected:
            status = .connected
        case .connecting, .reasserting:
            status = .connecting
        case .disconnecting:
            status = .disconnecting
        case .disconnected:
            status = .disconnected
            serviceStatus = .unavailable
        case .invalid:
            status = .invalid
            serviceStatus = .unavailable
        @unknown default:
            status = .disconnected
            serviceStatus = .unavailable
        }
    }

    private func scheduleServiceProbe() {
        serviceProbeTask?.cancel()
        serviceProbeTask = Task { [weak self] in
            await self?.verifyLoopbackService()
        }
    }

    private func observeTunnelNotifications() {
        NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let connection = self.tunnelManager?.connection else { return }
                let oldStatus = self.status
                self.updateStatus(from: connection.status)
                if connection.status == .connected && oldStatus != .connected {
                    self.scheduleServiceProbe()
                }
            }
            .store(in: &cancellables)
    }

    private func tunnelError(code: Int, message: String) -> NSError {
        NSError(domain: "AirLiftTunnel", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private struct LockdownProbeResult: Sendable {
        let ok: Bool
        let message: String
    }

    /// A real lockdown QueryType exchange. Merely opening TCP is not enough:
    /// the peer must return `com.apple.mobile.lockdown` in a framed plist.
    private nonisolated static func queryLockdown(host: String, port: UInt16) -> LockdownProbeResult {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return .init(ok: false, message: "Không thể tạo socket kiểm tra lockdownd.")
        }
        defer { close(descriptor) }

        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            return .init(ok: false, message: "Địa chỉ peer tunnel không hợp lệ.")
        }

        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            return .init(ok: false, message: "VPN đã bật nhưng 10.7.0.1:62078 chưa nhận kết nối.")
        }

        do {
            let request: [String: Any] = ["Request": "QueryType", "Label": "NovaX-AirLift-Probe"]
            let body = try PropertyListSerialization.data(fromPropertyList: request, format: .xml, options: 0)
            var length = UInt32(body.count).bigEndian
            var packet = Data(bytes: &length, count: 4)
            packet.append(body)

            guard sendAll(packet, to: descriptor) else {
                return .init(ok: false, message: "Không gửi được QueryType tới lockdownd.")
            }
            guard let header = receiveExactly(4, from: descriptor) else {
                return .init(ok: false, message: "lockdownd không trả về header hợp lệ.")
            }
            let responseLength = Int(
                (UInt32(header[0]) << 24) |
                (UInt32(header[1]) << 16) |
                (UInt32(header[2]) << 8) |
                UInt32(header[3])
            )
            guard responseLength > 0, responseLength <= 1_048_576,
                  let responseData = receiveExactly(responseLength, from: descriptor),
                  let response = try PropertyListSerialization.propertyList(from: responseData, options: [], format: nil) as? [String: Any],
                  response["Type"] as? String == "com.apple.mobile.lockdown" else {
                return .init(ok: false, message: "Cổng 62078 có mở nhưng phản hồi không phải lockdownd.")
            }
            return .init(ok: true, message: "lockdownd phản hồi hợp lệ.")
        } catch {
            return .init(ok: false, message: "Không phân tích được phản hồi lockdownd: \(error.localizedDescription)")
        }
    }

    private nonisolated static func canConnectTCP(host: String, port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return false }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private nonisolated static func sendAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return false }
            var sent = 0
            while sent < rawBuffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: sent), rawBuffer.count - sent)
                guard count > 0 else { return false }
                sent += count
            }
            return true
        }
    }

    private nonisolated static func receiveExactly(_ count: Int, from descriptor: Int32) -> Data? {
        var result = Data(count: count)
        var received = 0
        let completed = result.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let base = rawBuffer.baseAddress else { return false }
            while received < count {
                let amount = Darwin.read(descriptor, base.advanced(by: received), count - received)
                guard amount > 0 else { return false }
                received += amount
            }
            return true
        }
        return completed ? result : nil
    }
}
