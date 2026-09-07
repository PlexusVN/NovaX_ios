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
    
    /// Máy chủ Bootstrap Anycast toàn cầu tối ưu cho Apple DoH (IPv4 & IPv6)
    private let bootstrapServers: [String] = [
        "45.90.28.0",
        "2a07:a8c0::",
        "45.90.30.0",
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
                    self?.serverConfigID = cleanID
                    UserDefaults.standard.set(cleanID, forKey: "nextdns_admin_config_id")
                }
            }
        }.resume()
    }
    
    // MARK: - Quản lý Cấu hình DNS
    
    /// Tải trạng thái DNS từ NetworkExtension của iOS (đồng bộ chuẩn hai chiều)
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
                let userWantsEnabled = UserDefaults.standard.object(forKey: "nextdns_user_wants_enabled") as? Bool ?? true
                
                if !isInstalledInSettings {
                    self.isEnabled = false
                    self.isActivelyProtected = false
                    // Nếu profile đã được tạo trong máy nhưng chưa được tích chọn trong Settings
                    if self.manager.dnsSettings != nil {
                        self.needsManualActivation = true
                    } else {
                        self.needsManualActivation = false
                    }
                } else {
                    self.needsManualActivation = false
                    // Nếu người dùng đã tích chọn trong Cài đặt iPhone
                    // Chỉ bật nếu quy tắc kết nối là Connect VÀ người dùng muốn bật
                    if isRuleConnect && userWantsEnabled {
                        self.isEnabled = true
                        if andVerify {
                            self.verifyActiveResolution()
                        }
                    } else {
                        // Người dùng đã chủ động bấm TẮT trong app -> Giữ trạng thái TẮT rõ ràng!
                        self.isEnabled = false
                        self.isActivelyProtected = false
                    }
                }
            }
        }
    }
    
    /// Kiểm tra xác thực luồng phân giải thực tế qua máy chủ xác thực NextDNS
    func verifyActiveResolution() {
        let activeID = serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ffe228" : serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://test.nextdns.io") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("curl/8.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 4.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let session = URLSession(configuration: .ephemeral, delegate: NextDNSRedirectDelegate(), delegateQueue: nil)
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            var isProtected = false
            
            if let data = data, let text = String(data: data, encoding: .utf8) {
                if text.contains("\"status\": \"ok\"") || text.contains("\"status\":\"ok\"") || text.contains(activeID) {
                    isProtected = true
                }
            }
            
            DispatchQueue.main.async {
                self.isActivelyProtected = isProtected
            }
        }.resume()
    }
    
    /// Tự động xin quyền và đăng ký profile vĩnh viễn vào hệ điều hành (hiện mãi mãi trong Cài đặt máy)
    func registerDNSProfileIfNeeded(completion: ((Bool) -> Void)? = nil) {
        manager.loadFromPreferences { [weak self] error in
            guard let self = self else { return }
            
            let currentDoh = self.manager.dnsSettings as? NEDNSOverHTTPSSettings
            let hasMatchDomains = currentDoh?.matchDomains?.contains("") == true
            
            if self.manager.dnsSettings != nil && hasMatchDomains {
                DispatchQueue.main.async {
                    self.isEnabled = self.manager.isEnabled
                    if !self.manager.isEnabled {
                        self.needsManualActivation = true
                    }
                    completion?(true)
                }
                return
            }
            
            // Chưa có profile hoặc profile cũ chưa có matchDomains -> Khởi tạo/cập nhật cấu hình
            let activeID = self.serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "ffe228"
                : self.serverConfigID.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let dohSettings = NEDNSOverHTTPSSettings(servers: self.bootstrapServers)
            dohSettings.serverURL = URL(string: "https://dns.nextdns.io/\(activeID)")
            dohSettings.matchDomains = [""] // Bắt buộc để iOS định tuyến toàn bộ lưu lượng qua NextDNS
            
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
                        self.isEnabled = active
                        self.needsManualActivation = !active
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
            dohSettings.matchDomains = [""] // Bắt buộc để iOS định tuyến toàn bộ lưu lượng qua NextDNS
            
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
                                self.errorMessage = "Bạn đã bấm 'Không cho phép'. Hãy bấm lại nút và chọn 'Cho phép' để cấp quyền."
                            } else {
                                self.errorMessage = "Không thể lưu cấu hình DNS: \(saveError.localizedDescription)"
                            }
                            self.isEnabled = false
                        }
                        return
                    }
                    print("[NextDNS] Cấu hình không thay đổi (Code 2) - Đồng bộ thành công.")
                }
                
                UserDefaults.standard.set(true, forKey: "nextdns_user_wants_enabled")
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
                            self.errorMessage = "Lỗi tắt DNS: \(saveError.localizedDescription)"
                        }
                        return
                    }
                }
                
                UserDefaults.standard.set(false, forKey: "nextdns_user_wants_enabled")
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
        UserDefaults.standard.removeObject(forKey: "nextdns_user_wants_enabled")
        
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
    
    /// Chuyển người dùng đến Cài đặt iPhone để kích hoạt NovaX DNS
    func openSystemDNSSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
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
