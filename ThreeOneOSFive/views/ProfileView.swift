import SwiftUI
import UIKit

/// ProfileView - 2026 enterprise Hồ sơ dễ đọc:
/// - Hero: logo + NovaX + Phiên bản + PREMIUM + status "Hoạt động".
/// - License card (key) - nền đen, copy dễ.
/// - Lưới 2 cột HWID/Ngày/Ngày hết hạn/Loại key/Còn lại (responsive về 1 cột trên màn nhỏ).
/// - Hàng trạng thái key riêng.
/// - Phiên bản & cập nhật: số to + nút kiểm tra.
/// - Phiên đăng nhập: nút Đăng xuất key (chevron).
/// - Modal xác nhận đăng xuất key.
struct ProfileView: View {
    var showSystemDashboard: Binding<Bool>? = nil
    @EnvironmentObject private var auth: AuthManager
    @ObservedObject private var updateManager = UpdateManager.shared

    @State private var showLogoutModal: Bool = false
    @State private var appear: Bool = false

    private static let version: String = AppUpdateChecker.currentVersion
    private static let build: String = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    // 1. Hero card
                    profileHero
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 12)

                    // 2. Thông tin key
                    licenseCard
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 12)

                    // 3. Phiên bản & cập nhật
                    updateCard
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 12)

                    // 4. Phiên đăng nhập - Đăng xuất key
                    sessionCard
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 12)

                    // 5. Nhà phát triển
                    developerCard
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 12)

                    Spacer().frame(height: 120)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(MeshBackground())
            .navigationTitle("Hồ sơ")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.ink)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Haptics.light()
                        showSystemDashboard?.wrappedValue = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 32, height: 32)
                            .background(Color.white)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(AppTheme.grey200, lineWidth: 1))
                    }
                }
            }
            .overlay {
                if showLogoutModal {
                    logoutConfirmModal
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                        .zIndex(50)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { appear = true }
        }
    }

    // MARK: - Hero card

    private var profileHero: some View {
        HStack(spacing: 14) {
            AppLogo(size: 70)
                .saturation(0)
                .contrast(1.08)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(AppTheme.grey200, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text("NovaX")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .kerning(-0.6)

                Text("Phiên bản \(Self.version)")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.grey500)

                Text("PREMIUM")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(AppTheme.grey50)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(AppTheme.statusSuccess)
                    .frame(width: 7, height: 7)
                Text("Hoạt động")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.statusSuccess)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(AppTheme.grey50)
            .clipShape(Capsule())
        }
        .frame(minHeight: 112, alignment: .center)
        .padding(19)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.grey200, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 6)
    }

    // MARK: - License card

    private var licenseCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(AppTheme.ink)
                        .frame(width: 42, height: 42)
                    Image(systemName: "key.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Thông tin key")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .kerning(-0.25)
                    Text("Thông tin kích hoạt trên thiết bị này")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.grey500)
                }
                Spacer()
            }
            .padding(.bottom, 17)

            // License dark block
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("LICENSE KEY")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(AppTheme.grey400)
                        .tracking(1.1)
                    Spacer()
                    Button {
                        Haptics.light()
                        UIPasteboard.general.string = auth.licenseKey
                        Haptics.success()
                    } label: {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 36, height: 36)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Text(auth.licenseKey.isEmpty ? "Chưa kích hoạt" : auth.licenseKey)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(17)
            .background(AppTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

            // Info grid (2 cột, tự về 1 cột <380px)
            infoGrid

            // Trạng thái key - tách riêng
            HStack(spacing: 8) {
                Circle().fill(keyStatusColor).frame(width: 7, height: 7)
                Text("Trạng thái key")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.grey500)
                Spacer()
                Text(keyStatusLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(keyStatusColor)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(AppTheme.grey200, lineWidth: 1)
            )
            .padding(.top, 12)
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.grey200, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
    }

    private var infoGrid: some View {
        // 2 cột, nếu HWID quá dài thì cho full width
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
        return LazyVGrid(columns: columns, spacing: 10) {
            infoCell(icon: "iphone.gen3", label: "HWID thiết bị",
                     value: auth.hwid, isMono: true, fullWidth: true)
            infoCell(icon: "calendar.badge.clock", label: "Ngày kích hoạt",
                     value: formatDate(auth.expiresAt.map { $0.addingTimeInterval(-86400 * 30) }))
            infoCell(icon: "calendar.badge.exclamationmark", label: "Ngày hết hạn",
                     value: auth.expiresAt.map(formatDate) ?? "Không xác định")
            infoCell(icon: "tag.fill", label: "Loại key",
                     value: keyTypeLabel)
            infoCell(icon: "clock.arrow.circlepath", label: "Thời gian còn lại",
                     value: remainingTime)
        }
        .padding(.top, 12)
    }

    private func infoCell(icon: String, label: String, value: String, isMono: Bool = false, fullWidth: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.grey500)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(AppTheme.grey500)
            }
            Text(value)
                .font(.system(size: fullWidth ? 13 : 15, weight: .semibold,
                              design: fullWidth || isMono ? .monospaced : .rounded))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(fullWidth ? 1 : 2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.grey50)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .gridCellColumns(fullWidth ? 2 : 1)
    }

    // MARK: - Update card

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(AppTheme.ink)
                        .frame(width: 42, height: 42)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Phiên bản & cập nhật")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .kerning(-0.25)
                    Text("Thông tin bản dựng hiện tại")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.grey500)
                }
                Spacer()
            }

            Divider().background(AppTheme.grey200)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("PHIÊN BẢN")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(AppTheme.grey500)
                        .tracking(0.8)
                    HStack(alignment: .lastTextBaseline, spacing: 9) {
                        Text(Self.version)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                            .kerning(-1)
                        Text("Build \(Self.build)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.grey500)
                    }
                }
                Spacer()
                Text(updateStatusPresentation.label)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(updateStatusPresentation.color.opacity(0.10))
                    .overlay(
                        Capsule()
                            .stroke(updateStatusPresentation.color.opacity(0.24), lineWidth: 1)
                    )
                    .foregroundStyle(updateStatusPresentation.color)
                    .clipShape(Capsule())
            }
            .padding(16)
            .background(AppTheme.grey50)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )

            Button {
                Haptics.medium()
                updateManager.checkForUpdate(showFeedback: true)
            } label: {
                HStack(spacing: 8) {
                    if updateManager.isChecking {
                        ProgressView().tint(AppTheme.statusInfo).scaleEffect(0.85)
                        Text("Đang kiểm tra…")
                            .font(.system(size: 14, weight: .semibold))
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Kiểm tra cập nhật")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(OutlineButtonStyle())
            .disabled(updateManager.isChecking)

            if let message = updateManager.lastCheckedMessage {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: updateManager.updateOffer == nil ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(updateManager.updateOffer == nil ? AppTheme.statusSuccess : AppTheme.statusInfo)
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.grey200, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
    }

    // MARK: - Session card

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(AppTheme.ink)
                        .frame(width: 42, height: 42)
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Phiên đăng nhập")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .kerning(-0.25)
                    Text("Quản lý license key đang sử dụng")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.grey500)
                }
                Spacer()
            }

            Button {
                Haptics.medium()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                    showLogoutModal = true
                }
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Đăng xuất key")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text("Trở về màn hình nhập license key")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.grey500)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.grey400)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 65)
                .background(AppTheme.grey50)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.grey200, lineWidth: 1)
                )
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.grey200, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
    }

    // MARK: - Developer card

    private var developerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.ink, lineWidth: 1)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .frame(width: 42, height: 42)
                    Image(systemName: "person.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("NHÀ PHÁT TRIỂN")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("NovaX Developer")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.grey500)
                }
                Spacer()
            }

            Rectangle()
                .fill(AppTheme.grey200)
                .frame(height: 1)
                .padding(.vertical, 16)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.ink)
                        .frame(width: 48, height: 48)
                    Text("MK")
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Trần Minh Khải")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("☎ 0342145707")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppTheme.grey500)
                }
                Spacer()
            }

            Button {
                Haptics.light()
                if let url = URL(string: "https://zalo.me/0342145707") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Liên hệ Zalo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(AppTheme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.grey200, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 6)
    }

    // MARK: - Logout modal

    private var logoutConfirmModal: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        showLogoutModal = false
                    }
                }

            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(AppTheme.ink)
                            .frame(width: 62, height: 62)
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 4)

                    Text("Đăng xuất key?")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .kerning(-0.45)

                    Text("Phiên license hiện tại sẽ được xóa khỏi NovaX và bạn sẽ trở về màn hình nhập key.")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.grey500)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.grey600)
                            .padding(.top, 1)
                        Text("Thao tác này không tự khôi phục những tệp đã áp dụng.")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.grey700)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.grey50)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(AppTheme.grey200, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 8)

                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            showLogoutModal = false
                        }
                    } label: {
                        Text("Hủy")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(AppTheme.grey50)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppTheme.grey200, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        performLogout()
                    } label: {
                        Text("Đăng xuất")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(AppTheme.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Color.black.opacity(0.20), radius: 40, x: 0, y: 18)
            .padding(.horizontal, 28)
        }
    }

    private func performLogout() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            showLogoutModal = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            auth.logout()
        }
    }

    // MARK: - Helpers

    private var keyTypeLabel: String {
        switch auth.keyType {
        case .vip, .admin: return "Premium"
        case .pro:         return "Pro"
        case .basic:       return "Basic"
        }
    }

    private var keyStatusLabel: String {
        switch auth.authState {
        case .verified: return "Đang hoạt động"
        case .loading:  return "Đang xác thực…"
        case .error:    return "Lỗi xác thực"
        case .idle:     return "Chưa xác thực"
        }
    }

    private var keyStatusColor: Color {
        switch auth.authState {
        case .verified: return AppTheme.statusSuccess
        case .loading:  return AppTheme.statusInfo
        case .error, .idle: return AppTheme.statusError
        }
    }

    private var updateStatusPresentation: (label: String, color: Color) {
        if updateManager.isChecking {
            return ("Đang kiểm tra", AppTheme.statusInfo)
        }
        if updateManager.updateOffer != nil {
            return ("Có cập nhật", AppTheme.statusInfo)
        }
        if updateManager.hasChecked {
            return ("Mới nhất", AppTheme.statusSuccess)
        }
        return ("Chưa kiểm tra", AppTheme.statusInfo)
    }

    private var remainingTime: String {
        guard let expires = auth.expiresAt else { return "Vĩnh viễn" }
        let interval = expires.timeIntervalSinceNow
        if interval <= 0 { return "Đã hết hạn" }
        let days = Int(interval / 86400)
        let hours = Int(interval.truncatingRemainder(dividingBy: 86400) / 3600)
        if days > 0 { return "\(days) ngày \(hours) giờ" }
        let mins = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        return "\(hours) giờ \(mins) phút"
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Chưa kích hoạt" }
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        f.locale = Locale(identifier: "vi_VN")
        return f.string(from: date)
    }
}
