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

// MARK: - 2026 Enterprise Monochrome Theme
// Theo design.md: Trắng đen, tối giản, doanh nghiệp 2026.
// Nền trắng, chữ/icon/viền là đen hoặc thang xám.

enum AppTheme {
    // MARK: Monochrome palette
    static let ink          = Color(hex: 0x38BDF8) // shared accent & primary action
    static let inkSecondary = Color(hex: 0x0B1628)
    static let paper        = Color(hex: 0x030712)
    static let paperMuted   = Color(hex: 0x071122)
    static let paperRaised  = Color(hex: 0x0B1628)
    static let grey900      = Color(hex: 0xF4F8FF)
    static let grey700      = Color(hex: 0xD6E5FF)
    static let grey600      = Color(hex: 0xB6C6DF)
    static let grey500      = Color(hex: 0x91A4C0)
    static let grey400      = Color(hex: 0x7185A3)
    static let grey300      = Color(hex: 0x315078)
    static let grey200      = Color(hex: 0x1E3A5F)
    static let grey100      = Color(hex: 0x12243F)
    static let grey50       = Color(hex: 0x0B1628)

    // Semantic status palette: chỉ dùng để truyền đạt trạng thái.
    static let statusSuccess = Color(hex: 0x22C55E)
    static let statusInfo    = Color(hex: 0x38BDF8)
    static let statusWarning = Color(hex: 0xF59E0B)
    static let statusError   = Color(hex: 0xFB7185)

    static let positive     = statusSuccess
    static let negative     = statusError

    // MARK: Borders
    static let borderHairline = Color(hex: 0x1E3A5F)
    static let borderStrong   = Color(hex: 0x38BDF8)

    // MARK: Spacings / sizes
    static let pageInset: CGFloat = 16
    static let rowIconSize: CGFloat = 17
    static let rowIconFrame: CGFloat = 28
    static let fileRowIconSize: CGFloat = 17
    static let fileRowIconFrame: CGFloat = 30
    static let fileRowHeight: CGFloat = 60
    static let appIconSize: CGFloat = 32
    static let emptyIconSize: CGFloat = 30
    static let selectionIconSize: CGFloat = 18

    // Background helpers - light, paper-like
    static let pageBackground: Color = paper
    static let consoleBackground: Color = paperMuted

    /// Legacy colors kept for backward compatibility with existing helpers
    /// (AirLiftSettingsSection, PatchProjectEditorView, v.v.).
    /// Sử dụng `.ink` thay vì các giá trị này cho code mới.
    static let accent = ink
    static let accentLight = ink

    /// Aliases cho các tên cũ - trỏ về palette trắng-đen 2026
    static let cyberCyan  = Color(hex: 0x38BDF8)
    static let cyberBlue  = Color(hex: 0x147DFF)
    static let cyberPurple = Color(hex: 0x8B5CF6)
    static let cyberViolet = Color(hex: 0x6D5DFB)
    static let cyberPink   = Color(hex: 0xEC4899)
    static let cyberGreen  = Color(hex: 0x22C55E)
    static let cyberOLED   = paper
    static let cyberSurface = paperMuted

