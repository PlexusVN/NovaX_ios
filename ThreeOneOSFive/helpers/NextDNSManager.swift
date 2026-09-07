import Foundation
import NetworkExtension

class NextDNSManager: ObservableObject {
    static let shared = NextDNSManager()
    
    @Published var isEnabled: Bool = false
    @Published var isActivating: Bool = false
    @Published var errorMessage: String?
    
    private let manager = NEDNSSettingsManager.shared()
    
    private init() {
        loadStatus()
    }
    
    func loadStatus() {
        manager.loadFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Lỗi tải cấu hình DNS: \(error.localizedDescription)")
                    return
                }
                self?.isEnabled = self?.manager.isEnabled ?? false
            }
        }
    }
    
    func enableDNS(configID: String, useUltraLowLatency: Bool) {
        guard !configID.isEmpty else {
            self.errorMessage = "Vui lòng nhập Configuration ID hợp lệ"
            return
        }
        
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
            
            // Cấu hình DoH (DNS-over-HTTPS)
            let dohSettings = NEDNSOverHTTPSSettings(servers: ["45.90.28.0", "45.90.30.0"]) // Anycast IPs làm fallback
            
            if useUltraLowLatency {
                // Ultra-Low Latency sử dụng endpoint trực tiếp
                dohSettings.serverURL = URL(string: "https://dns.nextdns.io/\(configID)")
            } else {
                // Sử dụng Anycast mặc định với ID
                dohSettings.serverURL = URL(string: "https://dns.nextdns.io/\(configID)")
                // Ghi chú: NextDNS thường sẽ tự route sang anycast hoặc ultralow qua BGP,
                // Nhưng trong cấu hình Apple NEDNSSettingsManager, serverURL là endpoint DoH chính.
            }
            
            self.manager.dnsSettings = dohSettings
            self.manager.isEnabled = true
            
            self.manager.saveToPreferences { saveError in
                DispatchQueue.main.async {
                    self.isActivating = false
                    if let saveError = saveError {
                        self.errorMessage = "Không thể lưu hồ sơ DNS (Bạn đã từ chối quyền?): \(saveError.localizedDescription)"
                        self.isEnabled = false
                    } else {
                        self.isEnabled = true
                    }
                }
            }
        }
    }
    
    func disableDNS() {
        isActivating = true
        errorMessage = nil
        
        manager.loadFromPreferences { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Lỗi: \(error.localizedDescription)"
                    self.isActivating = false
                }
                return
            }
            
            self.manager.isEnabled = false
            self.manager.saveToPreferences { saveError in
                DispatchQueue.main.async {
                    self.isActivating = false
                    if let saveError = saveError {
                        self.errorMessage = "Lỗi tắt DNS: \(saveError.localizedDescription)"
                    } else {
                        self.isEnabled = false
                    }
                }
            }
        }
    }
}
