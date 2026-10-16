//
//  SplashLoginView.swift
//  ThreeOneOSFive
//
//  GỘP Splash + Login thành 1 màn hình duy nhất (liền mạch, không có 2 màn hình tách biệt).
//  Logo morph từ vị trí chính giữa màn hình (112x112) sang vị trí đầu màn hình đăng nhập (92x92)
//  thông qua matchedGeometryEffect, hiển thị liên tục, sắc nét và cố định vĩnh viễn trên đỉnh form đăng nhập.
//

import SwiftUI
import UIKit

struct SplashLoginView: View {
    @ObservedObject var auth: AuthManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updateManager: UpdateManager

    enum Phase: Equatable {
        case loading          // Splash: Logo 112 ở giữa + progress bar chạy mượt mà bên dưới
        case transitioning    // Logo morph trong khi splash và login cùng tồn tại
        case ready            // Login: Logo morph 92 cố định ở trên đầu + form hiển thị đầy đủ
    }

    @State private var phase: Phase
    @State private var loadProgress: CGFloat = 0.05
    @State private var statusText: String = "Đang khởi tạo"
    @State private var pulseOpacity: Double = 0.35
    @State private var sheenOffset: CGFloat = -160

    // Gradual entrance cho màn hình splash
    @State private var splashLogoOpacity: Double = 0.0
    @State private var splashLogoScale: CGFloat = 0.90
    @State private var splashIdentityOpacity: Double = 0.0
    @State private var splashBottomOpacity: Double = 0.0
    @State private var splashLayerOpacity: Double = 1.0

    // Reveal animation cho form đăng nhập
    @State private var formOpacity: Double = 0.0
    @State private var formOffset: CGFloat = 18

    @State private var showKey: Bool = false
    @State private var showCommunityAlert: Bool = false

    @Namespace private var logoNamespace
    private static var hasCompletedInitialSplash = false

    init(auth: AuthManager) {
        self.auth = auth
        if Self.hasCompletedInitialSplash {
            _phase = State(initialValue: .ready)
            _formOpacity = State(initialValue: 1.0)
            _formOffset = State(initialValue: 0.0)
        } else {
            _phase = State(initialValue: .loading)
        }
    }

    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()

            if phase != .loading {
                loginView
                    .zIndex(1)
            }

