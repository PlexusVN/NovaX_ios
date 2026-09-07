import Foundation
import NetworkExtension
import UIKit

class NextDNSManager: ObservableObject {
    static let shared = NextDNSManager()
    
    @Published var isEnabled: Bool = false
    @Published var isActivating: Bool = false
    @Published var errorMessage: String?
    @Published var needsManualActivation: Bool = false
    
    // Cấu hình NextDNS được Admin thiết lập từ máy chủ (mặc định ffe228)
    @Published var serverConfigID: String = UserDefaults.standard.string(forKey: "nextdns_admin_config_id") ?? "ffe228"
    
    private let manager = NEDNSSettingsManager.shared()
    
    private init() {
        loadStatus()
        fetchServerConfig()
    }
    
    /// Đồng bộ cấu hình DNS do Admin cài đặt từ Server
    func fetchServerConfig() {
        guard let url = URL(string: "https://zynox.click/api/client/config") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        
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
                    print("[NextDNS] Đồng bộ thành công cấu hình ID từ máy chủ: \(cleanID)")
                }
            }
        }.resume()
    }
    
    func loadStatus() {
        manager.loadFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Lỗi tải cấu hình DNS: \(error.localizedDescription)")
                    return
                }
                let active = self?.manager.isEnabled ?? false
                self?.isEnabled = active
                if active {
                    self?.needsManualActivation = false
                }
            }
        }
    }
    
    func enableDNS(useUltraLowLatency: Bool) {
        enableDNS(configID: nil, useUltraLowLatency: useUltraLowLatency)
    }
    
    func enableDNS(configID: String? = nil, useUltraLowLatency: Bool) {
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
            
            // Cấu hình DoH (DNS-over-HTTPS)
            let dohSettings = NEDNSOverHTTPSSettings(servers: ["45.90.28.0", "45.90.30.0"]) // Anycast IPs fallback
            if useUltraLowLatency {
                dohSettings.serverURL = URL(string: "https://dns.nextdns.io/\(activeID)/NovaX-Boost")
            } else {
                dohSettings.serverURL = URL(string: "https://dns.nextdns.io/\(activeID)")
            }
            
            // Đặt tên riêng biệt để không ảnh hưởng hoặc ghi đè lên các DNS khác
            self.manager.localizedDescription = "NovaX DNS"
            self.manager.dnsSettings = dohSettings
            
            self.manager.saveToPreferences { [weak self] saveError in
                guard let self = self else { return }
                
                if let saveError = saveError {
                    DispatchQueue.main.async {
                        self.isActivating = false
                        let desc = saveError.localizedDescription.lowercased()
                        if desc.contains("permission") || desc.contains("denied") || desc.contains("cancel") {
                            self.errorMessage = "Bạn đã bấm 'Không cho phép'. Hãy bấm lại nút 'BẬT NEXTDNS' và chọn 'Cho phép' để kích hoạt."
                        } else {
                            self.errorMessage = "Không thể lưu cấu hình DNS: \(saveError.localizedDescription)"
                        }
                        self.isEnabled = false
                    }
                    return
                }
                
                // Sau khi lưu, tải lại preferences để verify xem iOS đã tự động bật hay người dùng cần chọn thủ công
                self.manager.loadFromPreferences { [weak self] loadError in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.isActivating = false
                        self.isEnabled = self.manager.isEnabled
                        
                        // Nếu lưu thành công nhưng isEnabled vẫn false (do thiết bị đang có profile DNS khác ưu tiên)
                        if !self.manager.isEnabled {
                            self.needsManualActivation = true
                        } else {
                            self.needsManualActivation = false
                        }
                    }
                }
            }
        }
    }
    
    func disableDNS() {
        isActivating = true
        errorMessage = nil
        needsManualActivation = false
        
        manager.removeFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isActivating = false
                if let error = error {
                    self.errorMessage = "Lỗi tắt DNS: \(error.localizedDescription)"
                } else {
                    self.isEnabled = false
                    self.manager.loadFromPreferences { _ in }
                }
            }
        }
    }
    
    /// Chuyển người dùng thẳng đến màn hình cài đặt DNS / VPN của thiết bị
    func openSystemDNSSettings() {
        let candidateURLs = [
            "App-Prefs:root=General&path=VPN",
            "App-Prefs:root=General",
            UIApplication.openSettingsURLString
        ]
        
        for urlStr in candidateURLs {
            if let url = URL(string: urlStr), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }
        }
        
        if let fallback = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(fallback, options: [:], completionHandler: nil)
        }
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

