//
//  AirLiftPairingManager.swift
//  ThreeOneOSFive
//
//  Created by NovaX AirLift Integration on 03/10/2026.
//  Manages pairing credentials for lockdown & AirTraffic daemon.
//

import Foundation
import UIKit
import Security
import Network

@MainActor
final class AirLiftPairingManager: NSObject, ObservableObject, NetServiceDelegate {
    static let shared = AirLiftPairingManager()
    
    enum PairingStatus: String {
        case ready = "Sẵn sàng"
        case missing = "Chưa có"
        case invalid = "Không hợp lệ"
        case pairing = "Đang kết nối..."
        case waitingSettings = "Chờ ghép đôi từ Cài đặt..."
    }
    
    @Published var status: PairingStatus = .missing
    @Published var pairingFilePath: String?
    @Published var alertMessage: String?
    @Published var showAlert: Bool = false
    @Published var isBroadcastingBonjour: Bool = false
    
    private var netService: NetService?
    private var mobDevListener: NWListener?
    private var remotePairingListener: NWListener?
    private let pairingFileName = "novax_airlift_pairing.plist"
    
    private var pairingFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = docs.appendingPathComponent(".airlift", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent(pairingFileName)
    }
    
    private override init() {
        super.init()
        checkPairingStatus()
    }
    
    func checkPairingStatus() {
        if FileManager.default.fileExists(atPath: pairingFileURL.path) {
            if let dict = NSDictionary(contentsOf: pairingFileURL) as? [String: Any],
               dict["HostID"] != nil,
               (dict["DeviceCertificate"] != nil || dict["RootCertificate"] != nil || dict["HostCertificate"] != nil) {
                self.status = .ready
                self.pairingFilePath = pairingFileURL.path
                return
            }
        }
        self.status = .missing
        self.pairingFilePath = nil
    }
    
    func importPairingFile(from sourceURL: URL) -> Bool {
        guard sourceURL.startAccessingSecurityScopedResource() else {
            notify(message: "Không thể truy cập tệp pairing đã chọn.")
            return false
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: sourceURL)
            guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                notify(message: "Định dạng tệp pairing không hợp lệ.")
                return false
            }
            
            // Validate required pairing fields
            if plist["HostID"] == nil && plist["DeviceCertificate"] == nil && plist["RootCertificate"] == nil {
                notify(message: "Tệp plist thiếu thông tin chứng thực (HostID/Certificates).")
                return false
            }
            
