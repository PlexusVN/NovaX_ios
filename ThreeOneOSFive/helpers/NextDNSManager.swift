import Foundation
import NetworkExtension
import Network
import UIKit

/// Trình quản lý DNS tiêu chuẩn doanh nghiệp (Enterprise Grade) cho NovaX
/// Đảm bảo tương thích toàn diện từ iOS 16.0 đến iOS 27+
class NextDNSManager: ObservableObject {
    static let shared = NextDNSManager()
    
    // MARK: - Trạng thái Observable
    
    @Published var isEnabled: Bool = false
    @Published var isActivelyProtected: Bool = false
    @Published var isActivating: Bool = false
    @Published var errorMessage: String?
    @Published var needsManualActivation: Bool = false
    
    // Cấu hình NextDNS được Admin phân phối từ máy chủ (mặc định ffe228)
    @Published var serverConfigID: String = UserDefaults.standard.string(forKey: "nextdns_admin_config_id") ?? "ffe228"
    
    // MARK: - Private Properties
    
    private let manager = NEDNSSettingsManager.shared()
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.novax.dns.pathmonitor", qos: .utility)
    
    /// Danh sách máy chủ Bootstrap Anycast toàn cầu (Hỗ trợ Dual-Stack IPv4 + IPv6 chuẩn Doanh nghiệp)
    private let bootstrapServers: [String] = [
        "45.90.28.0",
        "45.90.30.0",
        "2a07:a8c0::",
        "2a07:a8c1::"
    ]
    
    // MARK: - Khởi tạo & Vòng đời
    
    private init() {
        loadStatus()
        fetchServerConfig()
        setupLifecycleObservers()
        startNetworkMonitoring()
    }
    
