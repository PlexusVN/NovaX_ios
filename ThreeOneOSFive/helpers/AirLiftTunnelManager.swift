//
//  AirLiftTunnelManager.swift
//  ThreeOneOSFive
//
//  Created by NovaX AirLift Integration on 03/10/2026.
//  Manages the lifecycle and state of the LocalDevVPN loopback tunnel.
//

import Foundation
import NetworkExtension
import Combine

@MainActor
final class AirLiftTunnelManager: ObservableObject {
    static let shared = AirLiftTunnelManager()
    
    enum TunnelStatus: String {
        case disconnected = "Chưa kết nối"
        case connecting = "Đang kết nối..."
        case connected = "Đã kết nối"
        case disconnecting = "Đang ngắt..."
        case checking = "Đang kiểm tra trạng thái..."
        case invalid = "Chưa cấu hình"
        
        var isConnected: Bool {
            self == .connected
        }
    }
    
    @Published var status: TunnelStatus = .checking
    @Published var isEnabled: Bool = false
    @Published var lastErrorMessage: String?
    
    private var tunnelManager: NETunnelProviderManager?
    private var cancellables = Set<AnyCancellable>()
    
    private var tunnelBundleID: String {
        let mainID = Bundle.main.bundleIdentifier ?? "com.apple.mobile.MobileHouseArrest"
        return "\(mainID).TunnelProv"
    }
    
    private init() {
        observeTunnelNotifications()
        Task {
            await refreshTunnelManager()
        }
    }
    
    func refreshTunnelManager() async {
        status = .checking
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            
            // 1. Tìm manager chính của NovaX hoặc LocalDevVPN
            let matchingManager = managers.first(where: {
                let bundleId = ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier ?? ""
                return bundleId == self.tunnelBundleID || bundleId.contains("LocalDevVPN") || bundleId.contains("TunnelProv")
            }) ?? managers.first(where: {
                let srv = ($0.protocolConfiguration as? NETunnelProviderProtocol)?.serverAddress ?? ""
                return srv == "10.7.0.1" || srv == "10.7.1.1"
            })
            
            if let existing = matchingManager {
                self.tunnelManager = existing
                self.isEnabled = existing.isEnabled
                if existing.localizedDescription != "NovaX VPN devoloper" {
                    existing.localizedDescription = "NovaX VPN devoloper"
                    try? await existing.saveToPreferences()
                }
                self.updateStatus(from: existing.connection.status)
            } else {
                let newManager = try await createDefaultManager()
                self.tunnelManager = newManager
                self.isEnabled = newManager.isEnabled
                self.updateStatus(from: newManager.connection.status)
            }
        } catch {
            self.status = .disconnected
            self.lastErrorMessage = error.localizedDescription
        }
    }
    
    private func createDefaultManager() async throws -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleID
        proto.serverAddress = "10.7.0.1"
        proto.providerConfiguration = [
            "TunnelIfaceIP": "10.7.1.1/32",
            "TunnelPeerIP": "10.7.0.1/32"
        ]
        manager.protocolConfiguration = proto
        manager.localizedDescription = "NovaX VPN devoloper"
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        return manager
    }
    
    func startTunnel() async throws {
        guard let manager = tunnelManager else {
            await refreshTunnelManager()
            guard let manager = tunnelManager else {
                throw NSError(domain: "AirLiftTunnel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy cấu hình Tunnel"])
            }
            try await startTunnelWithManager(manager)
            return
        }
        try await startTunnelWithManager(manager)
    }
    
    private func startTunnelWithManager(_ manager: NETunnelProviderManager) async throws {
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        
        let options: [String: NSObject] = [
            "TunnelIfaceIP": "10.7.1.1/32" as NSString,
            "TunnelPeerIP": "10.7.0.1/32" as NSString
        ]
        try manager.connection.startVPNTunnel(options: options)
    }
    
    func stopTunnel() {
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
            }
        }
    }
    
    private func updateStatus(from neStatus: NEVPNStatus) {
        switch neStatus {
        case .connected:
            self.status = .connected
        case .connecting:
            self.status = .connecting
        case .disconnecting:
            self.status = .disconnecting
        case .disconnected:
            self.status = .disconnected
        case .invalid:
            self.status = .invalid
        case .reasserting:
            self.status = .connecting
        @unknown default:
            self.status = .disconnected
        }
    }
    
    private func observeTunnelNotifications() {
        NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, let conn = self.tunnelManager?.connection else { return }
                self.updateStatus(from: conn.status)
            }
            .store(in: &cancellables)
    }
}
