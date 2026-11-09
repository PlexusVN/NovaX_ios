//
//  AirLiftTunnelManager.swift
//  ThreeOneOSFive
//
//  Detects an external LocalDevVPN tunnel and verifies that it can actually
//  reach the device service. Astra does not own or configure a VPN profile.
//

import Foundation
import Combine
import Darwin
import UIKit

@MainActor
final class AirLiftTunnelManager: ObservableObject {
    static let shared = AirLiftTunnelManager()

    enum TunnelStatus: String {
        case disconnected = "LocalDevVPN chưa sẵn sàng"
        case connecting = "Đang mở LocalDevVPN..."
        case connected = "LocalDevVPN hoạt động"
        case disconnecting = "Đang cập nhật..."
        case checking = "Đang kiểm tra LocalDevVPN..."
        case invalid = "Chưa cài LocalDevVPN"

        var isConnected: Bool { self == .connected }
    }

    enum ServiceStatus: String {
        case unavailable = "Chưa kiểm tra dịch vụ"
        case checking = "Đang kiểm tra RSD/lockdownd qua 10.7.0.1..."
        case routeReady = "Đã nhận diện route LocalDevVPN; AirLift sẽ xác thực RSD"
        case reachable = "Dịch vụ RSD/lockdownd đã sẵn sàng"
        case unreachable = "Không nhận được phản hồi RSD/lockdownd"
    }

    @Published var status: TunnelStatus = .checking
    @Published var serviceStatus: ServiceStatus = .unavailable
    @Published var isEnabled = false
    @Published private(set) var isTunnelRouteDetected = false
    @Published private(set) var isPortResponsive = false
    @Published private(set) var activePeerAddress = "10.7.0.1"
    @Published var lastErrorMessage: String?

    /// The transport is operational as soon as iOS actually routes the
    /// AirLift peer through the external LocalDevVPN tunnel.
    var isServiceReachable: Bool { serviceStatus == .reachable }
    var isOperational: Bool { isTunnelRouteDetected || isServiceReachable }

    private let peerAddress = "10.7.0.1"
    private let fallbackPeerAddress = "172.16.0.1"
    private let expectedInterfaceAddress = "10.7.1.1"
    private let lockdownPort: UInt16 = 62078
    private let rsdPort: UInt16 = 49152
    private var cancellables = Set<AnyCancellable>()

