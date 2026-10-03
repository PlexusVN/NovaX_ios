import SwiftUI
import UIKit

struct ProfileView: View {
    var showSystemDashboard: Binding<Bool>? = nil
    @EnvironmentObject private var auth: AuthManager
    @ObservedObject private var updateManager = UpdateManager.shared

    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Spacer().frame(height: 8)

                    keyInfoPanel

                    keyDetailsCard

                    appUpdateCard

                    AirLiftDashboardCard()

                    developerCard

                    logoutButton

                    Spacer().frame(height: 120)
                }
                .padding(.horizontal, 16)
            }
            .background(MeshBackground())
            .navigationTitle("Hồ sơ")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.accent)
            .toolbar {
                if let showSystemDashboard = showSystemDashboard {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Haptics.light()
                            showSystemDashboard.wrappedValue = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(AppTheme.cyberCyan)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(AppTheme.cyberSurface.opacity(0.8)))
                                .overlay(Circle().stroke(AppTheme.cyberCyan.opacity(0.35), lineWidth: 1))
                                .shadow(color: AppTheme.cyberCyan.opacity(0.3), radius: 6)
                        }
                    }
                }
            }
            .onReceive(timer) { currentTime = $0 }
        }
    }

    // MARK: - Key Info Panel (centered avatar + key type)

    private var keyInfoPanel: some View {
        VStack(spacing: 0) {
            // Top glow line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0), AppTheme.accent.opacity(0.6), AppTheme.accent.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            VStack(spacing: 16) {
                Spacer().frame(height: 8)

                // App icon
                ZStack {
                    // Glow
                    Circle()
                        .fill(AppTheme.accent.opacity(0.08))
                        .frame(width: 120, height: 120)

                    // Outer ring
                    Circle()
                        .stroke(AppTheme.accent.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 110, height: 110)

                    // Inner ring
                    Circle()
                        .stroke(AppTheme.accent.opacity(0.12), lineWidth: 8)
                        .frame(width: 96, height: 96)
                        .blur(radius: 4)

                    if let icon = UIImage(named: "AppIcon60x60")
                        ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
                        ?? UIImage(named: "AppIcon") {
                        Image(uiImage: icon)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: AppTheme.accent.opacity(0.2), radius: 12)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 80, height: 80)
                            .background(AppTheme.accent.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }

                // App name + version
                VStack(spacing: 4) {
                    Text("NovaX")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.cyberGradient)

                    Text("v\(AppUpdateChecker.currentVersion)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                }

                // Key type badge
                HStack(spacing: 6) {
                    Image(systemName: keyTypeIcon)
                        .font(.system(size: 10, weight: .bold))
                    Text(keyTypeLabel)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundColor(keyTypeColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(keyTypeColor.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(keyTypeColor.opacity(0.3), lineWidth: 1))

                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: statusColor.opacity(0.5), radius: 4)
                    Text(statusLabel)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(statusColor)
                }

                Spacer().frame(height: 4)
            }

            // Bottom glow line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0), AppTheme.accent.opacity(0.6), AppTheme.accent.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.cyberSurface.opacity(0.65))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.cyberBorderGradient, lineWidth: 1.2)
                )
                .shadow(color: AppTheme.cyberCyan.opacity(0.12), radius: 20, y: 10)
        )
    }

    // MARK: - Key Details Card

    private var keyDetailsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.accent)
                    .frame(width: 24, height: 24)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("THÔNG TIN KEY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.accent)
                    .tracking(1)
                Spacer()
            }

            Divider().background(AppTheme.accent.opacity(0.12))
                .padding(.vertical, 12)

            VStack(spacing: 0) {
                keyDetailRow(
                    icon: "key.fill",
                    label: "License Key",
                    value: auth.licenseKey.isEmpty ? "Chưa kích hoạt" : auth.licenseKey,
                    isCopyable: !auth.licenseKey.isEmpty
                )

                keyDetailRow(
                    icon: "fingerprint",
                    label: "HWID",
                    value: auth.hwid,
                    isCopyable: true
                )

                keyDetailRow(
                    icon: "calendar.badge.clock",
                    label: "Ngày kích hoạt",
                    value: {
                        if let exp = auth.expiresAt {
                            return formatDateShort(exp.addingTimeInterval(-86400 * 30))
                        }
                        return "Chưa kích hoạt"
                    }()
                )

                keyDetailRow(
                    icon: "calendar.badge.exclamationmark",
                    label: "Ngày hết hạn",
                    value: {
                        if let exp = auth.expiresAt {
                            return formatDateShort(exp)
                        }
                        return "Không xác định"
                    }()
                )

                keyDetailRow(
                    icon: "tag.fill",
                    label: "Loại key",
                    value: keyTypeLabel,
                    valueColor: keyTypeColor
                )

                keyDetailRow(
                    icon: "clock.arrow.circlepath",
                    label: "Thời gian còn lại",
                    value: remainingTime
                )

                keyDetailRow(
                    icon: "checkmark.shield.fill",
                    label: "Trạng thái",
                    value: statusLabel,
                    valueColor: statusColor,
                    isLast: true
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.cyberSurface.opacity(0.6))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.cyberCyan.opacity(0.25), AppTheme.cyberPurple.opacity(0.12), Color.white.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        )
    }

    // MARK: - App Update Card

    private var appUpdateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.accent)
                    .frame(width: 24, height: 24)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("PHIÊN BẢN & CẬP NHẬT")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.accent)
                    .tracking(0.5)
                Spacer()

                Text("v\(AppUpdateChecker.currentVersion)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            Divider().background(AppTheme.accent.opacity(0.12))

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Trạng thái")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                    if let msg = updateManager.lastCheckedMessage {
                        Text(msg)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(updateManager.updateOffer != nil ? Color(hex: 0xFF5252) : Color.green)
                    } else {
                        Text("Đang chạy v\(AppUpdateChecker.currentVersion)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                Spacer()

                Button {
                    Haptics.light()
                    updateManager.checkForUpdate(showFeedback: true)
                } label: {
                    HStack(spacing: 6) {
                        if updateManager.isChecking {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                            Text("Kiểm tra")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.accent.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .disabled(updateManager.isChecking)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.cyberSurface.opacity(0.6))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.accent.opacity(0.3), AppTheme.accent.opacity(0.08), Color.white.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        )
    }

    private func keyDetailRow(
        icon: String,
        label: String,
        value: String,
        valueColor: Color = .white.opacity(0.8),
        isCopyable: Bool = false,
        isLast: Bool = false
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.accent.opacity(0.6))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                    Text(value)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(valueColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if isCopyable {
                    Button(action: {
                        Haptics.light()
                        UIPasteboard.general.string = value
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.accent.opacity(0.5))
                            .frame(width: 26, height: 26)
                            .background(AppTheme.accent.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
            .padding(.vertical, 10)

            if !isLast {
                Divider().background(Color.white.opacity(0.05))
                    .padding(.leading, 32)
            }
        }
    }

    // MARK: - Developer Card

    private var developerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.accent)
                    .frame(width: 24, height: 24)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("NHÀ PHÁT TRIỂN")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.accent)
                    .tracking(1)
                Spacer()
            }

            Divider().background(AppTheme.accent.opacity(0.12))
                .padding(.vertical, 12)

            // Developer info
            HStack(spacing: 14) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accent.opacity(0.35), AppTheme.accent.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle().stroke(AppTheme.accent.opacity(0.35), lineWidth: 1.5)
                        )
                    Text("MK")
                        .font(.system(size: 17, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Trần Minh Khải")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white.opacity(0.95))
                    Text("NovaX Developer")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppTheme.accent.opacity(0.7))
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.accent.opacity(0.5))
                        Text("0342145707")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }

                Spacer()
            }

            Divider().background(Color.white.opacity(0.05))
                .padding(.vertical, 12)

            // Action buttons
            HStack(spacing: 10) {
                Button(action: {
                    Haptics.light()
                    UIPasteboard.general.string = "0342145707"
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                        Text("Sao chép SĐT")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(PremiumButtonStyle(color: AppTheme.accent.opacity(0.4), cornerRadius: 8))

                Button(action: {
                    Haptics.light()
                    if let url = URL(string: "https://zalo.me/0342145707") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 10))
                        Text("Liên hệ Zalo")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(CyberGlowButtonStyle(cornerRadius: 8))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.cyberSurface.opacity(0.6))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.cyberCyan.opacity(0.25), AppTheme.cyberPurple.opacity(0.12), Color.white.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        )
    }

    // MARK: - Logout Button

    private var logoutButton: some View {
        Button(action: {
            Haptics.medium()
            auth.logout()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                Text("Đăng xuất")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(PremiumButtonStyle(color: .red, cornerRadius: 10))
    }

    // MARK: - Helpers

    private var keyTypeLabel: String {
        switch auth.keyType {
        case .vip, .admin: return "VIP SUPREME"
        case .pro:         return "PRO EDITION"
        case .basic:       return "FREE BASIC"
        }
    }

    private var keyTypeIcon: String {
        switch auth.keyType {
        case .vip, .admin: return "crown.fill"
        case .pro:         return "star.fill"
        case .basic:       return "tag.fill"
        }
    }

    private var keyTypeColor: Color {
        switch auth.keyType {
        case .vip, .admin: return Color(hex: 0xFFD700)
        case .pro:         return AppTheme.accent
        case .basic:       return .white.opacity(0.5)
        }
    }

    private var statusColor: Color {
        if auth.authState == .verified {
            return Color(hex: 0x00CC66)
        } else if case .error = auth.authState {
            return .red
        }
        return .white.opacity(0.4)
    }

    private var statusLabel: String {
        switch auth.authState {
        case .verified:
            return "ĐANG HOẠT ĐỘNG"
        case .loading:
            return "DANG XAC THUC..."
        case .error:
            return "LỖI XÁC THỰC"
        case .idle:
            return "CHƯA XÁC THỰC"
        }
    }

    private var remainingTime: String {
        guard let expires = auth.expiresAt else { return "Không xác định" }
        let now = Date()
        let interval = expires.timeIntervalSince(now)
        if interval <= 0 { return "Đã hết hạn" }
        let days = Int(interval / 86400)
        let hours = Int(interval.truncatingRemainder(dividingBy: 86400) / 3600)
        if days > 0 { return "\(days) ngày \(hours) giờ" }
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        return "\(hours) giờ \(minutes) phút"
    }

    private func formatDateShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: date)
    }
}
