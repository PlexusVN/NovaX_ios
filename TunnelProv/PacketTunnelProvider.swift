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
    private var isRunning = false
    
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
        
        // The configured interface is /32. Using /16 here makes iOS believe the
        // whole 10.7.0.0/16 is on-link and can route traffic outside the intended
        // reflected peer.
        let ifaceIPv4 = NEIPv4Settings(addresses: [ifaceIPClean], subnetMasks: ["255.255.255.255"])
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
            self?.isRunning = true
            self?.startPacketLoop()
            completionHandler(nil)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        isRunning = false
        completionHandler()
    }
    
    private func startPacketLoop() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self, self.isRunning else { return }
            var modified = packets
            
            for i in modified.indices where i < protocols.count && protocols[i].int32Value == AF_INET && modified[i].count >= 20 {
                modified[i].withUnsafeMutableBytes { bytes in
                    // IPv4 source/destination are bytes 12...15 and 16...19.
                    // Byte-wise swapping avoids an unaligned UInt32 load.
                    for offset in 0..<4 {
                        let sourceByte = bytes[12 + offset]
                        bytes[12 + offset] = bytes[16 + offset]
                        bytes[16 + offset] = sourceByte
                    }
                }
            }
            
            self.packetFlow.writePackets(modified, withProtocols: protocols)
            self.startPacketLoop()
        }
    }
}
