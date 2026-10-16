//
//  SplashLoginView.swift
//  ThreeOneOSFive
//
//  GỘP Splash + Login thành 1 màn hình duy nhất (liền mạch, không có 2 màn hình tách biệt).
//  Giống cấu trúc HTML: logo morph từ giữa (112x112) → vị trí đăng nhập (92x92) trên cùng
//  một view, cùng một ZStack, cùng một ScrollView — không có "chuyển cảnh" giữa 2 view.
//

import SwiftUI
import UIKit

struct SplashLoginView: View {
    @ObservedObject var auth: AuthManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updateManager: UpdateManager

    enum Phase: Equatable {
        case loading          // Logo 112 ở center + status text loading bên dưới
        case ready            // Logo morph 92 ở top + form trượt lên
    }

    @State private var phase: Phase = .loading
    @State private var statusText: String = "Đang khởi tạo"
    @State private var showKey: Bool = false
    @State private var showCommunityAlert: Bool = false

    // Morph state
    @State private var identityOpacity: Double = 1
    @State private var loadingOpacity: Double = 1
    @State private var isMorphing: Bool = false

    // Reveal state (form trượt lên sau khi morph xong)
    @State private var formOpacity: Double = 0
    @State private var formOffset: CGFloat = 18
    @State private var brandOpacity: Double = 0
    @State private var brandOffset: CGFloat = 8

    // Loading status steps (giống splashSteps trong HTML)
    private let statusSteps = [
        "Đang khởi tạo",
        "Đang chuẩn bị không gian làm việc",
        "Sẵn sàng"
    ]
    private let statusInterval: Double = 0.47
    private let minLoadingDuration: Double = 1.5  // Khớp HTML: setTimeout(transitionToLogin, 1500)

    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // === HEADER ZONE: chứa logo morph + brand title ===
                    // Logo: ở giữa khi loading, ở top khi ready
                    // Brand title: ẩn khi loading, hiện dưới logo khi ready
                    headerZone
                        .padding(.top, phase == .loading ? 220 : 56)
                        .padding(.bottom, phase == .loading ? 0 : 22)

                    // === BODY ZONE: status text (loading) HOẶC form (ready) ===
                    if phase == .loading {
                        loadingStatusSection
                            .padding(.top, 28)
                    } else {
                        brandTitle
                            .padding(.bottom, 30)
                            .opacity(brandOpacity)
                            .offset(y: brandOffset)

                        activationCard
                            .padding(.horizontal, 20)
                            .opacity(formOpacity)
                            .offset(y: formOffset)

                        activateButton
                            .padding(.horizontal, 20)
                            .padding(.top, 18)
                            .padding(.bottom, 24)
                            .opacity(formOpacity)
                            .offset(y: formOffset)

                        deviceCard
                            .padding(.horizontal, 20)
                            .opacity(formOpacity)
                            .offset(y: formOffset)

                        developerCard
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 56)
                            .opacity(formOpacity)
                            .offset(y: formOffset)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
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
    }

    // MARK: - Header zone (logo + brand, ở giữa khi loading, ở top khi ready)

    @ViewBuilder
    private var headerZone: some View {
        VStack(spacing: 24) {
            // Logo morph: 112x112 ở giữa → 92x92 ở top
            // Outer clipShape + overlay + shadow + offset + scaleEffect control hoàn toàn
            resizableLogo(size: 112)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(
                        cornerRadius: isMorphing ? 24 : 29,
                        style: .continuous
                    )
                    .stroke(Color.black.opacity(0.13), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.16), radius: 22, x: 0, y: 12)
                .clipShape(RoundedRectangle(
                    cornerRadius: isMorphing ? 24 : 29,
                    style: .continuous
                ))
                .offset(y: isMorphing ? -220 + 56 : 0)  // morph từ center (padding 220) → top (padding 56)
                .scaleEffect(isMorphing ? 92.0 / 112.0 : 1.0)
                .opacity(loadingOpacity)
        }
    }

    // MARK: - Loading status (chỉ hiện khi phase == .loading)

    private var loadingStatusSection: some View {
        VStack(spacing: 16) {
            // Spinner / progress bar
            ProgressView()
                .progressViewStyle(.linear)
                .tint(AppTheme.ink)
                .frame(width: 180)
                .scaleEffect(y: 0.7)

            // Status text
            Text(statusText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.grey500)
                .tracking(0.5)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .frame(height: 18)
        }
        .opacity(loadingOpacity)
    }

    // MARK: - Brand title (chỉ hiện khi phase == .ready)

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
    }

    // MARK: - Image resizable

    @ViewBuilder
    private func resizableLogo(size: CGFloat) -> some View {
        if let icon = UIImage(named: "NovaXLogo")
            ?? UIImage(named: "AppIcon60x60")
            ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
            ?? UIImage(named: "AppIcon") {
            Image(uiImage: icon)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .saturation(0)
                .contrast(1.08)
        } else {
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(AppTheme.ink)
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
                    .stroke(AppTheme.grey300, lineWidth: 1)
            )

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

    // MARK: - Loading sequence (timeline khớp HTML chính xác)

    private func startLoadingSequence() {
        // Bước 1: chạy status text cycle (giống HTML setInterval 470ms)
        Task { @MainActor in
            for i in 1..<statusSteps.count {
                try? await Task.sleep(nanoseconds: UInt64(statusInterval * 1_000_000_000))
                withAnimation(.easeInOut(duration: 0.25)) {
                    statusText = statusSteps[i]
                }
            }
        }

        // Bước 2: sau 1500ms (khớp HTML setTimeout), chuyển sang phase ready
        // Timeline:
        //   t=0ms:   loading hiển thị (logo 112 ở center, status text bên dưới)
        //   t=80ms:  logo morph START (offset y: 0 → -164, scale 1 → 0.821)
        //   t=820ms: morph xong → status text + loading fade out
        //   t=820ms: form + brand title stagger fade in
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(minLoadingDuration * 1_000_000_000))
            await performTransitionToReady()
        }
    }

    private func performTransitionToReady() async {
        // Fade out status/loading ở t=0 (khớp HTML .splash-identity fade out .22s)
        withAnimation(.easeOut(duration: 0.22)) {
            identityOpacity = 0
        }

        // Morph logo tại t=80ms, duration .74s (khớp HTML gsap.to(movingLogo, {duration:.74}, .08))
        try? await Task.sleep(nanoseconds: 80_000_000)
        withAnimation(.easeInOut(duration: 0.74)) {
            isMorphing = true
        }

        // Sau khi morph xong (t=80+740=820ms), đổi phase → form
        try? await Task.sleep(nanoseconds: 740_000_000)

        // Đổi phase + fade out status loading đồng thời
        loadingOpacity = 0
        phase = .ready

        // Brand title fade in
        withAnimation(.easeOut(duration: 0.28).delay(0)) {
            brandOpacity = 1
            brandOffset = 0
        }

        // Form cards stagger fade in (khớp HTML revealTargets stagger .065s, duration .5s)
        withAnimation(.easeOut(duration: 0.5).delay(0.13)) {
            formOpacity = 1
            formOffset = 0
        }
    }
}