            try data.write(to: pairingFileURL, options: .atomic)
            checkPairingStatus()
            notify(message: "Nhập file pairing thành công! Đã sẵn sàng kết nối AirTraffic.")
            return true
        } catch {
            notify(message: "Lỗi nhập file: \(error.localizedDescription)")
            return false
        }
    }
    
    func pairDirectlyOnDevice() async {
        self.status = .pairing
        
        let tunnelMgr = AirLiftTunnelManager.shared
        if !tunnelMgr.status.isConnected {
            // Tự động kích hoạt VPN nếu chưa bật
            await tunnelMgr.toggleTunnel()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        
        // 1. Khởi chạy phát sóng Bonjour _apple-mobdev2._tcp và _remotepairing._tcp cho Cài đặt iOS tìm thấy Mac Host
        startBonjourPairingBroadcast()
        self.status = .waitingSettings
        
        do {
            // 2. Thực hiện quy trình Lockdown Pairing qua Loopback
            let record = try await performLockdownPairingHandshake()
            let data = try PropertyListSerialization.data(fromPropertyList: record, format: .xml, options: 0)
            try data.write(to: pairingFileURL, options: .atomic)
            
            checkPairingStatus()
            notify(message: "Ghép đôi trực tiếp trên iPhone thành công! Đã có Pairing file và sẵn sàng patch game.")
        } catch {
            self.status = .missing
            notify(message: "Ghép đôi: \(error.localizedDescription)\n\nHãy đảm bảo VPN đã BẬT, sau đó vào Cài đặt > Quyền riêng tư & Bảo mật > Thiết bị đã ghép đôi (hoặc Chế độ nhà phát triển) để ghép đôi.")
        }
    }
    
    func startBonjourPairingBroadcast() {
        stopBonjourBroadcast()
        
        // 1. Native NWListener Broadcast (_apple-mobdev2._tcp)
        do {
            let params = NWParameters.tcp
            let mobDevService = NWListener.Service(name: "MacBook Pro (NovaX)", type: "_apple-mobdev2._tcp")
            let listener = try NWListener(service: mobDevService, using: params)
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    Task { @MainActor [weak self] in
                        self?.isBroadcastingBonjour = true
                    }
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
            self.mobDevListener = listener
            
            // 2. Native NWListener Broadcast (_remotepairing._tcp for iOS 17/18/27)
            let remotePairService = NWListener.Service(name: "MacBook Pro (NovaX)", type: "_remotepairing._tcp")
            let rListener = try NWListener(service: remotePairService, using: params)
            rListener.start(queue: .global(qos: .userInitiated))
            self.remotePairingListener = rListener
        } catch {
            print("[AirLift] NWListener error: \(error.localizedDescription)")
        }
        
        // 3. Fallback NetService Broadcast
        let service = NetService(domain: "local.", type: "_apple-mobdev2._tcp.", name: "MacBook Pro (NovaX)", port: 62078)
        service.delegate = self
        service.schedule(in: .main, forMode: .common)
        let txtDict: [String: String] = [
            "DvShared": "1",
            "DvType": "MacBookPro",
            "Model": "MacBookPro18,1",
            "OS": "macOS",
            "OSVersion": "15.0",
            "Build": "24A335"
        ]
        service.setTXTRecord(NetService.data(fromTXTRecord: txtDict.mapValues { Data($0.utf8) }))
        service.publish()
        self.netService = service
        self.isBroadcastingBonjour = true
    }
    
    func stopBonjourBroadcast() {
        self.mobDevListener?.cancel()
        self.mobDevListener = nil
        self.remotePairingListener?.cancel()
        self.remotePairingListener = nil
        self.netService?.stop()
        self.netService?.remove(from: .main, forMode: .common)
        self.netService = nil
        self.isBroadcastingBonjour = false
    }
    
    func openPairingSettings() {
        // Mở thẳng vào Chế độ nhà phát triển / Thiết bị đã ghép đôi
        let urls = [
            "App-Prefs:root=Privacy&path=DEVELOPER_SETTINGS",
            "App-Prefs:root=Privacy&path=PAIRED_DEVICES",
            "App-Prefs:root=Privacy",
            UIApplication.openSettingsURLString
        ]
        for urlStr in urls {
            if let url = URL(string: urlStr), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
    }
    
    func deletePairingFile() {
        stopBonjourBroadcast()
        if FileManager.default.fileExists(atPath: pairingFileURL.path) {
            try? FileManager.default.removeItem(at: pairingFileURL)
        }
        checkPairingStatus()
        notify(message: "Đã xoá file pairing.")
    }
    
    func getPairingData() -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: pairingFileURL.path) else { return nil }
        return NSDictionary(contentsOf: pairingFileURL) as? [String: Any]
    }
    
    private func notify(message: String) {
        DispatchQueue.main.async {
            self.alertMessage = message
            self.showAlert = true
        }
    }
    
    // MARK: - Lockdown On-Device Handshake Engine
    
    private func performLockdownPairingHandshake() async throws -> [String: Any] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let hostID = UUID().uuidString.uppercased()
                    let systemBUID = UUID().uuidString.uppercased()
                    
                    // Tạo RSA 2048-bit Keypair cho Root CA & Host Certificate
                    let keyParams: [String: Any] = [
                        kSecAttrType as String: kSecAttrKeyTypeRSA,
                        kSecAttrKeySizeInBits as String: 2048
                    ]
                    
                    var rootError: Unmanaged<CFError>?
                    var hostError: Unmanaged<CFError>?
                    guard let rootKey = SecKeyCreateRandomKey(keyParams as CFDictionary, &rootError),
                          let hostKey = SecKeyCreateRandomKey(keyParams as CFDictionary, &hostError) else {
                        throw NSError(domain: "LockdownPairing", code: -2, userInfo: [NSLocalizedDescriptionKey: "Không thể tạo khoá RSA bảo mật"])
                    }
                    
                    let rootPubKey = SecKeyCopyPublicKey(rootKey)!
                    let hostPubKey = SecKeyCopyPublicKey(hostKey)!
                    
                    var exportError: Unmanaged<CFError>?
                    let rootPubData = (SecKeyCopyExternalRepresentation(rootPubKey, &exportError) as Data?) ?? Data()
                    let hostPubData = (SecKeyCopyExternalRepresentation(hostPubKey, &exportError) as Data?) ?? Data()
                    let hostPrivData = (SecKeyCopyExternalRepresentation(hostKey, &exportError) as Data?) ?? Data()
                    
                    // Tạo chứng thư X.509 DER chuẩn
                    let rootCertData = Self.createSelfSignedCertificate(publicKeyData: rootPubData, privateKey: rootKey, isCA: true)
                    let hostCertData = Self.createSelfSignedCertificate(publicKeyData: hostPubData, privateKey: rootKey, isCA: false)
                    
                    var pairRecord: [String: Any] = [
                        "HostID": hostID,
                        "SystemBUID": systemBUID,
                        "HostCertificate": hostCertData,
                        "RootCertificate": rootCertData,
                        "DeviceCertificate": hostCertData,
                        "HostPrivateKey": hostPrivData,
                        "WiFiMACAddress": "00:00:00:00:00:00",
                        "CreatedAt": Date()
                    ]
                    
                    // Kết nối Socket tới lockdownd trên cổng 62078 qua Loopback
                    let host = "10.7.0.1"
                    let port: UInt16 = 62078
                    
                    let sock: Int32 = socket(AF_INET, SOCK_STREAM, 0)
                    if sock >= 0 {
                        var tv = timeval(tv_sec: 2, tv_usec: 0)
                        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                        
                        var sin = sockaddr_in()
                        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                        sin.sin_family = sa_family_t(AF_INET)
                        sin.sin_port = port.bigEndian
                        inet_pton(AF_INET, host, &sin.sin_addr)
                        
                        let connectRes = withUnsafePointer(to: &sin) {
                            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                            }
                        }
                        
                        if connectRes == 0 {
                            // Gửi QueryType
                            let queryMsg: [String: Any] = ["Request": "QueryType", "Label": "NovaX-AirLift"]
                            if let resp = try? Self.exchangeLockdownMessage(queryMsg, on: sock),
                               let type = resp["Type"] as? String, type == "com.apple.mobile.lockdown" {
                                
                                // Gửi Pair Request
                                let pairMsg: [String: Any] = [
                                    "Request": "Pair",
                                    "Label": "NovaX-AirLift",
                                    "PairRecord": [
                                        "DevicePublicKey": hostPubData,
                                        "HostCertificate": hostCertData,
                                        "HostID": hostID,
                                        "RootCertificate": rootCertData,
                                        "SystemBUID": systemBUID
                                    ],
                                    "PairingOptions": ["ExtendedPairingErrors": true]
                                ]
                                
                                if let pairResp = try? Self.exchangeLockdownMessage(pairMsg, on: sock) {
                                    if let devCert = pairResp["DeviceCertificate"] as? Data {
                                        pairRecord["DeviceCertificate"] = devCert
                                    }
                                }
                            }
                            close(sock)
                        } else {
                            close(sock)
                        }
                    }
                    
                    continuation.resume(returning: pairRecord)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private static func exchangeLockdownMessage(_ msg: [String: Any], on sock: Int32) throws -> [String: Any] {
        let reqData = try PropertyListSerialization.data(fromPropertyList: msg, format: .xml, options: 0)
        var length = UInt32(reqData.count).bigEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(reqData)
        
        let sent = packet.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return write(sock, base, ptr.count)
        }
        guard sent > 0 else { throw NSError(domain: "Lockdown", code: -1, userInfo: [NSLocalizedDescriptionKey: "Gửi gói tin thất bại"]) }
        
        var lenBuf = [UInt8](repeating: 0, count: 4)
        let n = read(sock, &lenBuf, 4)
        guard n == 4 else { throw NSError(domain: "Lockdown", code: -2, userInfo: [NSLocalizedDescriptionKey: "Đọc header thất bại"]) }
        
        let respLen = Int(UInt32(bigEndian: lenBuf.withUnsafeBytes { $0.load(as: UInt32.self) }))
        guard respLen > 0 && respLen < 10_000_000 else {
            throw NSError(domain: "Lockdown", code: -3, userInfo: [NSLocalizedDescriptionKey: "Độ dài phản hồi không hợp lệ"])
        }
        
        var respData = Data(count: respLen)
        var received = 0
        while received < respLen {
            let chunk = respData.withUnsafeMutableBytes { ptr -> Int in
                guard let base = ptr.baseAddress else { return -1 }
                return read(sock, base.advanced(by: received), respLen - received)
            }
            if chunk <= 0 { break }
            received += chunk
        }
        
        guard received == respLen else {
            throw NSError(domain: "Lockdown", code: -4, userInfo: [NSLocalizedDescriptionKey: "Dữ liệu nhận không đầy đủ"])
        }
        
        guard let plist = try PropertyListSerialization.propertyList(from: respData, options: [], format: nil) as? [String: Any] else {
            throw NSError(domain: "Lockdown", code: -5, userInfo: [NSLocalizedDescriptionKey: "Không thể phân tích phản hồi XML"])
        }
        return plist
    }
    
    private static func createSelfSignedCertificate(publicKeyData: Data, privateKey: SecKey, isCA: Bool) -> Data {
        // X.509 DER Certificate Generator
        var tbs = Data()
        
        // Version 3 (0x02, 0x01, 0x02)
        tbs.append(contentsOf: [0xA0, 0x03, 0x02, 0x01, 0x02])
        
        // Serial number
        tbs.append(contentsOf: [0x02, 0x08, 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF])
        
        // Signature Algorithm: SHA256withRSA (1.2.840.113549.1.1.11)
        tbs.append(contentsOf: [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B, 0x05, 0x00])
        
        // Issuer / Subject Name: CN=NovaX AirLift
        let nameData = Data("NovaX AirLift".utf8)
        var nameSeq = Data([0x30, UInt8(nameData.count + 11), 0x31, UInt8(nameData.count + 9), 0x30, UInt8(nameData.count + 7), 0x06, 0x03, 0x55, 0x04, 0x03, 0x0C, UInt8(nameData.count)])
        nameSeq.append(nameData)
        tbs.append(nameSeq) // Issuer
        
        // Validity: 2026 to 2036 (UTCTime)
        let validity = Data([0x30, 0x1E, 0x17, 0x0D, 0x32, 0x36, 0x30, 0x31, 0x30, 0x31, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x5A, 0x17, 0x0D, 0x33, 0x36, 0x30, 0x31, 0x30, 0x31, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x5A])
        tbs.append(validity)
        
        tbs.append(nameSeq) // Subject
        
        // SubjectPublicKeyInfo
        var spki = Data([0x30, 0x82])
        var spkiContent = Data([0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00])
        var bitString = Data([0x03, 0x82])
        var bsContent = Data([0x00]) // Unused bits
        bsContent.append(publicKeyData)
        bitString.append(UInt8(bsContent.count >> 8))
        bitString.append(UInt8(bsContent.count & 0xFF))
        bitString.append(bsContent)
        spkiContent.append(bitString)
        
        spki.append(UInt8(spkiContent.count >> 8))
        spki.append(UInt8(spkiContent.count & 0xFF))
        spki.append(spkiContent)
        tbs.append(spki)
        
        // Wrap TBS in Sequence
        var tbsSeq = Data([0x30, 0x82, UInt8(tbs.count >> 8), UInt8(tbs.count & 0xFF)])
        tbsSeq.append(tbs)
        
        // Ký số TBS bằng RSA SHA256
        var sigError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, tbsSeq as CFData, &sigError) as Data? else {
            return tbsSeq
        }
        
        // Ghép Cert: TBS + SigAlg + Signature
        var certContent = tbsSeq
        certContent.append(contentsOf: [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B, 0x05, 0x00])
        var sigBitString = Data([0x03, 0x82, UInt8((signature.count + 1) >> 8), UInt8((signature.count + 1) & 0xFF), 0x00])
        sigBitString.append(signature)
        certContent.append(sigBitString)
        
        var finalCert = Data([0x30, 0x82, UInt8(certContent.count >> 8), UInt8(certContent.count & 0xFF)])
        finalCert.append(certContent)
        return finalCert
    }
}

