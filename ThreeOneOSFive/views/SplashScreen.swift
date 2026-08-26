import SwiftUI

struct SplashScreen: View {
    var onComplete: () -> Void

    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var lineWidth: CGFloat = 0
    @State private var statusText: String = ""
    @State private var statusOpacity: Double = 0
    @State private var ringRotation: Double = 0
    @State private var particleOpacity: Double = 0
    @State private var didComplete = false

    private let loadingSteps = [
        "Khởi tạo hệ thống",
        "Kết nối sandbox",
        "Quét ứng dụng",
        "Xác thực quyền truy cập",
        "Sẵn sàng"
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                logoSection

                Spacer()

                loadingSection
                    .padding(.bottom, 80)
            }

            particleLayer
        }
        .onAppear {
            startAnimation()
        }
    }

    private var logoSection: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .stroke(
                    AppTheme.accent.opacity(0.3),
                    lineWidth: 1.5
                )
                .frame(width: 140, height: 140)
                .opacity(glowOpacity)
                .rotationEffect(.degrees(ringRotation))

            // Inner glow ring
            Circle()
                .stroke(
                    AppTheme.accent.opacity(0.15),
                    lineWidth: 24
                )
                .frame(width: 140, height: 140)
                .blur(radius: 20)
                .opacity(glowOpacity)

            // Dashed orbit ring
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 8]))
                .frame(width: 160, height: 160)
                .opacity(glowOpacity * 0.6)
                .rotationEffect(.degrees(-ringRotation * 0.7))

            // Logo container
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.accent.opacity(0.18),
                                AppTheme.accent.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(AppTheme.accent.opacity(0.35), lineWidth: 1)
                    )

                if let icon = UIImage(named: "AppIcon60x60")
                    ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
                    ?? UIImage(named: "AppIcon") {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)
        }
    }

    private var loadingSection: some View {
        VStack(spacing: 16) {
            // App name
            Text("NovaX")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .opacity(logoOpacity)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accent, AppTheme.accent.opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: lineWidth, height: 3)
                        .shadow(color: AppTheme.accent.opacity(0.6), radius: 6)
                }
            }
            .frame(width: 200)
            .frame(height: 3)

            // Status text
            Text(statusText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.accent.opacity(0.8))
                .opacity(statusOpacity)
                .animation(.easeInOut(duration: 0.3), value: statusText)
        }
    }

    private var particleLayer: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2 - 40)

            ForEach(0..<12, id: \.self) { i in
                let angle = Double(i) * (360.0 / 12.0)
                let radius: Double = 95
                let x = center.x + CGFloat(cos(angle * .pi / 180) * radius)
                let y = center.y + CGFloat(sin(angle * .pi / 180) * radius)

                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 2, height: 2)
                    .position(x: x, y: y)
                    .opacity(particleOpacity * (0.3 + 0.7 * Double(i % 3 == 0 ? 1 : 0.3)))
            }
        }
        .ignoresSafeArea()
    }

    private func startAnimation() {
        let totalDuration: Double = 2.8

        withAnimation(.easeOut(duration: 0.8)) {
            logoScale = 1.0
            logoOpacity = 1.0
            glowOpacity = 1.0
            particleOpacity = 1.0
        }

        withAnimation(.linear(duration: totalDuration * 2).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }

        let stepDuration = totalDuration / Double(loadingSteps.count)

        for (index, step) in loadingSteps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(index)) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    statusText = step
                    statusOpacity = 1.0
                    lineWidth = CGFloat(index + 1) / CGFloat(loadingSteps.count) * 200
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.3) {
            if !didComplete {
                didComplete = true
                onComplete()
            }
        }
    }
}
