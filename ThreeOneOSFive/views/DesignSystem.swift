import SwiftUI
import UIKit

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
    // MARK: - Cyberpunk Gaming Palette (Option 1)
    static let cyberCyan = Color(hex: 0x00E5FF)       // Electric Ice Cyan
    static let cyberBlue = Color(hex: 0x007BFF)       // Deep Tech Blue
    static let cyberPurple = Color(hex: 0x9D4EDD)     // Neon Ultraviolet
    static let cyberViolet = Color(hex: 0x7928CA)     // Deep Cyber Violet
    static let cyberPink = Color(hex: 0xFF007F)       // Neon Hot Pink
    static let cyberGreen = Color(hex: 0x00F5A0)      // Neon Emerald Green
    static let cyberOLED = Color(hex: 0x06080D)       // Deep OLED Space Black
    static let cyberSurface = Color(hex: 0x0D111C)    // Elevated Cyber Glass Surface

    static let cyberGradient = LinearGradient(
        colors: [cyberCyan, cyberPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let cyberBorderGradient = LinearGradient(
        colors: [cyberCyan.opacity(0.8), cyberPurple.opacity(0.35)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cyberSubtleBorder = LinearGradient(
        colors: [Color.white.opacity(0.12), Color.white.opacity(0.02)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accent = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.00, green: 0.85, blue: 1.00, alpha: 1.00) // Electric Cyan
                : UIColor(red: 0.00, green: 0.45, blue: 0.95, alpha: 1.00)
        }
    )
    static let accentLight = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.35, green: 0.90, blue: 1.00, alpha: 1.00)
                : UIColor(red: 0.10, green: 0.55, blue: 1.00, alpha: 1.00)
        }
    )
    static let pageBackground = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1.00) // Deep OLED
                : .systemBackground
        }
    )
    static let consoleBackground = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1.00)
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

struct PremiumButtonStyle: ButtonStyle {
    var color: Color = AppTheme.accent
    var cornerRadius: CGFloat = 12
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                LinearGradient(
                    colors: [color.opacity(0.8), color.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(Color.black.opacity(0.2)) // Base layer
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: color.opacity(configuration.isPressed ? 0.1 : 0.3), radius: configuration.isPressed ? 5 : 12, y: configuration.isPressed ? 2 : 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct CyberGlowButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12
    var isEnabled: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(AppTheme.cyberGradient)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.4), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: AppTheme.cyberCyan.opacity(configuration.isPressed ? 0.2 : 0.45),
                radius: configuration.isPressed ? 6 : 14,
                y: configuration.isPressed ? 2 : 6
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1.0) : 0.5)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct MeshBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()
            
            // Glowing Cyber Orbs (Electric Ice Cyan & Neon Violet)
            Circle()
                .fill(AppTheme.cyberCyan.opacity(0.14))
                .blur(radius: 85)
                .frame(width: 320, height: 320)
                .offset(x: animate ? 120 : -60, y: animate ? -120 : 60)
            
            Circle()
                .fill(AppTheme.cyberPurple.opacity(0.16))
                .blur(radius: 95)
                .frame(width: 360, height: 360)
                .offset(x: animate ? -140 : 90, y: animate ? 160 : -90)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
        .ignoresSafeArea()
    }
}


struct ToastInfo: Equatable, Identifiable {
    var id = UUID()
    var title: String
    var message: String
    var isSuccess: Bool
}

struct GlassToastModifier: ViewModifier {
    @Binding var toast: ToastInfo?
    @State private var dragOffset: CGFloat = 0
    
    func body(content: Content) -> some View {
        content.overlay(
            ZStack {
                if let t = toast {
                    VStack {
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
                                                colors: [
                                                    (t.isSuccess ? Color.green : Color.red).opacity(0.8),
                                                    (t.isSuccess ? Color.green : Color.red).opacity(0.1)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                        )
                        .shadow(color: (t.isSuccess ? Color.green : Color.red).opacity(0.4), radius: 25, y: 15)
                        .padding(.horizontal, 24)
                        .padding(.top, 60)
                        .offset(y: dragOffset < 0 ? dragOffset : 0)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if value.translation.height < 0 {
                                        dragOffset = value.translation.height
                                    }
                                }
                                .onEnded { value in
                                    if value.translation.height < -20 {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                            toast = nil
                                        }
                                    }
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        dragOffset = 0
                                    }
                                }
                        )
                        .transition(.move(edge: .top))
                        .id(t.id)
                        
                        Spacer()
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    if self.toast?.id == t.id {
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
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: toast?.id)
        )
    }
}

extension View {
    func glassToast(toast: Binding<ToastInfo?>) -> some View {
        self.modifier(GlassToastModifier(toast: toast))
    }
}

// MARK: - Haptics

enum Haptics {
    static func light() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.impactOccurred()
    }

    static func medium() {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.impactOccurred()
    }

    static func heavy() {
        let g = UIImpactFeedbackGenerator(style: .heavy)
        g.impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

