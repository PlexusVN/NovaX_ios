import SwiftUI

struct DNSManagerView: View {
    @StateObject private var dnsManager = NextDNSManager.shared
    @Environment(\.scenePhase) private var scenePhase
    
    @AppStorage("nextdns_ultra_low_latency") private var useUltraLowLatency: Bool = true
    @State private var showUninstallConfirm: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var exportedFileURL: URL? = nil
    
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
                        
                        // 3. Phương thức DoH Trực tiếp Chuẩn NextDNS (MobileConfig Enterprise)
                        directMobileConfigSection
                        
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("NextDNS")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.accent)
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .onAppear {
                // ĐỒNG BỘ CHUẨN: Chỉ nạp trạng thái, KHÔNG đăng ký lại để tránh ghi đè toggle của người dùng
                dnsManager.loadStatus()
                dnsManager.fetchServerConfig()
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
                
                Image(systemName: dnsManager.isEnabled ? (dnsManager.isActivelyProtected ? "shield.fill" : "shield.lefthalf.filled") : "shield.slash")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(
                        dnsManager.isEnabled
                            ? (dnsManager.isActivelyProtected ? AppTheme.cyberGradient : LinearGradient(colors: [Color(hex: 0xFF9500), Color(hex: 0xFF5E00)], startPoint: .top, endPoint: .bottom))
                            : LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(
                        color: dnsManager.isEnabled
                            ? (dnsManager.isActivelyProtected ? AppTheme.cyberCyan.opacity(0.7) : Color(hex: 0xFF9500).opacity(0.5))
                            : .clear,
                        radius: 18
                    )
            }
            .padding(.top, 10)
            
            // Text trạng thái
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            !dnsManager.isEnabled
                                ? (dnsManager.needsManualActivation ? Color(hex: 0xFF9500) : Color.white.opacity(0.25))
                                : (dnsManager.isActivelyProtected ? AppTheme.cyberCyan : (dnsManager.isVerifying ? Color(hex: 0x00D4FF) : Color(hex: 0xFF9500)))
                        )
                        .frame(width: 8, height: 8)
                        .shadow(
                            color: !dnsManager.isEnabled
                                ? (dnsManager.needsManualActivation ? Color(hex: 0xFF9500) : .clear)
                                : (dnsManager.isActivelyProtected ? AppTheme.cyberCyan : Color(hex: 0xFF9500)),
                            radius: 5
                        )
                    
                    Text(
                        !dnsManager.isEnabled
                            ? (dnsManager.needsManualActivation ? "CHƯA TÍCH CHỌN" : "CHƯA KẾT NỐI")
                            : (dnsManager.isActivelyProtected
                                ? "ĐÃ XÁC THỰC BẢO VỆ"
                                : (dnsManager.isVerifying ? "ĐANG KIỂM TRA BẢO VỆ..." : "ĐÃ BẬT • CHƯA XÁC THỰC"))
                    )
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(
                        !dnsManager.isEnabled
                            ? (dnsManager.needsManualActivation ? Color(hex: 0xFF9500) : .white.opacity(0.5))
                            : (dnsManager.isActivelyProtected ? AppTheme.cyberCyan : (dnsManager.isVerifying ? Color(hex: 0x00D4FF) : Color(hex: 0xFF9500)))
                    )
                }
                
                Text(
                    !dnsManager.isEnabled
                        ? (dnsManager.needsManualActivation ? "Hồ sơ đã nạp vào máy. Cần tích chọn NovaX DNS trong Cài đặt iPhone" : "DNS của thiết bị đang ở chế độ mặc định")
                        : (dnsManager.isActivelyProtected
                            ? "Thiết bị đang được mã hóa và bảo vệ an toàn 100% qua NextDNS"
                            : (dnsManager.isVerifying ? "Đang gửi gói tin kiểm tra phân giải thực tế đến máy chủ NextDNS..." : "Cấu hình đã bật nhưng lưu lượng mạng chưa phân giải qua DoH"))
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
            }
            
            // Bảng Báo Xác Thực Kiểm Tra Máy Đã Thực Sự Kết Nối DNS
            if dnsManager.isEnabled {
                verificationStatusBadge
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
                        Text("MỞ CÀI ĐẶT DNS")
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
                Text("Để kích hoạt bảo vệ, bạn cần chọn NovaX DNS trong Cài đặt iPhone:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                
                VStack(alignment: .leading, spacing: 8) {
                    stepItem(num: "1", text: "Bấm nút **Mở Cài Đặt DNS** bên dưới (Cài đặt ➔ Cài đặt chung ➔ VPN & Quản lý thiết bị ➔ DNS).")
                    stepItem(num: "2", text: "Tích chọn **NovaX DNS**.")
                    stepItem(num: "3", text: "Quay lại ứng dụng NovaX: Trạng thái sẽ tự động chuyển sang **ĐÃ KẾT NỐI**.")
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
            }
            
            HStack(spacing: 10) {
                Button(action: {
                    Haptics.medium()
                    dnsManager.openSystemDNSSettings()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Mở Cài Đặt DNS")
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
    
    // MARK: - 3. Direct MobileConfig Profile (NextDNS Native Method)
    
    private var directMobileConfigSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GIẢI PHÁP DOANH NGHIỆP DỰ PHÒNG")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.cyberCyan)
                Spacer()
                Text("APPLE OFFICIAL")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(AppTheme.cyberPurple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.cyberPurple.opacity(0.18))
                    .cornerRadius(4)
            }
            .padding(.leading, 6)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.cyberCyan)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Cài đặt Hồ sơ DNS Trực tiếp (.mobileconfig)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Dành cho máy không hiện DNS hoặc bị lỗi cấp quyền. Cài đặt 1 lần hoạt động vĩnh viễn trên iOS 16, 17, 18, 26, 27+.")
                            .font(.system(size: 11.5))
                            .foregroundColor(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Button(action: {
                    Haptics.medium()
                    if let url = dnsManager.exportLocalMobileConfigFile() {
                        exportedFileURL = url
                        showShareSheet = true
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("Xuất File Hồ Sơ (.mobileconfig)")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: 0x0A84FF), Color(hex: 0x0055D4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .shadow(color: Color(hex: 0x0A84FF).opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(PressableButtonStyle())
                
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: 0xFFD60A))
                        .padding(.top, 1)
                    Text("Hướng dẫn: Lưu vào Tệp (Files) ➔ Chạm mở file ➔ Vào Cài đặt iPhone ➔ Bấm 'Hồ sơ đã tải về' để cài đặt vĩnh viễn.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
            .padding(16)
            .background(cardBackground)
        }
    }
    
    // MARK: - Bảng Báo Xác Thực Bảo Vệ Thiết Bị
    
    private var verificationStatusBadge: some View {
        Group {
            if dnsManager.isActivelyProtected {
                // TRẠNG THÁI: ĐÃ XÁC THỰC THIẾT BỊ ĐANG ĐƯỢC BẢO VỆ
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.cyberCyan.opacity(0.18))
                            .frame(width: 38, height: 38)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppTheme.cyberCyan)
                            .shadow(color: AppTheme.cyberCyan.opacity(0.6), radius: 6)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("ĐÃ XÁC THỰC BẢO VỆ")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("VERIFIED")
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundColor(AppTheme.cyberCyan)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.cyberCyan.opacity(0.16))
                                .cornerRadius(4)
                        }
                        
                        Text("Phân giải DoH qua NextDNS (\(dnsManager.serverConfigID)) • \(dnsManager.pingLatencyMs ?? 0) ms")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        Haptics.light()
                        dnsManager.verifyActiveResolution(showLoading: true)
                    }) {
                        HStack(spacing: 4) {
                            if dnsManager.isVerifying {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(AppTheme.cyberCyan)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                        .foregroundColor(AppTheme.cyberCyan)
                        .padding(8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(dnsManager.isVerifying)
                }
                .padding(12)
                .background(AppTheme.cyberCyan.opacity(0.08))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.cyberCyan.opacity(0.3), lineWidth: 1)
                )
            } else if dnsManager.isVerifying {
                // TRẠNG THÁI: ĐANG KIỂM TRA PHÂN GIẢI THỰC TẾ
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: 0x00D4FF).opacity(0.15))
                            .frame(width: 38, height: 38)
                        ProgressView()
                            .tint(AppTheme.cyberCyan)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Đang kiểm tra kết nối DNS thực tế...")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Gửi gói tin ping kiểm tra máy chủ NextDNS...")
                            .font(.system(size: 11.5))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.white.opacity(0.04))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.cyberCyan.opacity(0.2), lineWidth: 1)
                )
            } else {
                // TRẠNG THÁI: ĐÃ BẬT NHƯNG CHƯA ĐƯỢC BẢO VỆ THỰC SỰ
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: 0xFF9500).opacity(0.18))
                            .frame(width: 38, height: 38)
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Color(hex: 0xFF9500))
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("CHƯA BẢO VỆ THỰC TẾ")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("CHƯA KẾT NỐI")
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundColor(Color(hex: 0xFF9500))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: 0xFF9500).opacity(0.16))
                                .cornerRadius(4)
                        }
                        
                        Text("Hồ sơ đã bật nhưng lưu lượng mạng chưa phân giải qua NextDNS.")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        Haptics.medium()
                        dnsManager.verifyActiveResolution(showLoading: true)
                    }) {
                        Text("Kiểm tra lại")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(hex: 0xFF9500))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                .padding(12)
                .background(Color(hex: 0xFF9500).opacity(0.08))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: 0xFF9500).opacity(0.35), lineWidth: 1)
                )
            }
        }
    }
    
    // MARK: - Actions & Helpers
    
    private func toggleDNSAction() {
        Haptics.medium()
        if dnsManager.isEnabled {
            dnsManager.disableDNS()
        } else if dnsManager.needsManualActivation {
            dnsManager.openSystemDNSSettings()
        } else {
            dnsManager.enableDNS(useUltraLowLatency: useUltraLowLatency)
        }
    }
    
    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.red.opacity(0.95))
            }
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

// MARK: - UIActivityViewController Wrapper for SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