            if phase != .ready {
                splashView
                    .opacity(splashLayerOpacity)
                    .allowsHitTesting(false)
                    .zIndex(2)
            }
        }
        .overlay {
            if showCommunityAlert {
                communityAlert
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .onAppear {
            startLoadingSequence()
        }
        .animation(.easeInOut(duration: 0.22), value: authErrorMessage)
    }

    // MARK: - Splash View (giao diện loading khởi động)

    private var splashView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Logo 112x112 ở giữa màn hình (chuẩn HTML: width 112, height 112, border-radius 29)
                Group {
                    if phase == .loading {
                        appLogoView(size: 112, cornerRadius: 29)
                            .matchedGeometryEffect(id: "NOVAX_AVATAR_LOGO", in: logoNamespace)
                            .scaleEffect(splashLogoScale)
                            .opacity(splashLogoOpacity)
                            .overlay(
                                RoundedRectangle(cornerRadius: 29, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.0),
                                                Color.white.opacity(0.60),
                                                Color.white.opacity(0.0)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .offset(x: sheenOffset)
                                    .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
                                    .allowsHitTesting(false)
                            )
                    } else {
                        Color.clear
                            .frame(width: 112, height: 112)
                    }
                }

                VStack(spacing: 10) {
                    Text("NovaX")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .kerning(-1.35)

                    Text("KHAI PHÁ HỆ THỐNG")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.grey500)
                        .tracking(2.25)
                }
                .opacity(splashIdentityOpacity)
            }

            Spacer()

            // Thanh tiến trình chạy từ từ, mượt mà và status text (chuẩn HTML: width 210, height 2, bg #dedee2, dot 5x5)
            VStack(spacing: 13) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(hex: 0xDEDEE2))
                            .frame(height: 2)

                        Capsule()
                            .fill(AppTheme.ink)
                            .frame(width: max(0, min(geo.size.width * loadProgress, geo.size.width)), height: 2)
                    }
                }
                .frame(width: 210, height: 2)

                HStack(spacing: 8) {
                    Circle()
                        .fill(AppTheme.ink)
                        .frame(width: 5, height: 5)
                        .opacity(pulseOpacity)

                    Text(statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x58585D))
                        .tracking(0.1)
                        .frame(height: 18)
                }
            }
            .padding(.bottom, 66)
            .opacity(splashBottomOpacity)
        }
    }

    // MARK: - Login View (giao diện đăng nhập sau khi load xong)

    private var loginView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Logo 92x92 cố định hiển thị trên đỉnh form đăng nhập, luôn có mặt (không bao giờ bị mất)
                appLogoView(size: 92, cornerRadius: 24)
                    .matchedGeometryEffect(id: "NOVAX_AVATAR_LOGO", in: logoNamespace)
                    .padding(.top, 44)
                    .padding(.bottom, 16)

                brandTitle
                    .opacity(formOpacity)
                    .offset(y: formOffset * 0.5)
                    .animation(loginRevealAnimation(delay: 0), value: formOpacity)

                // Divider hairline 54x1 chuẩn HTML (styles.css: width 54px; height 1px; background #000; margin 20px auto 30px)
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 54, height: 1)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                    .opacity(formOpacity)
                    .animation(loginRevealAnimation(delay: 0.065), value: formOpacity)

                activationCard
                    .padding(.horizontal, 20)
                    .opacity(formOpacity)
                    .offset(y: formOffset)
                    .animation(loginRevealAnimation(delay: 0.13), value: formOpacity)

                activateButton
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                    .opacity(formOpacity)
                    .offset(y: formOffset)
                    .animation(loginRevealAnimation(delay: 0.195), value: formOpacity)

                deviceCard
                    .padding(.horizontal, 20)
                    .opacity(formOpacity)
                    .offset(y: formOffset)
                    .animation(loginRevealAnimation(delay: 0.26), value: formOpacity)

                developerCard
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 56)
                    .opacity(formOpacity)
                    .offset(y: formOffset)
                    .animation(loginRevealAnimation(delay: 0.325), value: formOpacity)
            }
        }
        .adaptiveScrollBounceBehavior()
    }

    // MARK: - Reusable App Logo View (Avatar hiển thị sắc nét)

    @ViewBuilder
    private func appLogoView(size: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            Color.white

            if let icon = UIImage(named: "NovaXLogo")
                ?? UIImage(named: "AppIcon60x60")
                ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
                ?? UIImage(named: "AppIcon") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.13), radius: 18, x: 0, y: 10)
    }

    // MARK: - Brand title

    private var brandTitle: some View {
        VStack(spacing: 9) {
            Text("NovaX")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .kerning(-1.5)

            Text("KHAI PHÁ HỆ THỐNG")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x5D5D62))
                .tracking(2.2)
        }
    }

    // MARK: - Activation card

    private var activationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    .stroke(authErrorMessage == nil ? AppTheme.grey300 : Color(red: 0.78, green: 0.13, blue: 0.13), lineWidth: 1)
            )

            if let errorMessage = authErrorMessage {
                authErrorBanner(errorMessage)
                    .padding(.top, 12)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        )
                    )
            }

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
    }

    private var authErrorMessage: String? {
        guard case .error(let message) = auth.authState else { return nil }
        return message
    }

    private var authStatusPresentation: (label: String, foreground: Color, dot: Color) {
        switch auth.authState {
        case .verified:
            return ("ON", AppTheme.ink, AppTheme.ink)
        case .loading:
            return ("WAIT", AppTheme.grey700, AppTheme.grey600)
        case .error:
            let red = Color(red: 0.78, green: 0.13, blue: 0.13)
            return ("ERROR", red, red)
        case .idle:
            return ("OFF", AppTheme.grey500, AppTheme.grey400)
        }
    }

    private func authErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(red: 0.78, green: 0.13, blue: 0.13))

            VStack(alignment: .leading, spacing: 4) {
                Text("KHÔNG THỂ XÁC THỰC")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.45)
                    .foregroundStyle(AppTheme.ink)

                Text(message)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AppTheme.grey700)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(13)
        .background(Color(red: 1.0, green: 0.965, blue: 0.965))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(red: 0.78, green: 0.13, blue: 0.13).opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lỗi xác thực: \(message)")
    }

    private var statusPill: some View {
        let presentation = authStatusPresentation
        return HStack(spacing: 4) {
            Circle()
                .fill(presentation.dot)
                .frame(width: 6, height: 6)
            Text(presentation.label)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(presentation.foreground)
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

    // MARK: - Loading sequence (Hiệu ứng load từ từ + thanh tiến trình mượt mà)

    private func loginRevealAnimation(delay: Double) -> Animation {
        .timingCurve(0.22, 0.75, 0.30, 1.0, duration: 0.50)
            .delay(delay)
    }

    private func startLoadingSequence() {
        guard phase == .loading else { return }

        // Chấm tròn nhấp nháy êm ái
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseOpacity = 1.0
        }

        // 1. Hiệu ứng load từ từ: Logo fade in từ từ 0 -> 1 và scale từ 0.90 -> 1.0 trong 0.7s
        withAnimation(.easeOut(duration: 0.7)) {
            splashLogoOpacity = 1.0
            splashLogoScale = 1.0
        }

        // Vệt sáng đơn sắc lướt qua mặt logo
        withAnimation(.easeInOut(duration: 1.15).delay(0.2)) {
            sheenOffset = 160
        }

        // Tên thương hiệu fade in nhẹ sau 0.2s
        withAnimation(.easeOut(duration: 0.55).delay(0.2)) {
            splashIdentityOpacity = 1.0
        }

        // Thanh tiến trình và status fade in sau 0.3s
        withAnimation(.easeOut(duration: 0.45).delay(0.3)) {
            splashBottomOpacity = 1.0
        }

        // 2. Thanh tiến trình chạy từ từ, mượt mà qua các chặng
        Task { @MainActor in
            // Chặng 1: 0% -> 45% (Đang khởi tạo)
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.easeInOut(duration: 0.45)) {
                loadProgress = 0.45
                statusText = "Đang khởi tạo"
            }

            // Chặng 2: 45% -> 80% (Đang chuẩn bị không gian làm việc)
            try? await Task.sleep(nanoseconds: 480_000_000)
            withAnimation(.easeInOut(duration: 0.48)) {
                loadProgress = 0.80
                statusText = "Đang chuẩn bị không gian làm việc"
            }

            // Chặng 3: 80% -> 100% (Sẵn sàng)
            try? await Task.sleep(nanoseconds: 500_000_000)
            withAnimation(.easeInOut(duration: 0.35)) {
                loadProgress = 1.0
                statusText = "Sẵn sàng"
            }

            // Đợi thanh chạm 100% trọn vẹn
            try? await Task.sleep(nanoseconds: 380_000_000)

            // Đánh dấu đã qua màn hình splash lần đầu
            Self.hasCompletedInitialSplash = true

            // Fade out nhẹ chi tiết phụ của splash (thanh progress & text)
            withAnimation(.easeOut(duration: 0.22)) {
                splashBottomOpacity = 0.0
                splashIdentityOpacity = 0.0
            }

            try? await Task.sleep(nanoseconds: 100_000_000)

            // Khớp nhịp HTML: logo morph 0.74s, nền splash mờ dần phía trên login.
            withAnimation(.timingCurve(0.22, 0.75, 0.30, 1.0, duration: 0.74)) {
                phase = .transitioning
            }
            withAnimation(.easeInOut(duration: 0.50).delay(0.10)) {
                splashLayerOpacity = 0.0
            }

            try? await Task.sleep(nanoseconds: 740_000_000)
            phase = .ready

            // Mỗi khối dùng delay riêng để tạo hiệu ứng stagger giống bản HTML.
            formOpacity = 1.0
            formOffset = 0.0
        }
    }
}

extension View {
    @ViewBuilder
    fileprivate func adaptiveScrollBounceBehavior() -> some View {
        if #available(iOS 16.4, *) {
            self.scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}
