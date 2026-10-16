import SwiftUI
import UIKit

/// LoginView - 2026 enterprise, doanh nghiệp, trắng-đen:
/// - Logo `NovaX-Logo-new.png` đơn sắc (đã grayscale), không vòng tròn trang trí.
/// - Card trắng, viền đen nhẹ, shadow mềm.
/// - Input key có icon chìa khóa đơn sắc, label lớn dễ đọc.
/// - Nút "XÁC THỰC NGAY" nền đen.
/// - Card "THÔNG TIN THIẾT BỊ" + "NHÀ PHÁT TRIỂN" đồng nhất.
/// - HWID có nút copy dễ thao tác.
struct LoginView: View {
    @ObservedObject var auth: AuthManager
    @EnvironmentObject var appState: AppState
    var namespace: Namespace.ID? = nil

    @State private var showKey: Bool = false
    @State private var cardOpacity: Double = 0
    @State private var cardOffset: CGFloat = 18
    @State private var logoAppear: Bool = false
    @State private var showCommunityAlert: Bool = false

    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 56)

                    // Logo - đơn sắc, không glow quanh
                    logoBlock
                        .padding(.bottom, 22)

                    // Brand title
                    brandTitle
                        .padding(.bottom, 30)

                    // Card kích hoạt
                    activationCard
                        .padding(.horizontal, 20)

                    // Nút XÁC THỰC NGAY
                    activateButton
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 24)

                    // Thông tin thiết bị
                    deviceCard
                        .padding(.horizontal, 20)

                    // Nhà phát triển
                    developerCard
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 56)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear { startEntryAnimation() }
        .overlay {
            if showCommunityAlert {
                communityAlert
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(100)
            }
        }
    }

    // MARK: - Sections

    private var logoBlock: some View {
        let logo = AppLogo(size: 92)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.13), radius: 22, x: 0, y: 12)
            .saturation(0)
            .contrast(1.08)
            .scaleEffect(logoAppear ? 1 : 0.96)

        // matchedGeometryEffect: khi splash morph xong, logo sẽ "tiếp quản" ở vị trí hiện tại
        if let ns = namespace {
            return AnyView(
                logo
                    .matchedGeometryEffect(id: "appLogo", in: ns, isSource: true)
                    .opacity(logoAppear ? 1 : 0)
            )
        } else {
            return AnyView(
                logo
                    .opacity(logoAppear ? 1 : 0)
            )
        }
    }

    private var brandTitle: some View {
        VStack(spacing: 9) {
            Text("NovaX")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .kerning(-1.5)
                .lineSpacing(0)

            Text("KHAI PHÁ HỆ THỐNG")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.grey500)
                .tracking(2.2)
        }
        .opacity(logoAppear ? 1 : 0)
        .offset(y: logoAppear ? 0 : 8)
    }

    private var activationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.ink, lineWidth: 1)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .frame(width: 42, height: 42)
                    Image(systemName: "key.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("KÍCH HOẠT HỆ THỐNG")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Nhập license key để bắt đầu")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.grey500)
                }
                Spacer()
                statusPill
            }

            Rectangle()
                .fill(AppTheme.grey200)
                .frame(height: 1)
                .padding(.vertical, 18)

            // Key label + input
            Text("MÃ KÍCH HOẠT")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.grey700)
                .tracking(0.7)
                .padding(.bottom, 9)

            HStack(spacing: 11) {
                Image(systemName: "key.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 22)

                Group {
                    if showKey {
                        TextField("Nhập license key", text: $auth.licenseKey)
                    } else {
                        SecureField("Nhập license key", text: $auth.licenseKey)
                    }
                }
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.system(size: 16, design: .monospaced))
                .foregroundStyle(AppTheme.ink)

                Button {
                    Haptics.light()
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 15)
            .frame(height: 58)
            .background(Color(red: 0.984, green: 0.984, blue: 0.988))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.grey300, lineWidth: 1)
            )

            // HWID row
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("HWID")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(AppTheme.grey500)
                    Text(auth.hwid)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppTheme.grey700)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button {
                    Haptics.light()
                    UIPasteboard.general.string = auth.hwid
                    Haptics.success()
                } label: {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 36, height: 36)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.grey200, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(AppTheme.grey50)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.grey100, lineWidth: 1)
            )
            .padding(.top, 14)
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.grey200, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 22, x: 0, y: 12)
        .opacity(cardOpacity)
        .offset(y: cardOffset)
    }

    private var statusPill: some View {
        let isOn = auth.authState == .verified
        return HStack(spacing: 4) {
            Circle()
                .fill(isOn ? AppTheme.ink : AppTheme.grey400)
                .frame(width: 6, height: 6)
            Text(isOn ? "ON" : "OFF")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(isOn ? AppTheme.ink : AppTheme.grey500)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(AppTheme.grey50)
        .clipShape(Capsule())
    }

    private var activateButton: some View {
        Button {
            Haptics.medium()
            Task { await auth.login() }
        } label: {
            HStack(spacing: 9) {
                if case .loading(let text) = auth.authState {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                    Text(text)
                        .font(.system(size: 15, weight: .semibold))
                } else {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 17, weight: .semibold))
                    Text("XÁC THỰC NGAY")
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(0.2)
                }
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(PrimaryButtonStyle())
        .opacity(cardOpacity)
        .offset(y: cardOffset)
        .disabled(auth.licenseKey.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "iphone")
                    .font(.system(size: 13))
                Text("THÔNG TIN THIẾT BỊ")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.4)
            }
            .foregroundStyle(AppTheme.ink)

            Divider().background(AppTheme.grey200)

            deviceRow("Phiên bản iOS:", value: "iOS \(AppInfo.osVersion)", isMonoValue: true)
            deviceRow("Trạng thái hỗ trợ:",
                      value: appState.accessLevelDescription.uppercased(),
                      isMonoValue: true, valueColor: appState.isSupported ? AppTheme.ink : AppTheme.ink)
        }
        .padding(19)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.grey200, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 10)
        .opacity(cardOpacity)
        .offset(y: cardOffset)
    }

    private func deviceRow(_ label: String, value: String, isMonoValue: Bool = false, valueColor: Color = AppTheme.ink) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.grey700)
            Spacer()
            Text(value)
                .font(.system(size: isMonoValue ? 12 : 14, weight: .semibold, design: isMonoValue ? .monospaced : .rounded))
                .foregroundStyle(valueColor)
        }
        .padding(.vertical, 4)
    }

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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Liên hệ hỗ trợ trực tiếp")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.grey500)
                }
                Spacer()
            }

            Rectangle()
                .fill(AppTheme.grey200)
                .frame(height: 1)
                .padding(.vertical, 16)

            // Admin info
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.ink)
                        .frame(width: 44, height: 44)
                    Text("MK")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Trần Minh Khải")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Nhà phát triển NovaX")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.grey500)
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(AppTheme.grey500)
                        Text("0342145707")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.grey600)
                    }
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    Haptics.light()
                    if let url = URL(string: "https://zalo.me/0342145707") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Liên hệ Zalo")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(AppTheme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showCommunityAlert = true
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Cộng đồng")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.ink, lineWidth: 1)
                    )
                }
            }
            .padding(.top, 16)
        }
        .padding(19)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.grey200, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 10)
        .opacity(cardOpacity)
        .offset(y: cardOffset)
    }

    // MARK: - Community alert

    private var communityAlert: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showCommunityAlert = false
                    }
                }

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.ink)
                        .padding(.top, 8)
                    Text("Tham gia cộng đồng")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Vui lòng chọn nhóm Zalo bạn muốn tham gia để nhận key và hỗ trợ.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.grey600)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.vertical, 20)

                Rectangle().fill(AppTheme.grey200).frame(height: 1)

                VStack(spacing: 12) {
                    communityButton(title: "BOX 1 - NovaX",
                                    url: "https://zalo.me/g/i1bffsvvb6wijb3l0gc8")
                    communityButton(title: "BOX 2 - NovaX",
                                    url: "https://zalo.me/g/wbsfu5a3mcp4uodtebft")
                }
                .padding(16)

                Rectangle().fill(AppTheme.grey200).frame(height: 1)

                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showCommunityAlert = false
                    }
                } label: {
                    Text("Đóng")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.grey600)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 35, x: 0, y: 15)
            .padding(.horizontal, 28)
        }
    }

    private func communityButton(title: String, url: String) -> some View {
        Button {
            Haptics.light()
            if let url = URL(string: url) { UIApplication.shared.open(url) }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showCommunityAlert = false
            }
        } label: {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                Text(title)
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(AppTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.grey50)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.ink, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Error section (nếu có)

    @ViewBuilder
    private func errorSection(_ msg: String) -> some View {
        if case .error(let msg) = auth.authState {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.ink)
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.ink)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(AppTheme.grey50)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.ink, lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Entry animation

    private func startEntryAnimation() {
        withAnimation(.easeOut(duration: 0.6)) {
            logoAppear = true
        }
        withAnimation(.easeOut(duration: 0.55).delay(0.35)) {
            cardOpacity = 1
            cardOffset = 0
        }
    }
}
