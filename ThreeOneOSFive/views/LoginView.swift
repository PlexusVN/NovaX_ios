import SwiftUI

struct LoginView: View {
    @ObservedObject var auth: AuthManager
    @EnvironmentObject var appState: AppState

    @State private var showKey: Bool = false
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var cardOpacity: Double = 0
    @State private var cardOffset: CGFloat = 30
    @State private var ringRotation: Double = 0
    @State private var particleOpacity: Double = 0
    @State private var scanLineOffset: CGFloat = -200
    @State private var pulseScale: CGFloat = 1.0
    @State private var gridOpacity: Double = 0
    @State private var showCommunityAlert: Bool = false

    var body: some View {
        ZStack {
            MeshBackground()

            gridBackground

            scanLineEffect

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 50)

                    logoSection

                    Spacer().frame(height: 12)

                    titleSection

                    Spacer().frame(height: 36)

                    inputCardSection

                    if case .error(let msg) = auth.authState {
                        errorSection(msg)
                    }

                    activateButton

                    Spacer().frame(height: 20)

                    osSupportCard

                    Spacer().frame(height: 16)

                    adminContactCard

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 24)
            }
            .opacity(cardOpacity)
        }
        .onAppear {
            startEntryAnimation()
        }
        .overlay {
            if showCommunityAlert {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showCommunityAlert = false
                            }
                        }
                    
                    customCommunityAlert
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
                .zIndex(100)
            }
        }
    }

    private var customCommunityAlert: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 28))
                    .foregroundColor(AppTheme.accent)
                    .padding(.top, 8)
                
                Text("Tham gia cộng đồng")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Vui lòng chọn nhóm Zalo bạn muốn tham gia để nhận key và hỗ trợ.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.vertical, 20)
            
            Divider().background(Color.white.opacity(0.1))
            
            // Buttons
            VStack(spacing: 12) {
                Button {
                    Haptics.light()
                    if let url = URL(string: "https://zalo.me/g/i1bffsvvb6wijb3l0gc8") {
                        UIApplication.shared.open(url)
                    }
                    withAnimation { showCommunityAlert = false }
                } label: {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("BOX 1 - NovaX")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(PremiumButtonStyle(color: Color(red: 0/255, green: 104/255, blue: 255/255)))
                
                Button {
                    Haptics.light()
                    if let url = URL(string: "https://zalo.me/g/wbsfu5a3mcp4uodtebft") {
                        UIApplication.shared.open(url)
                    }
                    withAnimation { showCommunityAlert = false }
                } label: {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("BOX 2 - NovaX")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(PremiumButtonStyle(color: Color(red: 0/255, green: 104/255, blue: 255/255)))
            }
            .padding(16)
            
            Divider().background(Color.white.opacity(0.1))
            
            Button {
                Haptics.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showCommunityAlert = false
                }
            } label: {
                Text("Đóng")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(PremiumButtonStyle(color: Color.white.opacity(0.15), cornerRadius: 12))
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .systemBackground).opacity(0.1))
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.2), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 20)
        .padding(.horizontal, 32)
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Grid Background

    private var gridBackground: some View {
        ZStack {

            GeometryReader { geo in
                let spacing: CGFloat = 40
                // Vertical lines
                ForEach(0..<Int(geo.size.width / spacing) + 1, id: \.self) { i in
                    let x = CGFloat(i) * spacing
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    .stroke(AppTheme.accent.opacity(0.06), lineWidth: 0.5)
                }
                // Horizontal lines
                ForEach(0..<Int(geo.size.height / spacing) + 1, id: \.self) { i in
                    let y = CGFloat(i) * spacing
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(AppTheme.accent.opacity(0.06), lineWidth: 0.5)
                }
            }
            .opacity(gridOpacity)

            // Corner accents
            VStack {
                HStack {
                    cornerAccent(alignment: .topLeading)
                    Spacer()
                    cornerAccent(alignment: .topTrailing)
                }
                Spacer()
                HStack {
                    cornerAccent(alignment: .bottomLeading)
                    Spacer()
                    cornerAccent(alignment: .bottomTrailing)
                }
            }
            .padding(12)
            .opacity(gridOpacity * 0.8)
        }
    }

    private func cornerAccent(alignment: Alignment) -> some View {
        ZStack {
            if alignment == .topLeading || alignment == .bottomTrailing {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 20))
                    p.addLine(to: CGPoint(x: 0, y: 0))
                    p.addLine(to: CGPoint(x: 20, y: 0))
                }
                .stroke(AppTheme.accent.opacity(0.5), lineWidth: 1.5)
            } else {
                Path { p in
                    p.move(to: CGPoint(x: 20, y: 0))
                    p.addLine(to: CGPoint(x: 0, y: 0))
                    p.addLine(to: CGPoint(x: 0, y: 20))
                }
                .stroke(AppTheme.accent.opacity(0.5), lineWidth: 1.5)
            }
        }
        .frame(width: 20, height: 20)
    }

    // MARK: - Scan Line Effect

    private var scanLineEffect: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.accent.opacity(0),
                            AppTheme.accent.opacity(0.08),
                            AppTheme.accent.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 120)
                .offset(y: scanLineOffset)
                .onAppear {
                    withAnimation(
                        .linear(duration: 4.0)
                        .repeatForever(autoreverses: false)
                    ) {
                        scanLineOffset = geo.size.height + 200
                    }
                }
        }
        .ignoresSafeArea()
    }

    // MARK: - Logo Section

    private var logoSection: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                .frame(width: 130, height: 130)
                .opacity(glowOpacity)
                .rotationEffect(.degrees(ringRotation))

            // Inner glow blur
            Circle()
                .stroke(AppTheme.accent.opacity(0.15), lineWidth: 20)
                .frame(width: 130, height: 130)
                .blur(radius: 20)
                .opacity(glowOpacity)

            // Dashed orbit
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 8]))
                .frame(width: 150, height: 150)
                .opacity(glowOpacity * 0.5)
                .rotationEffect(.degrees(-ringRotation * 0.7))

            // Logo container
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.accent.opacity(0.2),
                                AppTheme.accent.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(AppTheme.accent.opacity(0.4), lineWidth: 1.5)
                    )

                if let icon = UIImage(named: "AppIcon60x60")
                    ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
                    ?? UIImage(named: "AppIcon") {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .scaleEffect(logoScale * pulseScale)
            .opacity(logoOpacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    pulseScale = 1.05
                }
            }

            // Particles
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * (360.0 / 8.0)
                let radius: Double = 88
                let x = cos(angle * .pi / 180) * radius
                let y = sin(angle * .pi / 180) * radius

                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 2, height: 2)
                    .offset(x: x, y: y)
                    .opacity(particleOpacity * (Double(i % 2 == 0 ? 1 : 0.4)))
            }
        }
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(spacing: 8) {
            Text("NovaX")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.accent, AppTheme.accentLight],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: AppTheme.accent.opacity(0.5), radius: 8)

            Text("KHAI PHÁ HỆ THỐNG")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.accent.opacity(0.7))
                .tracking(3)

            HStack(spacing: 4) {
                Rectangle().frame(width: 24, height: 1).foregroundColor(AppTheme.accent.opacity(0.4))
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundColor(AppTheme.accent.opacity(0.6))
                Rectangle().frame(width: 24, height: 1).foregroundColor(AppTheme.accent.opacity(0.4))
            }
        }
        .opacity(logoOpacity)
    }

    // MARK: - Input Card

    private var inputCardSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "key.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("KÍCH HOẠT HỆ THỐNG")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.accent)
                    Text("Nhập license key để bắt đầu")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(auth.authState == .verified ? Color.green : AppTheme.accent.opacity(0.5))
                        .frame(width: 6, height: 6)
                    Text(auth.authState == .verified ? "ON" : "OFF")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(auth.authState == .verified ? .green : .white.opacity(0.4))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
            }

            Divider().background(AppTheme.accent.opacity(0.2))

            // Key input
            VStack(alignment: .leading, spacing: 6) {
                Text("MÃ KÍCH HOẠT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .tracking(1)

                HStack(spacing: 10) {
                    if showKey {
                        TextField("Nhập license key", text: $auth.licenseKey)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    } else {
                        SecureField("Nhập license key", text: $auth.licenseKey)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    Button(action: { showKey.toggle() }) {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.accent.opacity(0.6))
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.2), lineWidth: 1)
                )
            }

            // HWID
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HWID")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                    Text(auth.hwid)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button(action: {
                    Haptics.light()
                    UIPasteboard.general.string = auth.hwid
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.accent)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemBackground).opacity(0.1))
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
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
        )
        .offset(y: cardOffset)
        .opacity(cardOpacity)
    }

    // MARK: - Error

    private func errorSection(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)
            Text(msg)
                .font(.system(size: 12))
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Activate Button

    private var activateButton: some View {
        Button(action: {
            Haptics.medium()
            Task { await auth.login() }
        }) {
            ZStack {
                if case .loading(let text) = auth.authState {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                        Text(text)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 15))
                        Text("XÁC THỰC NGAY")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                    }
                    .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(PremiumButtonStyle(
            color: auth.licenseKey.trimmingCharacters(in: .whitespaces).isEmpty
                ? AppTheme.accent.opacity(0.2)
                : AppTheme.accent,
            cornerRadius: 14
        ))
        .disabled(auth.licenseKey.trimmingCharacters(in: .whitespaces).isEmpty)
        .offset(y: cardOffset)
        .opacity(cardOpacity)
    }

    // MARK: - OS Support Card

    private var osSupportCard: some View {
        let isSupported = appState.isSupported
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "iphone")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.accent.opacity(0.7))
                Text("THÔNG TIN THIẾT BỊ")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.accent.opacity(0.7))
                    .tracking(1)
            }

            HStack {
                Text("Phiên bản iOS:")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("\(UIDevice.current.systemVersion)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            
            HStack {
                Text("Trạng thái hỗ trợ:")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text(appState.accessLevelDescription.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(isSupported ? .green : .red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemBackground).opacity(0.1))
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.white.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .offset(y: cardOffset)
        .opacity(cardOpacity)
    }

    // MARK: - Admin Contact Card

    private var adminContactCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "person.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("NHÀ PHÁT TRIỂN")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.accent)
                        .tracking(1)
                    Text("Liên hệ hỗ trợ trực tiếp")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                }
                Spacer()
            }

            Divider().background(AppTheme.accent.opacity(0.15))
                .padding(.vertical, 10)

            // Admin info
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accent.opacity(0.35), AppTheme.accent.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle().stroke(AppTheme.accent.opacity(0.4), lineWidth: 1.5)
                        )
                    Text("MK")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Trần Minh Khải")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.95))
                    Text("Nhà phát triển NovaX")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppTheme.accent.opacity(0.7))
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.accent.opacity(0.5))
                        Text("0342145707")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Spacer()
            }
            .padding(.vertical, 2)
            
            // Buttons
            HStack(spacing: 12) {
                Button(action: {
                    Haptics.light()
                    if let url = URL(string: "https://zalo.me/0342145707") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text("Liên hệ Zalo")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(PremiumButtonStyle(color: Color(hex: 0x0068FF), cornerRadius: 8))
                
                Button(action: {
                    Haptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showCommunityAlert = true
                    }
                }) {
                    HStack {
                        Image(systemName: "person.3.fill")
                        Text("Cộng đồng")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(PremiumButtonStyle(cornerRadius: 8))
            }
            .padding(.top, 12)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .systemBackground).opacity(0.1))
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.white.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .offset(y: cardOffset)
        .opacity(cardOpacity)
    }

    // MARK: - Animation

    private func startEntryAnimation() {
        withAnimation(.easeOut(duration: 0.8)) {
            logoScale = 1.0
            logoOpacity = 1.0
            glowOpacity = 1.0
            particleOpacity = 1.0
            gridOpacity = 1.0
        }

        withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
            cardOpacity = 1.0
            cardOffset = 0
        }

        withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }
    }
}