    deinit {
        pathMonitor.cancel()
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Lắng nghe sự kiện quay lại app từ màn hình Cài đặt iOS để tự động cập nhật trạng thái 0ms
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
    
    /// Theo dõi thay đổi trạng thái mạng (chuyển đổi Wi-Fi <-> 4G/5G) để tự bảo trì kết nối DNS
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
                    self?.serverConfigID = cleanID
                    UserDefaults.standard.set(cleanID, forKey: "nextdns_admin_config_id")
                }
            }
        }.resume()
    }
    
    // MARK: - Quản lý Cấu hình DNS
    
    /// Tải trạng thái DNS từ NetworkExtension của iOS
    func loadStatus(andVerify: Bool = true) {
        manager.loadFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    print("[NextDNS] Lỗi nạp cấu hình: \(error.localizedDescription)")
                    return
                }
                
                let active = self.manager.isEnabled
                self.isEnabled = active
                
                if active {
                    if andVerify {
                        self.verifyActiveResolution()
                    }
                } else {
                    self.isActivelyProtected = false
                    self.needsManualActivation = false
                }
            }
        }
    }
    
    /// Kiểm tra xác thực luồng phân giải thực tế qua máy chủ xác thực NextDNS
    func verifyActiveResolution() {
        let activeID = serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ffe228" : serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://test.nextdns.io") else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 3.5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            var isProtected = false
            
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String, status == "ok" {
                let profile = json["profile"] as? String ?? ""
                if profile.isEmpty || profile == activeID {
                    isProtected = true
                }
            }
            
            DispatchQueue.main.async {
                self.isActivelyProtected = isProtected
                // Nếu iOS báo isEnabled nhưng traffic thực tế chưa qua NextDNS (do profile khác đè)
                if self.isEnabled && !isProtected {
                    self.needsManualActivation = true
                } else if self.isEnabled && isProtected {
                    self.needsManualActivation = false
                }
            }
        }.resume()
    }
    
    /// Tự động xin quyền và đăng ký profile vĩnh viễn vào hệ điều hành (hiện mãi mãi trong Cài đặt máy)
    func registerDNSProfileIfNeeded(completion: ((Bool) -> Void)? = nil) {
        manager.loadFromPreferences { [weak self] error in
            guard let self = self else { return }
            
            if self.manager.dnsSettings != nil {
                DispatchQueue.main.async {
                    self.isEnabled = self.manager.isEnabled
                    completion?(true)
                }
                return
            }
            
            // Chưa có profile -> Khởi tạo cấu hình ban đầu
            let activeID = self.serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "ffe228"
                : self.serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let dohSettings = NEDNSOverHTTPSSettings(servers: self.bootstrapServers)
            dohSettings.serverURL = URL(string: "https://dns.nextdns.io/\(activeID)")
            
            self.manager.localizedDescription = "NovaX DNS"
            self.manager.dnsSettings = dohSettings
            
            // Đặt quy tắc Disconnect để người dùng bật khi cần, profile luôn hiện diện trong Cài đặt
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
                    
                    if !isUnchanged {
                        print("[NextDNS] Không thể đăng ký cấu hình ban đầu: \(saveError.localizedDescription)")
                        DispatchQueue.main.async { completion?(false) }
                        return
                    }
                }
                
                self.manager.loadFromPreferences { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.isEnabled = self?.manager.isEnabled ?? false
                        print("[NextDNS] Đã đăng ký cấu hình NovaX DNS vĩnh viễn vào hệ điều hành.")
                        completion?(true)
                    }
                }
            }
        }
    }
    
    // MARK: - Bật / Tắt DNS
    
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
        needsManualActivation = false
        
        manager.loadFromPreferences { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Lỗi hệ thống: \(error.localizedDescription)"
                    self.isActivating = false
                }
                return
            }
            
            // Cấu hình DoH Dual-Stack
            let dohSettings = NEDNSOverHTTPSSettings(servers: self.bootstrapServers)
            if useUltraLowLatency {
                dohSettings.serverURL = URL(string: "https://dns.nextdns.io/\(activeID)/NovaX-Boost")
            } else {
                dohSettings.serverURL = URL(string: "https://dns.nextdns.io/\(activeID)")
            }
            
            self.manager.localizedDescription = "NovaX DNS"
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
                    
                    // Xử lý trường hợp Stale Configuration (code 3) -> tự động retry 1 lần
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
                                self.errorMessage = "Bạn đã bấm 'Không cho phép'. Hãy bấm lại nút 'BẬT NEXTDNS' và chọn 'Cho phép' để kích hoạt."
                            } else {
                                self.errorMessage = "Không thể lưu cấu hình DNS: \(saveError.localizedDescription)"
                            }
                            self.isEnabled = false
                        }
                        return
                    }
                    print("[NextDNS] Cấu hình không thay đổi (Code 2) - Đồng bộ thành công.")
                }
                
                self.manager.loadFromPreferences { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.isActivating = false
                        self.errorMessage = nil
                        self.isEnabled = true
                        
                        if !self.manager.isEnabled {
                            self.needsManualActivation = true
                        } else {
                            self.needsManualActivation = false
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
        needsManualActivation = false
        
        manager.loadFromPreferences { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Lỗi hệ thống: \(error.localizedDescription)"
                    self.isActivating = false
                }
                return
            }
            
            // Chuyển sang ngắt kết nối (Disconnect) thay vì xóa khỏi hệ thống
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
                            self.errorMessage = "Lỗi tắt DNS: \(saveError.localizedDescription)"
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
                    self.manager.loadFromPreferences { _ in }
                    completion?(true)
                }
            }
        }
    }
    
    // MARK: - Điều hướng Cài đặt Hệ thống (iOS 16 - iOS 27+)
    
    /// Chuyển người dùng thẳng đến màn hình cài đặt DNS / VPN của thiết bị trên iOS 16 - 27+
    func openSystemDNSSettings() {
        let candidateURLStrings = [
            "App-Prefs:root=General&path=ManagedConfigurationList",
            "App-Prefs:root=General&path=VPN",
            "prefs:root=General&path=ManagedConfigurationList",
            "prefs:root=General&path=VPN",
            "App-Prefs:root=General",
            "App-Prefs:"
        ]
        
        func tryOpen(index: Int) {
            guard index < candidateURLStrings.count else {
                if let fallback = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(fallback, options: [:], completionHandler: nil)
                }
                return
            }
            
            guard let url = URL(string: candidateURLStrings[index]) else {
                tryOpen(index: index + 1)
                return
            }
            
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    DispatchQueue.main.async {
                        tryOpen(index: index + 1)
                    }
                }
            }
        }
        
        tryOpen(index: 0)
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
