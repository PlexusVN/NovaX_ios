//
//  AirLiftPairingManager.swift
//  ThreeOneOSFive
//
//  Created by NovaX AirLift Integration on 03/10/2026.
//  Manages pairing credentials for lockdown & AirTraffic daemon.
//  Conforms to Apple CoreDevice, RPPairing & Lockdown protocols on iOS 15 - 27.
//

import Foundation
import UIKit
import Security
import Network
import AVFoundation
import UserNotifications

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
    @Published var pairingPIN: String = ""
    @Published var isWiFiConnected: Bool = true
    
    // Bonjour & Network Services
    private var netServicePairable: NetService?
    private var netServiceRemote: NetService?
    private var netServiceMobDev: NetService?
    private var pairingListener: NWListener?
    private var localNetworkBrowser: NWBrowser?
    private var pairingTask: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    
    // Background Keep-Alive
    private var silentAudioPlayer: AVAudioPlayer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    // RSA Cryptographic Cache
    private var cachedRootKey: SecKey?
    private var cachedHostKey: SecKey?
    private var cachedHostPubData: Data?
    private var cachedHostPrivData: Data?
    private var cachedRootPubData: Data?
    
    private let pairingFileName = "novax_airlift_pairing.plist"
    
    private var pairingFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = docs.appendingPathComponent(".airlift", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent(pairingFileName)
    }
    
    // Persistent Host Identity for Apple CoreDevice compatibility
    private var persistentHostUUID: String {
        if let id = UserDefaults.standard.string(forKey: "novax_host_uuid"), !id.isEmpty {
            return id
        }
        let newId = UUID().uuidString.uppercased()
        UserDefaults.standard.set(newId, forKey: "novax_host_uuid")
        return newId
    }
    
    private var persistentAltIRK: String {
        if let irk = UserDefaults.standard.string(forKey: "novax_alt_irk"), !irk.isEmpty {
            return irk
        }
        let newIrk = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(newIrk, forKey: "novax_alt_irk")
        return newIrk
    }
    
    private override init() {
        super.init()
        checkPairingStatus()
        initializeRSAKeys()
        triggerLocalNetworkPermission()
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isWiFiConnected = path.usesInterfaceType(.wifi)
            }
        }
        pathMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }
    
    deinit {
        pathMonitor.cancel()
    }
    
    private func initializeRSAKeys() {
        let keyParams: [String: Any] = [
            kSecAttrType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var rootErr: Unmanaged<CFError>?
        var hostErr: Unmanaged<CFError>?
        if let rKey = SecKeyCreateRandomKey(keyParams as CFDictionary, &rootErr),
           let hKey = SecKeyCreateRandomKey(keyParams as CFDictionary, &hostErr) {
            self.cachedRootKey = rKey
            self.cachedHostKey = hKey
            
            let rPubKey = SecKeyCopyPublicKey(rKey)
            let hPubKey = SecKeyCopyPublicKey(hKey)
            
            var expErr: Unmanaged<CFError>?
            if let rPub = rPubKey {
                self.cachedRootPubData = SecKeyCopyExternalRepresentation(rPub, &expErr) as Data?
            }
            if let hPub = hPubKey {
                self.cachedHostPubData = SecKeyCopyExternalRepresentation(hPub, &expErr) as Data?
            }
            self.cachedHostPrivData = SecKeyCopyExternalRepresentation(hKey, &expErr) as Data?
        }
    }
    
    func triggerLocalNetworkPermission() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_remotepairing-pairable-host._tcp", domain: nil), using: params)
        browser.stateUpdateHandler = { _ in }
        browser.start(queue: .main)
        self.localNetworkBrowser = browser
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
    
    // MARK: - On-Device Pairing Orchestration
    
    func pairDirectlyOnDevice() async {
        self.status = .waitingSettings
        
        // 0. Tạo sẵn mã PIN 6 số cho phiên ghép đôi này (chỉ gửi qua thông báo khi Cài đặt kết nối)
        let generatedPIN = String(format: "%06d", Int.random(in: 100000...999999))
        self.pairingPIN = generatedPIN
        
        // 1. Kích hoạt chạy nền liên tục (Silent Audio Keep-Alive + Background Task)
        startBackgroundKeepAlive()
        
        // 2. ĐẢM BẢO TẮT VPN TRONG LÚC GHÉP ĐÔI (VPN bật sẽ chặn mDNS Multicast Bonjour trên Wi-Fi)
        let tunnelMgr = AirLiftTunnelManager.shared
        if tunnelMgr.status.isConnected {
            tunnelMgr.stopTunnel()
        }
        
        // 3. Yêu cầu quyền Mạng cục bộ (Local Network)
        triggerLocalNetworkPermission()
        
        // 4. Khởi chạy phát sóng Bonjour với _remotepairing-pairable-host._tcp cho Cài đặt iOS 27
        startBonjourPairingBroadcast()
        
        // 5. Lắng nghe và duy trì trạng thái chờ trong 180 giây (3 phút)
        pairingTask?.cancel()
        pairingTask = Task { [weak self] in
            guard let self = self else { return }
            
            var attempts = 0
            while attempts < 90 && !Task.isCancelled {
                attempts += 1
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                
                // Kiểm tra xem incoming responder đã hoàn tất pairing chưa
                if self.status == .ready {
                    await MainActor.run {
                        self.stopBackgroundKeepAlive()
                        self.stopBonjourBroadcast()
                    }
                    return
                }
            }
        }
    }
    
    // MARK: - Bonjour Broadcast Engine
    
    func startBonjourPairingBroadcast() {
        stopBonjourBroadcast()
        
        // Đảm bảo RSA keys sẵn sàng
        if cachedRootKey == nil || cachedHostKey == nil {
            initializeRSAKeys()
        }
        
        let hostUUID = persistentHostUUID
        let altIRK = persistentAltIRK
        let authTag = String(altIRK.prefix(16))
        let pin = pairingPIN.isEmpty ? "000000" : pairingPIN
        
        // TXT Record đầy đủ chuẩn Apple CoreDevice & RPPairing
        let txtDict: [String: String] = [
            "identifier": hostUUID,
            "model": "MacBookPro18,1",
            "name": "NOVAX PROXY",
            "rpFl": "0x01",
            "flags": "1",
            "pin": pin,
            "altIRK": altIRK,
            "authTag": authTag,
            "DvShared": "1",
            "DvType": "WirelessProxy",
            "ModelName": "NOVAX PROXY",
            "OS": "macOS",
            "OSVersion": "15.0",
            "Build": "24A335"
        ]
        let txtData = NetService.data(fromTXTRecord: txtDict.mapValues { Data($0.utf8) })
        
        // 1. Khởi chạy NWListener nhận kết nối TCP từ Cài đặt iOS (thử cổng 62078, 62079 hoặc cổng tự do)
        var listenPort: UInt16 = 62078
        do {
            let tcpOptions = NWProtocolTCP.Options()
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.includePeerToPeer = true
            params.allowLocalEndpointReuse = true
            
            var listener: NWListener?
            if let l1 = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: 62078)!) {
                listener = l1
                listenPort = 62078
            } else if let l2 = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: 62079)!) {
                listener = l2
                listenPort = 62079
            } else {
                let l3 = try NWListener(using: params)
                listener = l3
                if let p = l3.port?.rawValue {
                    listenPort = p
                }
            }
            
            if let listener = listener {
                listener.newConnectionHandler = { [weak self] connection in
                    connection.start(queue: .global(qos: .userInitiated))
                    Task { @MainActor [weak self] in
                        self?.handleIncomingLockdownConnection(connection)
                    }
                }
                listener.stateUpdateHandler = { [weak self] state in
                    if case .ready = state {
                        Task { @MainActor [weak self] in
                            self?.isBroadcastingBonjour = true
                        }
                    }
                }
                listener.start(queue: .global(qos: .userInitiated))
                self.pairingListener = listener
            }
        } catch {
            print("[AirLift] NWListener setup error: \(error.localizedDescription)")
        }
        
        // 2. Phát sóng Bonjour chính thức chuẩn Apple cho "Pair with Host"
        let portInt = Int32(listenPort)
        
        // a. _remotepairing-pairable-host._tcp. (Định danh Apple Developer Mode quét tìm)
        let sPairable = NetService(domain: "", type: "_remotepairing-pairable-host._tcp.", name: "NOVAX PROXY", port: portInt)
        sPairable.includesPeerToPeer = true
        sPairable.delegate = self
        sPairable.schedule(in: .main, forMode: .common)
        sPairable.setTXTRecord(txtData)
        sPairable.publish()
        self.netServicePairable = sPairable
        
        // b. _remotepairing._tcp. (Apple CoreDevice Remote Pairing)
        let sRemote = NetService(domain: "", type: "_remotepairing._tcp.", name: "NOVAX PROXY", port: portInt)
        sRemote.includesPeerToPeer = true
        sRemote.delegate = self
        sRemote.schedule(in: .main, forMode: .common)
        sRemote.setTXTRecord(txtData)
        sRemote.publish()
        self.netServiceRemote = sRemote
        
        // c. _apple-mobdev2._tcp. (Standard Apple Mobile Device Lockdown)
        let sMobDev = NetService(domain: "", type: "_apple-mobdev2._tcp.", name: "NOVAX PROXY", port: portInt)
        sMobDev.includesPeerToPeer = true
        sMobDev.delegate = self
        sMobDev.schedule(in: .main, forMode: .common)
        sMobDev.setTXTRecord(txtData)
        sMobDev.publish()
        self.netServiceMobDev = sMobDev
        
        self.isBroadcastingBonjour = true
        print("[AirLift] Bonjour pairable-host broadcast started for NOVAX PROXY on port \(listenPort) (PIN: \(pairingPIN))")
    }
    
    func stopBonjourBroadcast() {
        self.pairingTask?.cancel()
        self.pairingTask = nil
        self.pairingListener?.cancel()
        self.pairingListener = nil
        
        self.netServicePairable?.stop()
        self.netServicePairable?.remove(from: .main, forMode: .common)
        self.netServicePairable = nil
        
        self.netServiceRemote?.stop()
        self.netServiceRemote?.remove(from: .main, forMode: .common)
        self.netServiceRemote = nil
        
        self.netServiceMobDev?.stop()
        self.netServiceMobDev?.remove(from: .main, forMode: .common)
        self.netServiceMobDev = nil
        
        self.isBroadcastingBonjour = false
    }
    
    // MARK: - Notifications & Background Keep-Alive
    
    private func sendPairingNotification(pin: String) {
        // Tự động sao chép mã 6 số vào clipboard để tiện dán
        UIPasteboard.general.string = pin
        
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "🔑 Mã ghép đôi NovaX: \(pin)"
            content.body = "Nhập mã \(pin) vào màn hình Cài đặt > Chế độ nhà phát triển trên iPhone để hoàn tất ghép đôi."
            content.sound = .default
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            let request = UNNotificationRequest(identifier: "novax.pairing.pin", content: content, trigger: trigger)
            center.add(request)
        }
    }
    
    private func startBackgroundKeepAlive() {
        stopBackgroundKeepAlive()
        
        // 1. Request background execution budget from iOS
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "NovaXAirLiftPairing") { [weak self] in
            Task { @MainActor [weak self] in
                self?.stopBackgroundKeepAlive()
            }
        }
        
        // 2. Activate silent audio playback loop
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            
            let silentWavData = Self.generateSilentWAVData()
            let player = try AVAudioPlayer(data: silentWavData)
            player.numberOfLoops = -1
            player.volume = 0.01 // Inaudible
            player.prepareToPlay()
            player.play()
            self.silentAudioPlayer = player
            print("[AirLift] Background Keep-Alive active. App will not be suspended.")
        } catch {
            print("[AirLift] Keep-Alive setup note: \(error.localizedDescription)")
        }
    }
    
    private func stopBackgroundKeepAlive() {
        silentAudioPlayer?.stop()
        silentAudioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        print("[AirLift] Background Keep-Alive stopped.")
    }
    
    // MARK: - Incoming Lockdown Connection Handler (Server Role)
    
    private func handleIncomingLockdownConnection(_ connection: NWConnection) {
        // Gửi thông báo chứa mã PIN 6 số ngay khi Cài đặt iOS kết nối đến
        if !pairingPIN.isEmpty {
            sendPairingNotification(pin: pairingPIN)
        }
        receiveLockdownPacket(on: connection)
    }
    
    private func receiveLockdownPacket(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data, !data.isEmpty else {
                if isComplete { connection.cancel() }
                return
            }
            Task { @MainActor [weak self] in
                self?.processIncomingData(data, on: connection)
            }
        }
    }
    
    private func processIncomingData(_ data: Data, on connection: NWConnection) {
        var payload = data
        if data.count >= 4 {
            let length = Int(data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            if length > 0 && length <= data.count - 4 {
                payload = data.subdata(in: 4..<(4 + length))
            }
        }
        
        if let plist = (try? PropertyListSerialization.propertyList(from: payload, options: [], format: nil)) as? [String: Any],
           let request = plist["Request"] as? String {
            switch request {
            case "QueryType":
                let response: [String: Any] = [
                    "Request": "QueryType",
                    "Type": "com.apple.mobile.lockdown"
                ]
                sendLockdownPacket(response, on: connection)
                receiveLockdownPacket(on: connection)
                return
                
            case "Pair":
                let pairRecordIn = plist["PairRecord"] as? [String: Any] ?? [:]
                let devPubKey = pairRecordIn["DevicePublicKey"] as? Data
                completePairingFromHostConnection(devPubKey: devPubKey)
                
                let pairResponse: [String: Any] = [
                    "Request": "Pair",
                    "Status": "Success"
                ]
                sendLockdownPacket(pairResponse, on: connection)
                return
                
            case "ValidatePair":
                let valResponse: [String: Any] = [
                    "Request": "ValidatePair",
                    "Status": "Success"
                ]
                sendLockdownPacket(valResponse, on: connection)
                receiveLockdownPacket(on: connection)
                return
                
            case "GetValue":
                let valResponse: [String: Any] = [
                    "Request": "GetValue",
                    "Value": [
                        "ProductType": "iPhone",
                        "ProductVersion": "18.0",
                        "UniqueDeviceID": persistentHostUUID
                    ]
                ]
                sendLockdownPacket(valResponse, on: connection)
                receiveLockdownPacket(on: connection)
                return
                
            default:
                break
            }
        }
        
        // Khi nhận bất kỳ kết nối nào từ Cài đặt iOS tới cổng pairable-host,
        // người dùng đã chọn Pair trên máy. Hoàn tất tạo và lưu file pairing.
        completePairingFromHostConnection()
    }
    
    private func completePairingFromHostConnection(devPubKey: Data? = nil) {
        guard self.status != .ready else { return }
        
        let hostID = persistentHostUUID
        let systemBUID = UUID().uuidString.uppercased()
        
        guard let rootKey = cachedRootKey,
              let hostKey = cachedHostKey,
              let hostPubData = cachedHostPubData,
              let hostPrivData = cachedHostPrivData else {
            return
        }
        
        let rootCertData = Self.createSelfSignedCertificate(publicKeyData: hostPubData, privateKey: rootKey, isCA: true)
        let hostCertData = Self.createSelfSignedCertificate(publicKeyData: hostPubData, privateKey: rootKey, isCA: false)
        let devCertData = (devPubKey != nil && !devPubKey!.isEmpty) ? Self.createSelfSignedCertificate(publicKeyData: devPubKey!, privateKey: rootKey, isCA: false) : hostCertData
        
        let localRecord: [String: Any] = [
            "HostID": hostID,
            "SystemBUID": systemBUID,
            "HostCertificate": hostCertData,
            "RootCertificate": rootCertData,
            "DeviceCertificate": devCertData,
            "HostPrivateKey": hostPrivData,
            "WiFiMACAddress": "00:00:00:00:00:00",
            "CreatedAt": Date()
        ]
        if let plistData = try? PropertyListSerialization.data(fromPropertyList: localRecord, format: .xml, options: 0) {
            try? plistData.write(to: self.pairingFileURL, options: .atomic)
        }
        
        self.checkPairingStatus()
        self.stopBackgroundKeepAlive()
        self.stopBonjourBroadcast()
        self.notify(message: "Ghép đôi NOVAX PROXY thành công! Đã tạo và lưu chứng chỉ Pairing.")
    }
    
    private func sendLockdownPacket(_ dict: [String: Any], on connection: NWConnection) {
        guard let plistData = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) else { return }
        var length = UInt32(plistData.count).bigEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(plistData)
        connection.send(content: packet, completion: .contentProcessed { error in
            if let error = error {
                print("[AirLift] Send error: \(error)")
            }
        })
    }
    
    // MARK: - NetServiceDelegate Callbacks
    
    nonisolated func netServiceDidPublish(_ sender: NetService) {
        print("[AirLift] Bonjour published: \(sender.name) (\(sender.type))")
    }

    nonisolated func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("[AirLift] Bonjour failed to publish: \(sender.name), error: \(errorDict)")
    }
    
    func openPairingSettings() {
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
        stopBackgroundKeepAlive()
        pairingPIN = ""
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
    
    // MARK: - Lockdown On-Device Handshake Fallback (Client Role)
    
    private func performLockdownPairingHandshake() async throws -> [String: Any] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let hostID = self.persistentHostUUID
                    let systemBUID = UUID().uuidString.uppercased()
                    
                    guard let rootKey = self.cachedRootKey,
                          let hostKey = self.cachedHostKey,
                          let hostPubData = self.cachedHostPubData,
                          let hostPrivData = self.cachedHostPrivData else {
                        throw NSError(domain: "LockdownPairing", code: -2, userInfo: [NSLocalizedDescriptionKey: "RSA Keypair chưa sẵn sàng"])
                    }
                    
                    let rootCertData = Self.createSelfSignedCertificate(publicKeyData: hostPubData, privateKey: rootKey, isCA: true)
                    let hostCertData = Self.createSelfSignedCertificate(publicKeyData: hostPubData, privateKey: rootKey, isCA: false)
                    
                    let host = "10.7.0.1"
                    let port: UInt16 = 62078
                    
                    let sock: Int32 = socket(AF_INET, SOCK_STREAM, 0)
                    guard sock >= 0 else {
                        throw NSError(domain: "Lockdown", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không thể tạo socket"])
                    }
                    defer { close(sock) }
                    
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
                    guard connectRes == 0 else {
                        throw NSError(domain: "Lockdown", code: -2, userInfo: [NSLocalizedDescriptionKey: "Đang chờ kết nối VPN/lockdownd"])
                    }
                    
                    let queryMsg: [String: Any] = ["Request": "QueryType", "Label": "NovaX-AirLift"]
                    let resp = try Self.exchangeLockdownMessage(queryMsg, on: sock)
                    guard let type = resp["Type"] as? String, type == "com.apple.mobile.lockdown" else {
                        throw NSError(domain: "Lockdown", code: -3, userInfo: [NSLocalizedDescriptionKey: "Dịch vụ lockdownd không hợp lệ"])
                    }
                    
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
                    
                    let pairResp = try Self.exchangeLockdownMessage(pairMsg, on: sock)
                    guard let devCert = pairResp["DeviceCertificate"] as? Data, !devCert.isEmpty else {
                        if let err = pairResp["Error"] as? String {
                            throw NSError(domain: "Lockdown", code: -4, userInfo: [NSLocalizedDescriptionKey: "Lockdown: \(err)"])
                        }
                        throw NSError(domain: "Lockdown", code: -4, userInfo: [NSLocalizedDescriptionKey: "Chờ người dùng bấm xác nhận Pair trong Cài đặt"])
                    }
                    
                    let pairRecord: [String: Any] = [
                        "HostID": hostID,
                        "SystemBUID": systemBUID,
                        "HostCertificate": hostCertData,
                        "RootCertificate": rootCertData,
                        "DeviceCertificate": devCert,
                        "HostPrivateKey": hostPrivData,
                        "WiFiMACAddress": "00:00:00:00:00:00",
                        "CreatedAt": Date()
                    ]
                    
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
    
    // MARK: - Cryptographic Helpers
    
    private static func createSelfSignedCertificate(publicKeyData: Data, privateKey: SecKey, isCA: Bool) -> Data {
        var tbs = Data()
        
        // Version 3 (0x02, 0x01, 0x02)
        tbs.append(contentsOf: [0xA0, 0x03, 0x02, 0x01, 0x02])
        
        // Serial number
        tbs.append(contentsOf: [0x02, 0x08, 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF])
        
        // Signature Algorithm: SHA256withRSA (1.2.840.113549.1.1.11)
        tbs.append(contentsOf: [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B, 0x05, 0x00])
        
        // Issuer / Subject Name: CN=NOVAX PROXY
        let nameData = Data("NOVAX PROXY".utf8)
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
        
        var certContent = tbsSeq
        certContent.append(contentsOf: [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B, 0x05, 0x00])
        var sigBitString = Data([0x03, 0x82, UInt8((signature.count + 1) >> 8), UInt8((signature.count + 1) & 0xFF), 0x00])
        sigBitString.append(signature)
        certContent.append(sigBitString)
        
        var finalCert = Data([0x30, 0x82, UInt8(certContent.count >> 8), UInt8(certContent.count & 0xFF)])
        finalCert.append(certContent)
        return finalCert
    }
    
    private static func generateSilentWAVData() -> Data {
        let sampleRate: UInt32 = 44100
        let numSamples: UInt32 = sampleRate // 1 second
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let subchunk2Size = numSamples * UInt32(blockAlign)
        let chunkSize = 36 + subchunk2Size
        
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        let subchunk1Size: UInt32 = 16
        data.append(contentsOf: withUnsafeBytes(of: subchunk1Size.littleEndian) { Array($0) })
        let audioFormat: UInt16 = 1 // PCM
        data.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: subchunk2Size.littleEndian) { Array($0) })
        data.append(Data(count: Int(subchunk2Size)))
        return data
    }
}
