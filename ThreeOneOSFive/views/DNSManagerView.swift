import SwiftUI

struct DNSManagerView: View {
    @StateObject private var dnsManager = NextDNSManager.shared
    
    // Lưu trữ config ID locally
    @AppStorage("nextdns_config_id") private var configID: String = ""
    @AppStorage("nextdns_ultra_low_latency") private var useUltraLowLatency: Bool = true
    
    @State private var showingCopiedAlert = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.pageBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Thẻ trạng thái & NÚT BẬT/TẮT TRUNG TÂM
                        masterStatusCard
                        
                        // Banner báo lỗi (nếu có)
                        if let error = dnsManager.errorMessage {
                            errorBanner(message: error)
                        }
                        
                        // 2. Khu vực cấu hình Configuration ID
                        configurationSection
                        
                        // 3. Khu vực Nâng cao
                        advancedSection
                        
                        // 4. Hướng dẫn Anti-Revoke tích hợp
                        antiRevokeTipCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("NextDNS")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.accent)
        }
    }
    
    // MARK: - 1. Master Status Card (Trung tâm Bật/Tắt)
    
    private var masterStatusCard: some View {
        VStack(spacing: 20) {
            // Icon khiên phát sáng
            ZStack {
                // Vòng sóng phát sáng khi đang bật
                if dnsManager.isEnabled {
                    Circle()
                        .stroke(AppTheme.accent.opacity(0.2), lineWidth: 8)
                        .frame(width: 104, height: 104)
                        .scaleEffect(1.05)
                    Circle()
                        .fill(AppTheme.accent.opacity(0.15))
                        .frame(width: 88, height: 88)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 88, height: 88)
                }
                
                Image(systemName: dnsManager.isEnabled ? "shield.fill" : "shield.slash")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(dnsManager.isEnabled ? AppTheme.accent : .white.opacity(0.35))
                    .shadow(color: dnsManager.isEnabled ? AppTheme.accent.opacity(0.6) : .clear, radius: 16)
            }
            .padding(.top, 10)
            
            // Text trạng thái
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(dnsManager.isEnabled ? Color(hex: 0x34C759) : Color.white.opacity(0.25))
                        .frame(width: 8, height: 8)
                    Text(dnsManager.isEnabled ? "ĐÃ KẾT NỐI" : "CHƯA KẾT NỐI")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(dnsManager.isEnabled ? Color(hex: 0x34C759) : .white.opacity(0.5))
                }
                
                Text(dnsManager.isEnabled ? "Thiết bị đang được bảo vệ qua NextDNS" : "DNS của thiết bị đang ở chế độ mặc định")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }
            
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
                                colors: [Color.red.opacity(0.85), Color.red.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        } else {
                            // Nút Accent khi đang tắt -> bấm để bật
                            LinearGradient(
                                colors: [AppTheme.accent, AppTheme.accentLight],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                )
                .foregroundColor(.white)
                .cornerRadius(14)
                .shadow(color: (dnsManager.isEnabled ? Color.red : AppTheme.accent).opacity(0.35), radius: 12, y: 4)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(dnsManager.isActivating)
        }
        .padding(20)
        .background(cardBackground)
    }
    
    // MARK: - 2. Configuration Section
    
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CẤU HÌNH TÀI KHOẢN")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.accent)
                .padding(.leading, 6)
            
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Configuration ID")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    
                    HStack(spacing: 12) {
                        Image(systemName: "number")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppTheme.accent)
                        
                        TextField("VD: ffe228", text: $configID)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: configID) { _ in
                                if dnsManager.isEnabled {
                                    dnsManager.disableDNS()
                                }
                            }
                        
                        // Nút Dán nhanh (Paste)
                        Button(action: pasteFromClipboard) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 12))
                                Text("Dán")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(AppTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.accent.opacity(0.12))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .padding(16)
            }
            .background(cardBackground)
            
            Text("Lấy mã ID cấu hình của bạn tại trang my.nextdns.io. Khi bật, DNS sẽ tự động chuyển hướng toàn bộ thiết bị qua ID này.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 6)
        }
    }
    
    // MARK: - 3. Advanced Section
    
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TÙY CHỌN MẠNG")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.accent)
                .padding(.leading, 6)
            
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ultra-Low Latency Network")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                        Text("Tối ưu hóa máy chủ gần nhất để giảm ping khi chơi game")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                    Toggle("", isOn: $useUltraLowLatency)
                        .labelsHidden()
                        .tint(AppTheme.accent)
                        .onChange(of: useUltraLowLatency) { _ in
                            if dnsManager.isEnabled {
                                dnsManager.enableDNS(configID: configID, useUltraLowLatency: useUltraLowLatency)
                            }
                        }
                }
                .padding(16)
            }
            .background(cardBackground)
        }
    }
    
    // MARK: - 4. Anti-Revoke Tip Card
    
    private var antiRevokeTipCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 20))
                .foregroundColor(AppTheme.accent)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Mẹo Chặn Thu Hồi (Anti-Revoke)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text("Bạn có thể thêm các tên miền ocsp.apple.com, ocsp2.apple.com vào mục Denylist trên NextDNS để tự động chống thu hồi chứng chỉ app.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(AppTheme.accent.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.accent.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Actions & Helpers
    
    private func toggleDNSAction() {
        Haptics.medium()
        if dnsManager.isEnabled {
            dnsManager.disableDNS()
        } else {
            let trimmed = configID.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                dnsManager.errorMessage = "Vui lòng nhập Configuration ID trước khi bật DNS!"
                Haptics.error()
                return
            }
            dnsManager.enableDNS(configID: trimmed, useUltraLowLatency: useUltraLowLatency)
        }
    }
    
    private func pasteFromClipboard() {
        if let text = UIPasteboard.general.string {
            configID = text.trimmingCharacters(in: .whitespacesAndNewlines)
            Haptics.light()
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
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.03))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .systemBackground).opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.15), Color.white.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 15, y: 8)
    }
}
