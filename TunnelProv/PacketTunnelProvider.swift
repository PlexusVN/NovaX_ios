//
//  PacketTunnelProvider.swift
//  TunnelProv
//
//  Created by NovaX AirLift Integration on 03/10/2026.
//  Loopback packet reflector for local IPC communication.
//

import Foundation
import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {
    var tunnelIfaceIP: String = "10.7.1.1/32"
    var tunnelPeerIP: String = "10.7.0.1/32"
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let providerConfiguration = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        
        if let ifaceIp = options?["TunnelIfaceIP"] as? String ?? providerConfiguration?["TunnelIfaceIP"] as? String {
            tunnelIfaceIP = ifaceIp
        }
        if let peerIp = options?["TunnelPeerIP"] as? String ?? providerConfiguration?["TunnelPeerIP"] as? String {
            tunnelPeerIP = peerIp
        }
        
        let ifaceIPClean = tunnelIfaceIP.components(separatedBy: "/").first ?? "10.7.1.1"
        let peerIPClean = tunnelPeerIP.components(separatedBy: "/").first ?? "10.7.0.1"
        
        let ifaceIPv4 = NEIPv4Settings(addresses: [ifaceIPClean], subnetMasks: ["255.255.0.0"])
        let tunnelDestinationIPv4Routes = [
            NEIPv4Route(destinationAddress: peerIPClean, subnetMask: "255.255.255.255")
        ]
        ifaceIPv4.includedRoutes = tunnelDestinationIPv4Routes
        ifaceIPv4.excludedRoutes = [.default()]
        
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: peerIPClean)
        settings.ipv4Settings = ifaceIPv4
        
        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error {
                completionHandler(error)
                return
            }
            self?.startPacketLoop()
            completionHandler(nil)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    private func startPacketLoop() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }
            var modified = packets
            
            for i in modified.indices where protocols[i].int32Value == AF_INET && modified[i].count >= 20 {
                modified[i].withUnsafeMutableBytes { bytes in
                    guard let ptr = bytes.baseAddress?.assumingMemoryBound(to: UInt32.self) else { return }
                    let src = ptr[3]
                    let dst = ptr[4]
                    ptr[3] = dst
                    ptr[4] = src
                }
            }
            
            self.packetFlow.writePackets(modified, withProtocols: protocols)
            self.startPacketLoop()
        }
    }
}
