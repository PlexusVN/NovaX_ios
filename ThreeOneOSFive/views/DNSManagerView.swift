import SwiftUI

struct DNSManagerView: View {
    @StateObject private var dnsManager = NextDNSManager.shared
    
    // Lưu trữ config ID locally
    @AppStorage("nextdns_config_id") private var configID: String = ""
    @AppStorage("nextdns_ultra_low_latency") private var useUltraLowLatency: Bool = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                MeshBackground()
                
                ScrollView {
                    VStack(spacing: 24) {
                        headerCard
                        
                        if let error = dnsManager.errorMessage {
                            errorBanner(message: error)
                        }
                        
                        configurationSection
                        
                        advancedSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("NextDNS")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.accent)
        }
    }
    
    // MARK: - Header
    
    private var headerCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "shield.righthalf.filled")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(AppTheme.accent)
            }
            .shadow(color: AppTheme.accent.opacity(0.25), radius: 20)
            
            VStack(spacing: 4) {
                Text("Trình chặn DNS")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Chặn quảng cáo, trackers và mã độc")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(cardBackground)
    }
    
    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.red.opacity(0.9))
            Spacer()
        }
        .padding(16)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Configuration Section
    
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CẤU HÌNH")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.accent)
                .padding(.leading, 8)
            
            VStack(spacing: 0) {
                // Toggle Kích hoạt
                HStack {
                    Text("Sử dụng Custom Configuration")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { dnsManager.isEnabled },
                        set: { newValue in
                            if newValue {
                                dnsManager.enableDNS(configID: configID, useUltraLowLatency: useUltraLowLatency)
                            } else {
                                dnsManager.disableDNS()
                            }
                        }
                    ))
                    .labelsHidden()
                    .disabled(dnsManager.isActivating)
                    .tint(AppTheme.accent)
                }
                .padding(16)
                
                Divider().background(Color.white.opacity(0.06))
                
                // Input ID
                HStack {
                    Text("Configuration ID")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    TextField("VD: ffe228", text: $configID)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(AppTheme.accent)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: configID) { _ in
                            // Tự động tắt nếu đổi ID để người dùng bật lại
                            if dnsManager.isEnabled {
                                dnsManager.disableDNS()
                            }
                        }
                }
                .padding(16)
            }
            .background(cardBackground)
            
            Text("Thiết lập hệ thống chuyển hướng DNS toàn thiết bị. Khi bật lần đầu, hệ điều hành sẽ yêu cầu quyền thêm hồ sơ VPN/DNS.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 8)
        }
    }
    
    // MARK: - Advanced Section
    
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NÂNG CAO")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.accent)
                .padding(.leading, 8)
            
            VStack(spacing: 0) {
                HStack {
                    Text("Sử dụng mạng Ultra-Low Latency")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("", isOn: $useUltraLowLatency)
                        .labelsHidden()
                        .tint(AppTheme.accent)
                        .onChange(of: useUltraLowLatency) { _ in
                            if dnsManager.isEnabled {
                                // Cập nhật lại DNS nếu đang bật
                                dnsManager.enableDNS(configID: configID, useUltraLowLatency: useUltraLowLatency)
                            }
                        }
                }
                .padding(16)
            }
            .background(cardBackground)
            
            Text("Tắt cài đặt này nếu nhà mạng của bạn chặn hoặc làm chậm mạng NextDNS, có thể làm độ trễ tăng lên một chút do dùng mạng Anycast.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 8)
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(uiColor: .systemBackground).opacity(0.1))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.2), Color.white.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }
}
