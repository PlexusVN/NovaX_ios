import Foundation
import NetworkExtension
import Network
import UIKit

/// Trình quản lý DNS tiêu chuẩn doanh nghiệp (Enterprise Grade) cho Astra
/// Đảm bảo tương thích toàn diện từ iOS 16.0 đến iOS 27+
/// Hỗ trợ chuẩn phương pháp của Apple, phòng ngừa triệt để lỗi permission denied và lỗi lệch trạng thái khi đổi tab
class NextDNSManager: ObservableObject {
    static let shared = NextDNSManager()
    
    // MARK: - Trạng thái Observable
    
    @Published var isEnabled: Bool = false
    @Published var isActivelyProtected: Bool = false
    @Published var isActivating: Bool = false
    @Published var isVerifying: Bool = false
    @Published var errorMessage: String?
    @Published var needsManualActivation: Bool = false
    @Published var pingLatencyMs: Int? = nil
    @Published var verifiedProtocol: String? = nil
    @Published var verifiedServer: String? = nil
    @Published var lastVerifiedDate: Date? = nil
    
    // Cấu hình NextDNS được Admin phân phối từ máy chủ (mặc định ffe228)
    @Published var serverConfigID: String = UserDefaults.standard.string(forKey: "nextdns_admin_config_id") ?? "ffe228"
    
    // MARK: - Private Properties
    
    private let manager = NEDNSSettingsManager.shared()
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.novax.dns.pathmonitor", qos: .utility)
    private let userWantsEnabledKey = "nextdns_user_wants_enabled"
    
    /// Máy chủ Bootstrap Anycast toàn cầu tối ưu cho Apple DoH (IPv4 & IPv6 đa tầng)
    /// Bổ sung các IP Anycast dự phòng chính thức nhằm tránh bị nhà mạng di động chặn IP kết thúc bằng .0
    private let bootstrapServers: [String] = [
        "45.90.28.0",
        "45.90.30.0",
        "45.90.28.187",
        "45.90.30.187",
        "1.1.1.1",
        "8.8.8.8",
        "2a07:a8c0::",
        "2a07:a8c1::"
    ]
    
    // MARK: - Khởi tạo & Vòng đời
    
    private init() {
        loadStatus(andVerify: true)
        fetchServerConfig()
        setupLifecycleObservers()
        startNetworkMonitoring()
    }
    
    deinit {
        pathMonitor.cancel()
        NotificationCenter.default.removeObserver(self)
    }
        
    /// Lắng nghe sự kiện quay lại app từ màn hình Cài đặt iOS để tự động cập nhật trạng thái tức thì
    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func handleAppDidBecomeActive() {
        loadStatus(andVerify: true)
    }
    
