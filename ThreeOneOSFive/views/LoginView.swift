import SwiftUI

struct LoginView: View {
    @ObservedObject var auth: AuthManager

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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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

                    instructionCard

                    Spacer().frame(height: 16)

                    adminContactCard

                    Spacer().frame(height: 12)

                    zaloGroupBox(
                        title: "BOX 1 - NovaX",
                        subtitle: "Tham gia box 1 de nhan key va ho tro",
                        url: "https://zalo.me/g/i1bffsvvb6wijb3l0gc8",
                        icon: "1.circle.fill"
                    )

                    Spacer().frame(height: 12)

                    zaloGroupBox(
                        title: "BOX 2 - NovaX",
                        subtitle: "Tham gia box 2 de nhan key va ho tro",
                        url: "https://zalo.me/g/wbsfu5a3mcp4uodtebft",
                        icon: "2.circle.fill"
                    )

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 24)
            }
            .opacity(cardOpacity)
        }
        .onAppear {
            startEntryAnimation()
        }
    }

    // MARK: - Grid Background

    private var gridBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.02, blue: 0.06),
                    Color(red: 0.04, green: 0.04, blue: 0.10),
                    Color(red: 0.02, green: 0.02, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

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

            Text("KHAI PHA HET QUYEN")
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
                    Text("KICH HOAT HE THONG")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.accent)
                    Text("Nhap license key de bat dau")
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
                Text("MA KICH HOAT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .tracking(1)

                HStack(spacing: 10) {
                    if showKey {
                        TextField("Nhap license key", text: $auth.licenseKey)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    } else {
                        SecureField("Nhap license key", text: $auth.licenseKey)
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
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.15), lineWidth: 1)
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
                        Text("XAC THUC NGAY")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                    }
                    .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: auth.licenseKey.trimmingCharacters(in: .whitespaces).isEmpty
                        ? [AppTheme.accent.opacity(0.3), AppTheme.accent.opacity(0.15)]
                        : [AppTheme.accent, AppTheme.accentLight],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        auth.licenseKey.trimmingCharacters(in: .whitespaces).isEmpty
                            ? AppTheme.accent.opacity(0.2)
                            : AppTheme.accent.opacity(0.5),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: auth.licenseKey.trimmingCharacters(in: .whitespaces).isEmpty
                    ? .clear
                    : AppTheme.accent.opacity(0.3),
                radius: 12, y: 4
            )
        }
        .disabled(auth.licenseKey.trimmingCharacters(in: .whitespaces).isEmpty)
        .offset(y: cardOffset)
        .opacity(cardOpacity)
    }

    // MARK: - Instruction Card

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.accent.opacity(0.7))
                Text("HUONG DAN KICH HOAT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.accent.opacity(0.7))
                    .tracking(1)
            }

            instructionRow("01", "Mua KEY tai nguoi ban uy tin")
            instructionRow("02", "Sao chep ma KEY vao o ben tren")
            instructionRow("03", "Nhan XAC THUC NGAY de kich hoat")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.accent.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.1), lineWidth: 0.5)
                )
        )
        .offset(y: cardOffset)
        .opacity(cardOpacity)
    }

    private func instructionRow(_ num: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(num)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundColor(AppTheme.accent)
                .frame(width: 22, height: 22)
                .background(AppTheme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
        }
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
                    Text("NHA PHAT TRIEN")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.accent)
                        .tracking(1)
                    Text("Lien he ho tro truc tiep")
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
                    Text("Tran Minh Khai")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.95))
                    Text("Nha phat trien NovaX")
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

                Button(action: {
                    Haptics.light()
                    UIPasteboard.general.string = "0342145707"
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.accent)
                        .frame(width: 32, height: 32)
                        .background(AppTheme.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.vertical, 2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.15), lineWidth: 0.5)
                )
        )
        .offset(y: cardOffset)
        .opacity(cardOpacity)
    }

    // MARK: - Zalo Group Card

    private func zaloGroupBox(title: String, subtitle: String, url: String, icon: String) -> some View {
        Button(action: {
            Haptics.medium()
            if let link = URL(string: url) {
                UIApplication.shared.open(link)
            }
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x0068FF).opacity(0.3), Color(hex: 0x0068FF).opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle().stroke(Color(hex: 0x0068FF).opacity(0.4), lineWidth: 1)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: 0x0068FF))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("Tham gia")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: 0x0068FF))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: 0x0068FF))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(hex: 0x0068FF).opacity(0.12))
                .clipShape(Capsule())
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(hex: 0x0068FF).opacity(0.12), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
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
