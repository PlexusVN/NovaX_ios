import SwiftUI

/// SplashScreen - Phiên bản 2026 doanh nghiệp:
/// - Nền trắng, không vòng tròn neon, không spinner mặc định.
/// - Logo NovaX-Logo-new.png ở giữa; sheen ánh sáng quét ngang.
/// - Progress bar đơn sắc (đen).
/// - Status text xoay vòng: "Đang khởi tạo" → ... → "Sẵn sàng".
struct SplashScreen: View {
    var onComplete: () -> Void
    @State private var logoAppeared = false
    @State private var logoScale: CGFloat = 0.9
    @State private var logoOpacity: Double = 0.0
    @State private var identityOpacity: Double = 0
    @State private var loadingOpacity: Double = 0
    @State private var progress: CGFloat = 0
    @State private var statusText: String = ""
    @State private var statusIndex: Int = 0
    @State private var ringDidTrigger = false
    @State private var didComplete = false

    /// Phase 1: logo bắt đầu morph từ splash → login (trượt lên + thu nhỏ)
    @State private var isMorphing: Bool = false
    /// Phase 2: morph xong, splash sắp biến mất
    @State private var splashDisappearing: Bool = false

    private let statusSteps = [
        "Đang khởi tạo",
        "Đang chuẩn bị không gian làm việc",
        "Sẵn sàng"
    ]

    // Tổng thời gian loading mục tiêu ~2.0s, đủ để người dùng thấy từng bước khởi tạo.
    private let statusInterval: Double = 0.65

    var body: some View {
        ZStack {
            SplashBackdrop()

            VStack(spacing: 0) {
                Spacer().frame(height: 220)

                logoSection
                    .opacity(loadingOpacity)
                    .scaleEffect(logoScale)

                Spacer()

                loadingSection
                    .padding(.bottom, 80)
            }

            // Sheen trượt ngang trên logo
            if logoAppeared {
                Color.clear
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    // MARK: - Logo

    /// Morph offset: khoảng cách logo cần trượt từ vị trí splash → vị trí login.
    /// Splash: logo ở giữa (220pt từ top). Login: logo ở 56pt từ top → trượt lên -164pt.
    private let morphYOffset: CGFloat = -164
    /// Scale từ 112 → 92
    private let morphScale: CGFloat = 92.0 / 112.0

    /// Tạo Image logo có thể resize theo size tùy ý (dùng cho morph).
    /// AppLogo mặc định có .clipShape cứng bên trong nên không morph được,
    /// nên ta tự tạo Image thuần để outer scale/offset control hoàn toàn.
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
        } else {
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(AppTheme.ink)
        }
    }

    private var logoSection: some View {
        VStack(spacing: 24) {
            // Cả "cái ô" logo (ảnh + background + borderRadius + shadow) morph cùng nhau.
            // Dùng Image thuần resizable, KHÔNG có clipShape cứng bên trong.
            // Outer: clipShape + overlay + shadow + offset + scaleEffect control hoàn toàn.
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
                // Morph toàn bộ ô: trượt lên + thu nhỏ
                .offset(y: isMorphing ? morphYOffset : 0)
                .scaleEffect(isMorphing ? morphScale : 1.0)
                .opacity(loadingOpacity)

            VStack(spacing: 10) {
                Text("NovaX")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .kerning(-1.35)
                Text("KHAI PHÁ HỆ THỐNG")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(AppTheme.grey500)
                    .tracking(2.25)
            }
            .multilineTextAlignment(.center)
            .opacity(identityOpacity)
        }
    }

    /// Sheen ánh sáng quét ngang (1 lần, auto-stop)
    @ViewBuilder
    private var logoSheenOverlay: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                if !MotionPreference.isReduced {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .white.opacity(0.65), location: 0.5),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: w * 0.5, height: h * 1.6)
                    .rotationEffect(.degrees(8))
                    .offset(x: -w * 1.6)
                    .blendMode(.plusLighter)
                    .modifier(SheenOnceModifier())
                }
            }
        }
        .mask(AppLogo(size: 112))
        .allowsHitTesting(false)
    }

    // MARK: - Loading section

    private var loadingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressBar(progress: progress)
                .frame(height: 2)

            HStack(spacing: 8) {
                Circle()
                    .fill(AppTheme.ink)
                    .frame(width: 5, height: 5)
                    .modifier(StatusPulseModifier())

                Text(statusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.grey700)
                    .animation(.easeInOut(duration: 0.25), value: statusText)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 210)
    }

    // MARK: - Animation

    private func startAnimation() {
        // Logo appear
        withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
            logoOpacity = 1
            logoScale = 1
            identityOpacity = 1
        }
        logoAppeared = true

        // Identity + loading fade in chậm
        withAnimation(.easeOut(duration: 0.6).delay(0.32)) {
            identityOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.55)) {
            loadingOpacity = 1
        }

        // Progress bar với curve cubic, chạy trong ~1.9s để hoàn thành cùng lúc với status cuối
        withAnimation(.easeInOut(duration: 1.85).delay(0.10)) {
            progress = 1
        }

        // Status text xoay vòng
        if MotionPreference.isReduced {
            // Reduce motion: show only final state
            statusText = statusSteps.last ?? "Sẵn sàng"
            scheduleCompletion(after: 2.0)
        } else {
            statusText = statusSteps.first ?? "Đang khởi tạo"
            scheduleNextStatus()
            scheduleCompletion(after: 2.0)
        }
    }

    private func scheduleNextStatus() {
        Task { @MainActor in
            for i in 1..<statusSteps.count {
                try? await Task.sleep(nanoseconds: UInt64(statusInterval * 1_000_000_000))
                guard !didComplete else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    statusText = statusSteps[i]
                    statusIndex = i
                }
            }
        }
    }

    private func scheduleCompletion(after seconds: Double) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !didComplete else { return }
            didComplete = true

            // Bước 1: fade out identity để chỉ còn logo NovaX
            withAnimation(.easeOut(duration: 0.22)) {
                identityOpacity = 0
            }

            // Bước 2: morph logo — trượt lên + thu nhỏ + bo góc (khớp HTML: t=80ms, dur=.74s)
            try? await Task.sleep(nanoseconds: 80_000_000)
            withAnimation(.easeInOut(duration: 0.74)) {
                isMorphing = true
            }

            // Bước 3: morph hoàn tất tại t=80+740=820ms → gọi onComplete
            // Splash sẽ fade out (0.55s) → Login hiện ra → logo bounce (0.28s)
            try? await Task.sleep(nanoseconds: 740_000_000)
            onComplete()
        }
    }
}

// MARK: - Progress Bar

private struct ProgressBar: View {
    let progress: CGFloat
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(AppTheme.grey100)
                    .frame(height: 2)
                RoundedRectangle(cornerRadius: 1)
                    .fill(AppTheme.ink)
                    .frame(width: proxy.size.width * progress, height: 2)
            }
        }
        .frame(height: 2)
    }
}

// MARK: - Sheen modifier (chạy 1 lần)

private struct SheenOnceModifier: ViewModifier {
    @State private var animate = false
    func body(content: Content) -> some View {
        content
            .offset(x: animate ? 600 : -180)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.15).delay(0.25)) {
                    animate = true
                }
            }
    }
}

// MARK: - Status pulse

private struct StatusPulseModifier: ViewModifier {
    @State private var pulse = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(pulse ? 1.0 : 0.82)
            .opacity(pulse ? 1.0 : 0.28)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