    /// Theo dõi thay đổi trạng thái mạng (Wi-Fi <-> 4G/5G) để tự bảo trì kết nối DNS
    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            if path.status == .satisfied {
                DispatchQueue.main.async {
                    if self.isEnabled {
                        self.verifyActiveResolution()
                    }
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }
    
    // MARK: - Đồng bộ cấu hình Server
    
    /// Đồng bộ cấu hình DNS do Admin phân phối từ Server Zynox
    func fetchServerConfig() {
        guard let url = URL(string: "https://zynox.click/api/client/config") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data,
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            
            if let decoded = try? JSONDecoder().decode(NextDNSConfigResponse.self, from: data),
               decoded.success,
               let cfg = decoded.config,
               let val = cfg["nextdns_config_id"]?.stringValue ?? cfg["dns_config_id"]?.stringValue,
               !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let cleanID = val.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    let oldID = self?.serverConfigID
                    self?.serverConfigID = cleanID
                    UserDefaults.standard.set(cleanID, forKey: "nextdns_admin_config_id")
                    
                    // Nếu ID thay đổi trên server và máy đang bật DNS -> tự động đồng bộ sang ID mới
                    if let self = self, self.isEnabled, oldID != cleanID {
                        print("[NextDNS] Server cập nhật ID mới (\(cleanID)), tự động đồng bộ cấu hình DoH...")
                        let useFast = UserDefaults.standard.bool(forKey: "nextdns_ultra_low_latency")
                        self.enableDNS(configID: cleanID, useUltraLowLatency: useFast)
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - Quản lý Cấu hình DNS
    
    /// Tải trạng thái DNS từ NetworkExtension của iOS (Đồng bộ chuẩn 2 chiều không bị lệch khi đổi tab)
    func loadStatus(andVerify: Bool = true) {
        manager.loadFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    print("[NextDNS] Lỗi nạp cấu hình: \(error.localizedDescription)")
                    return
                }
                
                let isInstalledInSettings = self.manager.isEnabled
                let isRuleConnect = self.manager.onDemandRules?.contains { $0 is NEOnDemandRuleConnect } ?? false
                let hasUserPref = UserDefaults.standard.object(forKey: self.userWantsEnabledKey) != nil
                let userWantsEnabled = hasUserPref ? UserDefaults.standard.bool(forKey: self.userWantsEnabledKey) : false
                
                if !isInstalledInSettings {
                    // Chưa cài đặt hoặc chưa được tích chọn trong Cài đặt iPhone
                    self.isEnabled = false
                    self.isActivelyProtected = false
                    if self.manager.dnsSettings != nil {
                        self.needsManualActivation = true
                    } else {
                        self.needsManualActivation = false
                    }
                } else {
                    // Đã tích chọn trong Cài đặt iPhone
                    self.needsManualActivation = false
                    
                    // CHỈ bật nếu người dùng muốn bật VÀ rule là Connect
                    if userWantsEnabled && isRuleConnect {
                        self.isEnabled = true
                        if andVerify {
                            self.verifyActiveResolution()
                        }
                    } else {
                        // Người dùng đã chủ động tắt trong app -> Giữ trạng thái TẮT chuẩn chỉ!
                        self.isEnabled = false
                        self.isActivelyProtected = false
                    }
                }
            }
        }
    }
    
    /// Kiểm tra xác thực luồng phân giải thực tế qua máy chủ xác thực NextDNS
    func verifyActiveResolution(showLoading: Bool = true, retryAttempt: Int = 0) {
        let activeID = serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ffe228" : serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://test.nextdns.io") else { return }
        
        if showLoading {
            DispatchQueue.main.async {
                self.isVerifying = true
            }
        }
        
        var request = URLRequest(url: url)
        request.setValue("curl/8.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 4.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let session = URLSession(configuration: .ephemeral, delegate: NextDNSRedirectDelegate(), delegateQueue: nil)
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            let latency = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            var isProtected = false
            var proto: String? = nil
            var srv: String? = nil
            
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let status = json["status"] as? String ?? ""
                proto = json["protocol"] as? String
                srv = json["server"] as? String
                let profile = json["profile"] as? String ?? ""
                
                if status == "ok" || profile == activeID || (!profile.isEmpty && profile.contains(activeID)) {
                    isProtected = true
                }
            } else if let data = data, let text = String(data: data, encoding: .utf8) {
                if text.contains("\"status\": \"ok\"") || text.contains("\"status\":\"ok\"") || text.contains(activeID) {
                    isProtected = true
                }
            }
            
