import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum AppTheme {
    static let accent = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.55, blue: 1.00, alpha: 1.00)
                : UIColor(red: 0.05, green: 0.35, blue: 0.85, alpha: 1.00)
        }
    )
    static let accentLight = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.15, green: 0.60, blue: 1.00, alpha: 1.00)
                : UIColor(red: 0.10, green: 0.45, blue: 0.90, alpha: 1.00)
        }
    )
    static let pageBackground = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.00)
                : .systemBackground
        }
    )
    static let consoleBackground = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.00)
                : .secondarySystemBackground
        }
    )
    static let pageInset: CGFloat = 16
    static let rowIconSize: CGFloat = 17
    static let rowIconFrame: CGFloat = 28
    static let fileRowIconSize: CGFloat = 17
    static let fileRowIconFrame: CGFloat = 30
    static let fileRowHeight: CGFloat = 60
    static let appIconSize: CGFloat = 32
    static let emptyIconSize: CGFloat = 30
    static let selectionIconSize: CGFloat = 18
}

struct AppRowIcon: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    var symbolSize: CGFloat = AppTheme.rowIconSize
    var frameSize: CGFloat = AppTheme.rowIconFrame

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.12))
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: frameSize, height: frameSize)
        .accessibilityHidden(true)
    }
}

struct AppSearchField: View {
    @Binding var text: String
    let prompt: String
    let clearLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(prompt, text: $text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 36)
        .background(
            Color(uiColor: .secondarySystemFill),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, AppTheme.pageInset)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct AppLogo: View {
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let icon = UIImage(named: "AppIcon60x60")
                ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
                ?? UIImage(named: "AppIcon") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "bolt.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

// MARK: - VisionOS Upgrades

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct MeshBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()
            
            // Glowing Orbs
            Circle()
                .fill(AppTheme.accent.opacity(0.15))
                .blur(radius: 80)
                .frame(width: 300, height: 300)
                .offset(x: animate ? 100 : -50, y: animate ? -100 : 50)
            
            Circle()
                .fill(Color(hex: 0x8A2BE2).opacity(0.15))
                .blur(radius: 90)
                .frame(width: 350, height: 350)
                .offset(x: animate ? -120 : 80, y: animate ? 150 : -80)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
        .ignoresSafeArea()
    }
}


struct ToastInfo: Equatable {
    var title: String
    var message: String
    var isSuccess: Bool
}

struct GlassToastModifier: ViewModifier {
    @Binding var toast: ToastInfo?
    
    func body(content: Content) -> some View {
        content.overlay(
            ZStack {
                if let t = toast {
                    VStack {
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Image(systemName: t.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(t.isSuccess ? .green : .red)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                Text(t.message)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            Spacer()
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
                                                colors: [Color.white.opacity(0.3), Color.white.opacity(0.05)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    if self.toast == t {
                                        self.toast = nil
                                    }
                                }
                            }
                        }
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                toast = nil
                            }
                        }
                    }
                    .zIndex(100)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: toast != nil)
        )
    }
}

extension View {
    func glassToast(toast: Binding<ToastInfo?>) -> some View {
        self.modifier(GlassToastModifier(toast: toast))
    }
}

