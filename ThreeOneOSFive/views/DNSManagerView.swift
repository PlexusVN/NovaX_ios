import SwiftUI

struct DNSManagerView: View {
    @StateObject private var dnsManager = NextDNSManager.shared
    @Environment(\.scenePhase) private var scenePhase
    
    @AppStorage("nextdns_ultra_low_latency") private var useUltraLowLatency: Bool = true
    @State private var showUninstallConfirm: Bool = false
    @State private var showActivationGuideAlert: Bool = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.pageBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Thẻ trạng thái & NÚT BẬT/TẮT TRUNG TÂM
                        masterStatusCard
                        
                        // Hướng dẫn mở Cài đặt nếu iOS chưa chuyển tick sang NovaX DNS
                        if dnsManager.needsManualActivation {
                            manualActivationCard
                        }
                        
                        // Banner báo lỗi (nếu có)
                        if let error = dnsManager.errorMessage {
                            errorBanner(message: error)
                        }
                        
                        // 2. Khu vực Ultra-Low Latency Network
                        ultraLowLatencySection
                        
                        // Tùy chọn gỡ hồ sơ DNS hoàn toàn khỏi hệ điều hành
                        Button(action: {
                            showUninstallConfirm = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                Text("Gỡ bỏ cấu hình NovaX DNS khỏi thiết bị")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.35))
                            .padding(.top, 8)
                        }
                        .alert("Xác nhận gỡ cấu hình", isPresented: $showUninstallConfirm) {
                            Button("Hủy", role: .cancel) { }
                            Button("Gỡ bỏ", role: .destructive) {
                                dnsManager.uninstallDNSProfile()
                            }
                        } message: {
                            Text("Thao tác này sẽ xóa hồ sơ NovaX DNS khỏi Cài đặt của iPhone. Bạn sẽ cần cấp quyền lại nếu muốn kích hoạt sau này.")
                        }
                        .alert("Kích hoạt NovaX DNS", isPresented: $showActivationGuideAlert) {
                            Button("Mở Cài Đặt Ngay") {
                                dnsManager.openSystemDNSSettings()
                            }
                            Button("Đóng", role: .cancel) { }
                        } message: {
                            Text("Do bảo mật của iOS, hệ thống sẽ mở màn hình Cài đặt NovaX:\n\n1. Nhìn góc trên cùng bên trái: Bấm chữ '< Cài đặt'\n2. Vào 'Cài đặt chung' ➔ 'VPN & Quản lý thiết bị' ➔ 'DNS'\n3. Tích chọn 'NovaX DNS'\n\nSau khi tích chọn xong, mở lại NovaX sẽ tự động chuyển sang ĐÃ KẾT NỐI.")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("NextDNS")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.accent)
            .onAppear {
                dnsManager.loadStatus()
                dnsManager.fetchServerConfig()
                dnsManager.registerDNSProfileIfNeeded()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    dnsManager.loadStatus()
                    dnsManager.fetchServerConfig()
                }
            }
        }
    }
    
    // MARK: - 1. Master Status Card (Trung tâm Bật/TẮT)
    
    private var masterStatusCard: some View {
        VStack(spacing: 20) {
            // Icon khiên phát sáng
            ZStack {
                // Vòng sóng phát sáng khi đang bật
                if dnsManager.isEnabled {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.cyberCyan.opacity(0.35), AppTheme.cyberPurple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 8
                        )
                        .frame(width: 108, height: 108)
                        .scaleEffect(1.05)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [AppTheme.cyberCyan.opacity(0.25), AppTheme.cyberPurple.opacity(0.1), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 45
                            )
                        )
                        .frame(width: 90, height: 90)
                } else {
                    Circle()
                        .fill(AppTheme.cyberOLED.opacity(0.6))
                        .frame(width: 90, height: 90)
                }
                
                Image(systemName: dnsManager.isEnabled ? "shield.fill" : "shield.slash")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(dnsManager.isEnabled ? AppTheme.cyberGradient : LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: dnsManager.isEnabled ? AppTheme.cyberCyan.opacity(0.7) : .clear, radius: 18)
            }
            .padding(.top, 10)
            
            // Text trạng thái
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(dnsManager.isEnabled ? AppTheme.cyberCyan : (dnsManager.needsManualActivation ? Color(hex: 0xFF9500) : Color.white.opacity(0.25)))
                        .frame(width: 8, height: 8)
                        .shadow(color: dnsManager.isEnabled ? AppTheme.cyberCyan : (dnsManager.needsManualActivation ? Color(hex: 0xFF9500) : .clear), radius: 5)
                    Text(dnsManager.isEnabled ? "ĐÃ KẾT NỐI" : (dnsManager.needsManualActivation ? "CHƯA TÍCH CHỌN" : "CHƯA KẾT NỐI"))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(dnsManager.isEnabled ? AppTheme.cyberCyan : (dnsManager.needsManualActivation ? Color(hex: 0xFF9500) : .white.opacity(0.5)))
                }
                
                Text(dnsManager.isEnabled ? "Thiết bị đang được bảo vệ qua NextDNS" : (dnsManager.needsManualActivation ? "Hồ sơ đã nạp vào máy. Cần tích chọn NovaX DNS trong Cài đặt iPhone" : "DNS của thiết bị đang ở chế độ mặc định"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                
                if dnsManager.isEnabled && dnsManager.isActivelyProtected {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.cyberCyan)
                        Text("ĐÃ XÁC MINH BẢO VỆ THỰC TẾ")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(AppTheme.cyberCyan)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.cyberCyan.opacity(0.12))
                    .cornerRadius(6)
                }
            }
            
            // Thanh gạt công tắc chuẩn NextDNS (Master Toggle Switch)
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(dnsManager.isEnabled ? AppTheme.cyberCyan.opacity(0.15) : Color.white.opacity(0.06))
                        .frame(width: 36, height: 36)
                    Image(systemName: dnsManager.isEnabled ? "checkmark.shield.fill" : "shield.slash.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(dnsManager.isEnabled ? AppTheme.cyberCyan : .white.opacity(0.4))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bảo vệ NextDNS")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(dnsManager.isEnabled ? "Đang bật (DoH • ID: \(dnsManager.serverConfigID))" : (dnsManager.needsManualActivation ? "Cần kích hoạt trong Cài đặt máy" : "Đang tắt (Tạm dừng bảo vệ)"))
                        .font(.system(size: 12))
                        .foregroundColor(dnsManager.isEnabled ? AppTheme.cyberCyan : (dnsManager.needsManualActivation ? Color(hex: 0xFF9500) : .white.opacity(0.45)))
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { dnsManager.isEnabled },
                    set: { _ in
                        toggleDNSAction()
                    }
                ))
                .labelsHidden()
                .tint(AppTheme.cyberCyan)
                .disabled(dnsManager.isActivating)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            
            // NÚT BẬT / TẮT DNS CHÍNH (MASTER ACTION BUTTON)
            Button(action: toggleDNSAction) {
                HStack(spacing: 10) {
                    if dnsManager.isActivating {
                        ProgressView()
                            .tint(.white)
                        Text("Đang xử lý...")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    } else if dnsManager.isEnabled {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 17, weight: .bold))
                        Text("TẮT DNS")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    } else if dnsManager.needsManualActivation {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 17, weight: .bold))
                        Text("MỞ CÀI ĐẶT ĐỂ KÍCH HOẠT")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    } else {
                        Image(systemName: "power")
                            .font(.system(size: 17, weight: .bold))
                        Text("BẬT NEXTDNS")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    Group {
                        if dnsManager.isEnabled {
                            // Nút đỏ khi đang bật -> bấm để tắt
                            LinearGradient(
                                colors: [Color(hex: 0xFF2A6D), Color(hex: 0xD00036)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        } else {
                            // Cyber Gradient rực rỡ khi đang tắt -> bấm để bật
                            AppTheme.cyberGradient
                        }
                    }
                )
                .foregroundColor(.white)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.4), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: (dnsManager.isEnabled ? Color(hex: 0xFF2A6D) : AppTheme.cyberCyan).opacity(0.45), radius: 15, y: 5)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(dnsManager.isActivating)
        }
        .padding(20)
        .background(cardBackground)
    }
    
    // MARK: - Manual Activation Guide Card
    
    private var manualActivationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: 0xFF9500))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cần tích chọn NovaX DNS trên iPhone")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Hồ sơ đã được nạp an toàn, chỉ cần 1 thao tác")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Do bảo mật của Apple, bạn cần làm theo 4 bước sau:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                
                VStack(alignment: .leading, spacing: 8) {
                    stepItem(num: "1", text: "Bấm nút **Mở Cài Đặt iPhone** bên dưới.")
                    stepItem(num: "2", text: "Nếu màn hình mở vào trang NovaX: bấm vào **`< Cài đặt`** ở góc trên cùng bên trái để ra danh sách Cài đặt chính.")
                    stepItem(num: "3", text: "Vào **Cài đặt chung** ➔ **VPN & Quản lý thiết bị** ➔ **DNS**.")
                    stepItem(num: "4", text: "Tích chọn **NovaX DNS**.")
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
                
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(AppTheme.cyberCyan)
                    Text("Khi tích xong, quay lại NovaX sẽ tự động chuyển sang **ĐÃ KẾT NỐI**.")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.cyberCyan)
                }
            }
            
            HStack(spacing: 10) {
                Button(action: {
                    Haptics.medium()
                    showActivationGuideAlert = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Mở Cài Đặt iPhone")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(AppTheme.cyberGradient)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .shadow(color: AppTheme.cyberCyan.opacity(0.3), radius: 8, y: 3)
                }
                .buttonStyle(PressableButtonStyle())
                
                Button(action: {
                    Haptics.light()
                    dnsManager.loadStatus()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                        Text("Kiểm tra lại")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(16)
        .background(Color(hex: 0xFF9500).opacity(0.12))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: 0xFF9500).opacity(0.4), lineWidth: 1)
        )
    }
    
    private func stepItem(num: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num + ".")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.cyberCyan)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - 2. Ultra-Low Latency Section
    
    private var ultraLowLatencySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TÙY CHỌN MẠNG")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.cyberCyan)
                .padding(.leading, 6)
            
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.cyberCyan.opacity(useUltraLowLatency ? 0.25 : 0.08), AppTheme.cyberPurple.opacity(useUltraLowLatency ? 0.25 : 0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(useUltraLowLatency ? AppTheme.cyberCyan : .white.opacity(0.4))
                            .shadow(color: useUltraLowLatency ? AppTheme.cyberCyan.opacity(0.6) : .clear, radius: 6)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Ultra-Low Latency Network")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            if useUltraLowLatency {
                                Text("FAST")
                                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                    .foregroundColor(AppTheme.cyberCyan)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [AppTheme.cyberCyan.opacity(0.22), AppTheme.cyberPurple.opacity(0.22)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .overlay(
                                                Capsule().stroke(AppTheme.cyberCyan.opacity(0.4), lineWidth: 1)
                                            )
                                    )
                            }
                        }
                        
                        Text("Tự động định tuyến máy chủ gần nhất để tối ưu hóa tốc độ và giảm ping khi chơi game.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $useUltraLowLatency)
                        .labelsHidden()
                        .tint(AppTheme.cyberCyan)
                        .onChange(of: useUltraLowLatency) { newValue in
                            if dnsManager.isEnabled {
                                dnsManager.enableDNS(useUltraLowLatency: newValue)
                            }
                        }
                }
                .padding(16)
            }
            .background(cardBackground)
        }
    }
    
    // MARK: - Actions & Helpers
    
    private func toggleDNSAction() {
        Haptics.medium()
        if dnsManager.isEnabled {
            dnsManager.disableDNS()
        } else if dnsManager.needsManualActivation {
            showActivationGuideAlert = true
        } else {
            dnsManager.enableDNS(useUltraLowLatency: useUltraLowLatency)
        }
    }
    
    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.red.opacity(0.95))
            Spacer()
        }
        .padding(14)
        .background(Color.red.opacity(0.12))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.25), lineWidth: 1)
        )
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(AppTheme.cyberSurface.opacity(0.65))
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.cyberBorderGradient, lineWidth: 1.2)
            )
            .shadow(color: AppTheme.cyberCyan.opacity(0.1), radius: 20, y: 8)
    }
}