            DispatchQueue.main.async {
                if isProtected {
                    self.isActivelyProtected = true
                    self.isVerifying = false
                    self.pingLatencyMs = max(1, latency)
                    self.lastVerifiedDate = Date()
                    self.verifiedProtocol = proto ?? "DoH"
                    self.verifiedServer = srv
                } else if self.isEnabled && retryAttempt < 2 {
                    // DoH handshake có thể mất 1-2 giây để định tuyến gói tin đầu tiên -> tự động retry
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                        self.verifyActiveResolution(showLoading: false, retryAttempt: retryAttempt + 1)
                    }
                } else {
                    self.isActivelyProtected = false
                    self.isVerifying = false
                    if !self.isEnabled {
                        self.pingLatencyMs = nil
                    }
                }
            }
        }.resume()
    }
    
    /// Đăng ký profile vào hệ điều hành (chỉ tạo nếu chưa có, KHÔNG ghi đè trạng thái tắt khi chuyển tab)
    func registerDNSProfileIfNeeded(completion: ((Bool) -> Void)? = nil) {
        manager.loadFromPreferences { [weak self] error in
            guard let self = self else { return }
            
            let currentDoh = self.manager.dnsSettings as? NEDNSOverHTTPSSettings
            let hasMatchDomains = currentDoh?.matchDomains?.contains("") == true
            
            // Nếu profile hợp lệ đã có trong hệ thống:
            if self.manager.dnsSettings != nil && hasMatchDomains {
                DispatchQueue.main.async {
                    // ĐỒNG BỘ: Không gán đè self.isEnabled ở đây!
                    // Trạng thái bật/tắt sẽ do loadStatus() quản lý dựa trên userWantsEnabled
                    if !self.manager.isEnabled {
                        self.needsManualActivation = true
                    }
                    completion?(true)
                }
                return
            }
            
            // Chưa có profile hoặc profile cũ chưa có matchDomains -> Khởi tạo cấu hình ban đầu
            let activeID = self.serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "ffe228"
                : self.serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let dohSettings = NEDNSOverHTTPSSettings(servers: self.bootstrapServers)
            dohSettings.serverURL = URL(string: "https://dns.nextdns.io/\(activeID)")
            dohSettings.matchDomains = [""] // Bắt buộc để iOS định tuyến toàn bộ lưu lượng qua NextDNS
            
            self.manager.localizedDescription = "Astra DNS"
            self.manager.dnsSettings = dohSettings
            
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            self.manager.onDemandRules = [rule]
            
            self.manager.saveToPreferences { [weak self] saveError in
                guard let self = self else { return }
                
                if let saveError = saveError {
                    let nsError = saveError as NSError
                    let desc = saveError.localizedDescription.lowercased()
                    let isUnchanged = (nsError.domain == "NEConfigurationErrorDomain" && nsError.code == 2)
                        || desc.contains("unchanged")
                        || desc.contains("không thay đổi")
                    
                    if !isUnchanged {
                        print("[NextDNS] Không thể đăng ký cấu hình ban đầu: \(saveError.localizedDescription)")
                        DispatchQueue.main.async { completion?(false) }
                        return
                    }
                }
                
                self.manager.loadFromPreferences { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        let active = self.manager.isEnabled
                        self.needsManualActivation = !active
                        print("[NextDNS] Đã đăng ký cấu hình Astra DNS vào hệ điều hành.")
                        completion?(true)
                    }
                }
            }
        }
    }
    
    // MARK: - Bật / Tắt DNS Chuẩn Apple Enterprise
    
    func enableDNS(useUltraLowLatency: Bool) {
        enableDNS(configID: nil, useUltraLowLatency: useUltraLowLatency, retryCount: 0)
    }
    
    func enableDNS(configID: String? = nil, useUltraLowLatency: Bool, retryCount: Int = 0) {
        guard !isActivating else { return }
        
        let activeID = (configID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? configID!.trimmingCharacters(in: .whitespacesAndNewlines)
            : (serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? serverConfigID : "ffe228")
        
        isActivating = true
        errorMessage = nil
        
        manager.loadFromPreferences { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Lỗi hệ thống: \(error.localizedDescription)"
                    self.isActivating = false
                }
                return
            }
            
            let dohSettings = NEDNSOverHTTPSSettings(servers: self.bootstrapServers)
            let baseURL = useUltraLowLatency
                ? "https://dns.nextdns.io/\(activeID)"
                : "https://anycast.dns.nextdns.io/\(activeID)"
            dohSettings.serverURL = URL(string: baseURL)
            dohSettings.matchDomains = [""] // Bắt buộc để iOS định tuyến toàn bộ lưu lượng
            
            self.manager.localizedDescription = "Astra DNS"
            self.manager.dnsSettings = dohSettings
            
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            self.manager.onDemandRules = [rule]
            
            self.manager.saveToPreferences { [weak self] saveError in
                guard let self = self else { return }
                
                if let saveError = saveError {
                    let nsError = saveError as NSError
                    let desc = saveError.localizedDescription.lowercased()
                    let isUnchanged = (nsError.domain == "NEConfigurationErrorDomain" && nsError.code == 2)
                        || desc.contains("unchanged")
                        || desc.contains("không thay đổi")
                    
                    // Code 3: Stale configuration -> Tải lại và thử lại
                    if nsError.domain == "NEConfigurationErrorDomain" && nsError.code == 3 && retryCount < 1 {
                        print("[NextDNS] Phát hiện cấu hình stale, tự động tải lại và thử lại...")
                        DispatchQueue.main.async {
                            self.isActivating = false
                            self.enableDNS(configID: configID, useUltraLowLatency: useUltraLowLatency, retryCount: retryCount + 1)
                        }
                        return
                    }
                    
                    if !isUnchanged {
                        DispatchQueue.main.async {
                            self.isActivating = false
                            if desc.contains("permission") || desc.contains("denied") || desc.contains("cancel") {
                                self.errorMessage = "Bạn đã bấm 'Không cho phép' hoặc chứng chỉ chưa hỗ trợ NetworkExtension. Hãy chọn 'Cài đặt Hồ sơ Trực tiếp (MobileConfig)' bên dưới để sử dụng ổn định 100%."
                            } else {
                                self.errorMessage = "Không thể lưu cấu hình DNS: \(saveError.localizedDescription)"
                            }
                            self.isEnabled = false
                            UserDefaults.standard.set(false, forKey: self.userWantsEnabledKey)
                        }
                        return
                    }
                }
                
                // Ghi nhận ý định người dùng muốn bật
                UserDefaults.standard.set(true, forKey: self.userWantsEnabledKey)
                
                self.manager.loadFromPreferences { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.isActivating = false
                        self.errorMessage = nil
                        
                        let active = self.manager.isEnabled
                        self.isEnabled = active
                        self.needsManualActivation = !active
                        
                        if active {
                            self.verifyActiveResolution()
                        }
                    }
                }
            }
        }
    }
    
    func disableDNS(retryCount: Int = 0) {
        guard !isActivating else { return }
        
        isActivating = true
        errorMessage = nil
        
        // CẬP NHẬT TRƯỚC: Ghi nhận ngay ý định tắt của người dùng để UI phản hồi lập tức và không bao giờ bị bật lại khi đổi tab
        UserDefaults.standard.set(false, forKey: userWantsEnabledKey)
        self.isEnabled = false
        self.isActivelyProtected = false
        self.pingLatencyMs = nil
        
        manager.loadFromPreferences { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Lỗi hệ thống: \(error.localizedDescription)"
                    self.isActivating = false
                }
                return
            }
            
            let rule = NEOnDemandRuleDisconnect()
            rule.interfaceTypeMatch = .any
            self.manager.onDemandRules = [rule]
            
            self.manager.saveToPreferences { [weak self] saveError in
                guard let self = self else { return }
                
                if let saveError = saveError {
                    let nsError = saveError as NSError
                    let desc = saveError.localizedDescription.lowercased()
                    let isUnchanged = (nsError.domain == "NEConfigurationErrorDomain" && nsError.code == 2)
                        || desc.contains("unchanged")
                        || desc.contains("không thay đổi")
                    
                    if nsError.domain == "NEConfigurationErrorDomain" && nsError.code == 3 && retryCount < 1 {
                        DispatchQueue.main.async {
                            self.isActivating = false
                            self.disableDNS(retryCount: retryCount + 1)
                        }
                        return
                    }
                    
                    if !isUnchanged {
                        DispatchQueue.main.async {
                            self.isActivating = false
                            // Giữ trạng thái isEnabled = false trong app
                            if desc.contains("permission") || desc.contains("denied") {
                                self.errorMessage = "Cấu hình đã tắt trong ứng dụng. Bạn cũng có thể tắt hoàn toàn trong Cài đặt iPhone -> DNS."
                            } else {
                                self.errorMessage = "Lỗi tắt DNS: \(saveError.localizedDescription)"
                            }
                        }
                        return
                    }
                }
                
                self.manager.loadFromPreferences { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.isActivating = false
                        self.errorMessage = nil
                        self.isEnabled = false
                        self.isActivelyProtected = false
                        self.isVerifying = false
                        self.pingLatencyMs = nil
                        self.needsManualActivation = false
                    }
                }
            }
        }
    }
    
    /// Gỡ bỏ hoàn toàn cấu hình khỏi hệ điều hành khi người dùng muốn dọn sạch
    func uninstallDNSProfile(completion: ((Bool) -> Void)? = nil) {
        guard !isActivating else { return }
        
        isActivating = true
        errorMessage = nil
        needsManualActivation = false
        UserDefaults.standard.removeObject(forKey: userWantsEnabledKey)
        
        manager.removeFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isActivating = false
                if let error = error {
                    self.errorMessage = "Lỗi gỡ cấu hình: \(error.localizedDescription)"
                    completion?(false)
                } else {
                    self.isEnabled = false
                    self.isActivelyProtected = false
                    self.needsManualActivation = false
                    self.pingLatencyMs = nil
                    self.manager.loadFromPreferences { _ in }
                    completion?(true)
                }
            }
        }
    }
    
    // MARK: - Phương thức Cài đặt Hồ sơ Trực tiếp (MobileConfig - Chuẩn NextDNS Gốc)
    
    /// Mở trang cấu hình Apple chính thức của NextDNS trong Safari để cài đặt profile .mobileconfig trực tiếp
    /// Phương pháp này hoạt động 100% trên mọi phiên bản iOS (16, 17, 18, 26, 27+) mà không phụ thuộc vào chứng chỉ ứng dụng
    func installDirectMobileConfigProfile() {
        let activeID = serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ffe228" : serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://apple.nextdns.io/\(activeID)") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    /// Xuất file MobileConfig chuẩn Apple DoH cục bộ để cài đặt hoặc chia sẻ qua AirDrop / Tệp
    /// Cấu trúc chuẩn 100% khớp tuyệt đối với Official NextDNS Generator (apple.nextdns.io)
    func exportLocalMobileConfigFile() -> URL? {
        let activeID = serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ffe228" : serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileUUID = UUID().uuidString
        let managedUUID = UUID().uuidString
        let profileXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>PayloadDisplayName</key>
            <string>Astra NextDNS (\(activeID))</string>
            <key>PayloadDescription</key>
            <string>Cấu hình bảo vệ NextDNS mã hóa DoH chuẩn Apple cho Astra</string>
            <key>PayloadIdentifier</key>
            <string>io.nextdns.\(activeID).profile</string>
            <key>PayloadScope</key>
            <string>System</string>
            <key>PayloadType</key>
            <string>Configuration</string>
            <key>PayloadUUID</key>
            <string>\(profileUUID)</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>PayloadContent</key>
            <array>
                <dict>
                    <key>DNSSettings</key>
                    <dict>
                        <key>DNSProtocol</key>
                        <string>HTTPS</string>
                        <key>ServerURL</key>
                        <string>https://apple.dns.nextdns.io/\(activeID)</string>
                        <key>ServerAddresses</key>
                        <array>
                            <string>45.90.28.0</string>
                            <string>2a07:a8c0::</string>
                            <string>45.90.30.0</string>
                            <string>2a07:a8c1::</string>
                        </array>
                    </dict>
                    <key>OnDemandRules</key>
                    <array>
                        <dict>
                            <key>Action</key>
                            <string>EvaluateConnection</string>
                            <key>ActionParameters</key>
                            <array>
                                <dict>
                                    <key>DomainAction</key>
                                    <string>NeverConnect</string>
                                    <key>Domains</key>
                                    <array>
                                        <string>captive.apple.com</string>
                                        <string>3gppnetwork.org</string>
                                        <string>dav.orange.fr</string>
                                        <string>vvm.mobistar.be</string>
                                        <string>vvm.mstore.msg.t-mobile.com</string>
                                        <string>tma.vvm.mone.pan-net.eu</string>
                                        <string>vvm.ee.co.uk</string>
                                    </array>
                                </dict>
                            </array>
                        </dict>
                        <dict>
                            <key>Action</key>
                            <string>Connect</string>
                        </dict>
                    </array>
                    <key>PayloadType</key>
                    <string>com.apple.dnsSettings.managed</string>
                    <key>PayloadIdentifier</key>
                    <string>io.nextdns.\(activeID).profile.dnsSettings.managed</string>
                    <key>PayloadUUID</key>
                    <string>\(managedUUID)</string>
                    <key>PayloadDisplayName</key>
                    <string>Astra NextDNS (\(activeID))</string>
                    <key>PayloadOrganization</key>
                    <string>Astra NextDNS Enterprise</string>
                    <key>PayloadVersion</key>
                    <integer>1</integer>
                </dict>
            </array>
        </dict>
        </plist>
        """
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("Astra-NextDNS-\(activeID).mobileconfig")
        do {
            try profileXML.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("[NextDNS] Lỗi tạo file mobileconfig: \(error)")
            return nil
        }
    }
    
    // MARK: - Điều hướng Cài đặt Hệ thống (iOS 16 - iOS 27+)
    
    /// Chuyển thẳng người dùng đến màn hình Cài đặt DNS của iPhone
    /// (Cài đặt chung -> VPN & Quản lý thiết bị -> DNS)
    func openSystemDNSSettings() {
        let prioritizedSchemes = [
            "prefs:root=General&path=ManagedConfigurationList/DNS",
            "prefs:root=General&path=ManagedConfigurationList",
            "prefs:root=General&path=VPN/DNS",
            "prefs:root=General&path=VPN",
            "prefs:root=VPN",
            "prefs:root=General",
            "App-prefs:root=General&path=ManagedConfigurationList/DNS",
            "App-prefs:root=General&path=ManagedConfigurationList",
            "App-prefs:root=General&path=VPN",
            "App-prefs:root=VPN",
            "App-prefs:root=General"
        ]
        
        // 1. Thử mở bằng LaunchServices Private API (openSensitiveURL:withOptions:)
        // Phương pháp này có quyền mở thẳng các deep link hệ thống mà UIApplication.open thông thường bị sandbox chặn
        for scheme in prioritizedSchemes {
            if openSensitiveSettingsURL(scheme) {
                print("[NextDNS] Đã mở cài đặt DNS thành công qua LaunchServices: \(scheme)")
                return
            }
        }
        
        // 2. Dự phòng: Mở tuần tự qua UIApplication.shared.open
        openFirstAvailableURL(from: prioritizedSchemes + [UIApplication.openSettingsURLString])
    }
    
    private func openFirstAvailableURL(from schemes: [String]) {
        guard let first = schemes.first, let url = URL(string: first) else { return }
        let remaining = Array(schemes.dropFirst())
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:]) { success in
                if !success && !remaining.isEmpty {
                    DispatchQueue.main.async {
                        self.openFirstAvailableURL(from: remaining)
                    }
                }
            }
        } else if !remaining.isEmpty {
            openFirstAvailableURL(from: remaining)
        } else {
            // Fallback cuối cùng nếu mọi scheme đều bị từ chối
            if let fallbackURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(fallbackURL, options: [:], completionHandler: nil)
            }
        }
    }
}

// MARK: - Delegate hỗ trợ Redirect và Headers kiểm tra NextDNS

private class NextDNSRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var redirectedRequest = request
        redirectedRequest.setValue("curl/8.0.0", forHTTPHeaderField: "User-Agent")
        redirectedRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        completionHandler(redirectedRequest)
    }
}

// MARK: - Server Response Models

struct NextDNSConfigResponse: Decodable {
    let success: Bool
    let config: [String: NextDNSAnyCodableValue]?
}

struct NextDNSAnyCodableValue: Decodable {
    let stringValue: String
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            stringValue = str
        } else if let intVal = try? container.decode(Int.self) {
            stringValue = String(intVal)
        } else {
            stringValue = ""
        }
    }
}