    static let cyberGradient = LinearGradient(
        colors: [cyberCyan, cyberViolet, cyberPink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let cyberBorderGradient = LinearGradient(
        colors: [cyberCyan.opacity(0.70), cyberViolet.opacity(0.48), cyberPink.opacity(0.34)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let cyberSubtleBorder = LinearGradient(
        colors: [cyberCyan.opacity(0.28), cyberPink.opacity(0.12)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Gaming blue / black palette
    // Kept separate from the legacy monochrome aliases so older screens and
    // transport diagnostics retain their existing contrast and behavior.
    static let gamingBackground = Color(hex: 0x030712)
    static let gamingBackgroundRaised = Color(hex: 0x071122)
    static let gamingSurface = Color(hex: 0x0B1628)
    static let gamingSurfaceRaised = Color(hex: 0x10213B)
    static let gamingBlue = Color(hex: 0x147DFF)
    static let gamingBlueBright = Color(hex: 0x38BDF8)
    static let gamingViolet = Color(hex: 0x5865F2)
    static let gamingPink = Color(hex: 0xEC4899)
    static let gamingText = Color(hex: 0xF4F8FF)
    static let gamingTextSecondary = Color(hex: 0x91A4C0)
    static let gamingBorder = Color(hex: 0x1E3A5F)

    static let gamingAccentGradient = LinearGradient(
        colors: [gamingBlueBright, gamingBlue, gamingViolet, gamingPink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let gamingBorderGradient = LinearGradient(
        colors: [gamingBlueBright.opacity(0.72), gamingViolet.opacity(0.48), gamingPink.opacity(0.30)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let gamingTabSpring = Animation.spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.12)

    // MARK: Surfaces / Materials
    /// Floating capsule material for tabbar (iOS 16-25 fallback)
    @ViewBuilder
    static func capsuleBar(tint: Color = ink) -> some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule().stroke(tint.opacity(0.16), lineWidth: 1)
            )
    }

    /// Card surface (white, border đen nhẹ, shadow mềm)
    @ViewBuilder
    static func cardSurface(cornerRadius: CGFloat = 22) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(paperRaised)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderHairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
    }

    /// Liquid Glass / iOS 16+ equivalent: ultraThinMaterial on capsule
    /// Khi build bằng Xcode 26+ với iOS 26 SDK, có thể kích hoạt glassEffect thật ở đây.
    static func liquidGlassCapsule<S: Shape>(shape: S, interactive: Bool = true) -> some View {
        shape.fill(.ultraThinMaterial)
            .overlay(
                shape.stroke(borderHairline, lineWidth: 1)
            )
    }
}

// MARK: - Gaming surfaces

struct GamingBackdrop: View {
    var body: some View {
        ZStack {
            AppTheme.gamingBackground

            RadialGradient(
                colors: [AppTheme.gamingBlue.opacity(0.22), Color.clear],
                center: .init(x: 0.12, y: 0.02),
                startRadius: 0,
                endRadius: 430
            )

            RadialGradient(
                colors: [AppTheme.gamingViolet.opacity(0.13), Color.clear],
                center: .init(x: 0.92, y: 0.42),
                startRadius: 0,
                endRadius: 360
            )

            RadialGradient(
                colors: [AppTheme.gamingPink.opacity(0.11), Color.clear],
                center: .init(x: 0.08, y: 0.82),
                startRadius: 0,
                endRadius: 330
            )

            LinearGradient(
                colors: [Color.white.opacity(0.025), Color.clear, AppTheme.gamingBlue.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct GamingPressButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.76), value: configuration.isPressed)
    }
}

// MARK: - Logo

struct AppLogo: View {
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let icon = UIImage(named: "NovaXLogo")
                ?? UIImage(named: "AppIcon60x60")
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
                    .background(AppTheme.ink)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

// MARK: - Reusable building blocks

struct AppRowIcon: View {
    let systemName: String
    var tint: Color = AppTheme.ink
    var symbolSize: CGFloat = AppTheme.rowIconSize
    var frameSize: CGFloat = AppTheme.rowIconFrame

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.08))
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
            AppTheme.grey50,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, AppTheme.pageInset)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Button styles

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// White card outline button (ghost)
struct OutlineButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 14
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(AppTheme.paperRaised)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.ink, lineWidth: 1)
            )
            .foregroundStyle(AppTheme.ink)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Gaming primary button (đồng bộ 100% với "XÁC THỰC NGAY" trong preview styles.css)
struct PrimaryButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 15
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: 0x147DFF),
                        Color(hex: 0x2563EB),
                        Color(hex: 0x5865F2),
                        Color(hex: 0xEC4899)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
            )
            .foregroundStyle(Color.white)
            .shadow(
                color: Color(hex: 0x147DFF).opacity(configuration.isPressed ? 0.20 : 0.38),
                radius: configuration.isPressed ? 6 : 12,
                y: configuration.isPressed ? 2 : 6
            )
            .shadow(
                color: Color(hex: 0xEC4899).opacity(configuration.isPressed ? 0.08 : 0.18),
                radius: configuration.isPressed ? 5 : 10,
                y: 0
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Legacy button styles preserved for backward compatibility
/// (AirLiftSettingsSection, PatchProjectEditorView, FilesTabControls v.v.)
/// Phiên bản đơn sắc trắng-đen theo design 2026.
struct PremiumButtonStyle: ButtonStyle {
    var color: Color = AppTheme.ink
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                LinearGradient(
                    colors: [color.opacity(0.95), color.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.08 : 0.16),
                    radius: configuration.isPressed ? 3 : 8, y: configuration.isPressed ? 1 : 4)
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
            .background(AppTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.08 : 0.16),
                radius: configuration.isPressed ? 3 : 10,
                y: configuration.isPressed ? 1 : 5
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1.0) : 0.4)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Disabled state (placeholder, vẫn giữ kích thước)
struct PrimaryButtonStyleDisabled: ButtonStyle {
    var cornerRadius: CGFloat = 15
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(AppTheme.grey200)
            .foregroundStyle(AppTheme.grey500)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Toast

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
                                .font(.system(size: 22))
                                .foregroundColor(t.isSuccess ? AppTheme.gamingBlueBright : AppTheme.statusError)
                                .shadow(
                                    color: (t.isSuccess ? AppTheme.gamingBlue : AppTheme.statusError).opacity(0.45),
                                    radius: 8
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(AppTheme.gamingText)
                                Text(t.message)
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.gamingTextSecondary)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppTheme.gamingSurface.opacity(0.93))
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    t.isSuccess
                                        ? AppTheme.gamingBorderGradient
                                        : LinearGradient(
                                            colors: [AppTheme.statusError.opacity(0.72), Color.white.opacity(0.08)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(
                            color: (t.isSuccess ? AppTheme.gamingBlue : AppTheme.statusError).opacity(0.22),
                            radius: 22,
                            y: 10
                        )
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
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
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
    static func light()  { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy()  { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func soft()   { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.72) }
    static func rigid()  { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.82) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success(){ UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning(){ UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error()  { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

// MARK: - Mesh backdrop (trắng, tĩnh)

struct MeshBackground: View {
    var body: some View {
        ZStack {
            AppTheme.gamingBackground.ignoresSafeArea()
            // Soft radial glow nhẹ để có "tầng" rất nhẹ
            RadialGradient(
                colors: [AppTheme.gamingBlue.opacity(0.18), AppTheme.gamingViolet.opacity(0.10), Color.clear],
                center: .init(x: 0.5, y: 0.15),
                startRadius: 0,
                endRadius: 600
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Backgrounds

/// SplashScreen specific: trắng, có sheen nhẹ dọc giữa (subtle)
struct SplashBackdrop: View {
    var body: some View {
        ZStack {
            GamingBackdrop()
            RadialGradient(
                colors: [AppTheme.gamingViolet.opacity(0.20), AppTheme.gamingPink.opacity(0.08), Color.clear],
                center: .init(x: 0.5, y: 0.4),
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()
            Rectangle()
                .fill(
                    LinearGradient(colors: [Color.clear, AppTheme.gamingBlueBright.opacity(0.22), Color.clear],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

struct AstraDeveloperContact: Identifiable {
    let id: String
    let name: String
    let initials: String
    let telegram: String
}

enum AstraDeveloperDirectory {
    static let contacts: [AstraDeveloperContact] = [
        AstraDeveloperContact(
            id: "minh-khai",
            name: "Minh Khải",
            initials: "MK",
            telegram: "@trnmnhkh"
        ),
        AstraDeveloperContact(
            id: "son-dev",
            name: "Sơn Dev",
            initials: "SD",
            telegram: "@Sondevv"
        )
    ]

    static func openTelegram(_ username: String) {
        let normalizedUsername = username.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard let appURL = URL(string: "tg://resolve?domain=\(normalizedUsername)"),
              let webURL = URL(string: "https://t.me/\(normalizedUsername)") else { return }

        UIApplication.shared.open(appURL, options: [:]) { opened in
            guard !opened else { return }
            DispatchQueue.main.async {
                UIApplication.shared.open(webURL)
            }
        }
    }

}

struct DeveloperContactsList: View {
    var body: some View {
        VStack(spacing: 15) {
            ForEach(Array(AstraDeveloperDirectory.contacts.enumerated()), id: \.element.id) { index, developer in
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: 0x147DFF), Color(hex: 0x6D5DFB)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                                .shadow(color: Color(hex: 0x147DFF).opacity(0.35), radius: 6, x: 0, y: 0)

                            Text(developer.initials)
                                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                                .foregroundStyle(Color.white)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(developer.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x38BDF8))
                            Text("Telegram: \(developer.telegram)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(hex: 0x91A4C0))
                        }
                        Spacer()
                    }

                    Button {
                        Haptics.light()
                        AstraDeveloperDirectory.openTelegram(developer.telegram)
                    } label: {
                        Label("Mở Telegram", systemImage: "paperplane.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: 0x147DFF), Color(hex: 0x5865F2), Color(hex: 0xEC4899)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                            .shadow(color: Color(hex: 0x147DFF).opacity(0.28), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(GamingPressButtonStyle(scale: 0.985))
                }

                if index < AstraDeveloperDirectory.contacts.count - 1 {
                    Rectangle()
                        .fill(Color(hex: 0x1E3A5F).opacity(0.8))
                        .frame(height: 1)
                }
            }
        }
    }
}

// MARK: - Geometry match helpers

/// Helper dùng chung cho logo morph: shared namespace constant
enum SplashGeometryNamespace {
    static let logo = "novax.splash.logo"
}

// MARK: - MotionReduce helper

enum MotionPreference {
    static var isReduced: Bool {
        UIAccessibility.isReduceMotionEnabled
    }
}