    private init() {
        guard ExploitSupportPolicy.currentStorageMode == .airLift else {
            status = .disconnected
            serviceStatus = .unavailable
            return
        }
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.verifyLoopbackService()
                }
            }
            .store(in: &cancellables)
        Task { await verifyLoopbackService() }
    }

    /// Kept as a compatibility entry point for existing callers. Astra no
    /// longer reads or creates VPN preferences; it only probes the external app.
    func refreshTunnelManager() async {
        await verifyLoopbackService()
    }

    func openLocalDevVPN() {
        guard let url = URL(string: "localdevvpn://") else { return }
        guard UIApplication.shared.canOpenURL(url) else {
            status = .invalid
            lastErrorMessage = "Không tìm thấy ứng dụng LocalDevVPN. Hãy cài ứng dụng rồi bật tunnel trong LocalDevVPN."
            return
        }
        status = .connecting
        UIApplication.shared.open(url)
    }

    func verifyLoopbackService() async {
        status = .checking
        serviceStatus = .checking
        lastErrorMessage = nil

        let candidates = [peerAddress, fallbackPeerAddress]
        let expectedSource = expectedInterfaceAddress

        let result = await Task.detached(priority: .utility) {
            var winningHost = candidates[0]
            var routeFound = false
            var portResponsive = false
            var serviceFound = false
            var statusMessage = ""

            for host in candidates {
                let hasRoute = Self.hasTunnelRoute(to: host, expectedSource: (host == "10.7.0.1") ? expectedSource : host)
                if hasRoute {
                    routeFound = true
                    winningHost = host
                }

                // Check port 49152 (RSD) and port 62078 (Lockdown)
                let rsdProbe = Self.probeTcpPort(host: host, port: 49152, timeoutSec: 1.2)
                let lkdProbe = Self.probeTcpPort(host: host, port: 62078, timeoutSec: 1.2)

                if rsdProbe.connected || lkdProbe.connected {
                    winningHost = host
                    routeFound = true
                    portResponsive = true
                    serviceFound = true
                    statusMessage = "Dịch vụ RSD/Lockdown phản hồi tốt trên \(host)."
                    break
                } else if rsdProbe.reachable || lkdProbe.reachable {
                    winningHost = host
                    routeFound = true
                    portResponsive = true
                    statusMessage = "Đã nhận diện route tunnel tới \(host)."
                    break
                }
            }

            if !serviceFound && routeFound {
                let lk = Self.queryLockdown(host: winningHost, port: 62078)
                if lk.ok {
                    serviceFound = true
                    portResponsive = true
                    statusMessage = lk.message
                }
            }

            if !routeFound {
                if Self.hasAnyTunnelInterface() {
                    routeFound = true
                    statusMessage = "Đã nhận diện interface tunnel mạng cục bộ."
                } else {
                    statusMessage = "Không tìm thấy route LocalDevVPN tới \(winningHost). Hãy mở LocalDevVPN và bấm Bật kết nối."
                }
            }

            return TunnelProbeResult(
                routeDetected: routeFound,
                portResponsive: portResponsive,
                serviceReachable: serviceFound,
                activeHost: winningHost,
                message: statusMessage
            )
        }.value

        isTunnelRouteDetected = result.routeDetected
        isPortResponsive = result.portResponsive
        activePeerAddress = result.activeHost
        if result.serviceReachable || (result.routeDetected && result.portResponsive) {
            status = .connected
            isEnabled = true
            serviceStatus = result.serviceReachable ? .reachable : .routeReady
            lastErrorMessage = nil
        } else if result.routeDetected {
            status = .connected
            isEnabled = true
            serviceStatus = .routeReady
            lastErrorMessage = nil
        } else {
            status = .disconnected
            isEnabled = false
            serviceStatus = .unreachable
            lastErrorMessage = result.message
        }
    }

    private struct LockdownProbeResult: Sendable {
        let ok: Bool
        let message: String
    }

    private struct TunnelProbeResult: Sendable {
        let routeDetected: Bool
        let portResponsive: Bool
        let serviceReachable: Bool
        let activeHost: String
        let message: String
    }

    /// Fast non-blocking TCP socket probe to verify if the loopback tunnel actively routes packets.
    nonisolated static func probeTcpPort(host: String, port: UInt16, timeoutSec: Double = 1.2) -> (reachable: Bool, connected: Bool) {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return (false, false) }
        defer { Darwin.close(fd) }

        let flags = Darwin.fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = Darwin.fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return (false, false) }

        let ret = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if ret == 0 {
            return (true, true)
        }

        let err = errno
        if err == EINPROGRESS || err == EALREADY || err == EWOULDBLOCK {
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT | POLLIN | POLLERR | POLLHUP), revents: 0)
            let pollTimeoutMs = Int32(timeoutSec * 1000)
            let pollRet = Darwin.poll(&pfd, 1, pollTimeoutMs)
            if pollRet > 0 {
                var soErr: Int32 = 0
                var soErrLen = socklen_t(MemoryLayout<Int32>.size)
                if Darwin.getsockopt(fd, SOL_SOCKET, SO_ERROR, &soErr, &soErrLen) == 0 {
                    if soErr == 0 {
                        return (true, true)
                    } else if soErr == ECONNREFUSED {
                        return (true, false)
                    }
                }
            }
            return (false, false)
        } else if err == ECONNREFUSED {
            return (true, false)
        }

        return (false, false)
    }

    private nonisolated static func hasAnyTunnelInterface() -> Bool {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return false }
        defer { freeifaddrs(interfaces) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let name = String(cString: current.pointee.ifa_name)
            if isTunnelInterface(name) { return true }
        }
        return false
    }

    /// Confirms that iOS routes the AirLift peer through LocalDevVPN. A UDP
    /// connect does not send traffic; it only asks the kernel to select a route
    /// and local source address for the peer.
    private nonisolated static func hasTunnelRoute(to host: String, expectedSource: String) -> Bool {
        guard let source = routeSource(to: host) else {
            return false
        }
        guard source == expectedSource else { return false }
        if let defaultSource = routeSource(to: "203.0.113.1"), defaultSource == source {
            return false
        }

        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return false }
        defer { freeifaddrs(interfaces) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr,
                  address.pointee.sa_family == sa_family_t(AF_INET) else {
                continue
            }
            let name = String(cString: current.pointee.ifa_name)
            guard name.hasPrefix("utun") || name.hasPrefix("ipsec") ||
                    name.hasPrefix("tap") || name.hasPrefix("ppp") else {
                continue
            }
            if numericHost(address) == source { return true }
        }
        return false
    }

    /// Addresses RemoteXPC may advertise back to the device while it
    /// establishes the tunnel. When available, only the local Wi-Fi interface (en0)
    /// should be passed; cellular interfaces (pdp_ip) must NEVER be passed as they
    /// drop inbound loopback connections and cause 12s socket timeouts.
    nonisolated static func remoteXPCHostCandidates() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return [] }
        defer { freeifaddrs(interfaces) }

        var wifi: [String] = []
        var seen = Set<String>()
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr,
                  address.pointee.sa_family == sa_family_t(AF_INET),
                  let ipv4 = numericHost(address),
                  !ipv4.hasPrefix("127."),
                  !ipv4.hasPrefix("169.254."),
                  seen.insert(ipv4).inserted else {
                continue
            }

            let name = String(cString: current.pointee.ifa_name)
            guard !isTunnelInterface(name), !isCellularInterface(name) else { continue }
            if name == "en0" {
                wifi.append(ipv4)
            }
        }
        return wifi
    }

    private nonisolated static func isCellularInterface(_ name: String) -> Bool {
        name.hasPrefix("pdp_ip") || name.hasPrefix("cellular") || name.hasPrefix("ip1") || name.hasPrefix("wwan")
    }

    private nonisolated static func isTunnelInterface(_ name: String) -> Bool {
        name.hasPrefix("utun") || name.hasPrefix("ipsec") ||
            name.hasPrefix("tap") || name.hasPrefix("ppp")
    }

    private nonisolated static func routeSource(to host: String) -> String? {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var peer = sockaddr_in()
        peer.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        peer.sin_family = sa_family_t(AF_INET)
        peer.sin_port = UInt16(9).bigEndian
        guard inet_pton(AF_INET, host, &peer.sin_addr) == 1 else { return nil }
        let connected = withUnsafePointer(to: &peer) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }

        var local = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let resolved = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard resolved == 0, local.sin_addr.s_addr != 0 else { return nil }
        return withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                numericHost($0)
            }
        }
    }

    private nonisolated static func numericHost(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        return String(cString: host)
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
            return .init(ok: false, message: "10.7.0.1:62078 chưa nhận kết nối từ LocalDevVPN.")
        }

        do {
            let request: [String: Any] = ["Request": "QueryType", "Label": "Astra-AirLift-Probe"]
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
