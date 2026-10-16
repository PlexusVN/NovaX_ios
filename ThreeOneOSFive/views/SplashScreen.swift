import SwiftUI

/// SplashScreen - Phiên bản 2026 doanh nghiệp:
/// - Nền trắng, không vòng tròn neon, không spinner mặc định.
/// - Logo NovaX-Logo-new.png ở giữa; sheen ánh sáng quét ngang.
/// - Progress bar đơn sắc (đen) với curve professionalLoad.
/// - Status text xoay vòng: "Đang khởi tạo" → ... → "Sẵn sàng".
/// - Khi xong, logo morph sang vị trí logo đăng nhập (matchedGeometryEffect ở App scope).
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

    private let statusSteps = [
        "Đang khởi tạo",
        "Đang chuẩn bị không gian làm việc",
        "Sẵn sàng"
    ]

    // Tổng thời gian loading mục tiêu ~1.3s, đủ để người dùng thấy nhưng không chậm.
    private let statusInterval: Double = 0.45

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

    private var logoSection: some View {
        VStack(spacing: 24) {
            ZStack {
                AppLogo(size: 112)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 29, style: .continuous)
                            .stroke(Color.black.opacity(0.13), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.16), radius: 22, x: 0, y: 12)
                    .matchedGeometryEffect(id: SplashGeometryNamespace.logo, in: splashNamespace)
                    .overlay(logoSheenOverlay)
            }

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

    private var splashNamespace: Namespace.ID { appNamespace }

    /// Namespace sẽ được truyền từ App.swift để morph sang LoginView cùng ID.
    /// SplashScreen nhận thông qua một hằng số wrapper để chia sẻ giữa 2 view.
    /// Trong trường hợp chưa được cung cấp, fallback về namespace cục bộ.
    private func startAnimation() {
        // Logo appear
        withAnimation(.spring(response: 0.65, dampingFraction: 0.85)) {
            logoOpacity = 1
            logoScale = 1
            identityOpacity = 1
        }
        logoAppeared = true

        // Identity + loading fade in chậm
        withAnimation(.easeOut(duration: 0.55).delay(0.28)) {
            identityOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.48)) {
            loadingOpacity = 1
        }

        // Progress bar với curve cubic giống professionalLoad của preview
        withAnimation(.easeInOut(duration: 1.2).delay(0.10)) {
            progress = 1
        }

        // Status text xoay vòng
        if MotionPreference.isReduced {
            // Reduce motion: show only final state
            statusText = statusSteps.last ?? "Sẵn sàng"
            scheduleCompletion(after: 1.0)
        } else {
            statusText = statusSteps.first ?? "Đang khởi tạo"
            scheduleNextStatus()
            scheduleCompletion(after: 1.3)
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
