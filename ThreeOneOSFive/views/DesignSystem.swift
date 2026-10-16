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
    static let ink          = Color(hex: 0x0A0A0A) // primary text & buttons
    static let inkSecondary = Color(hex: 0x1C1C1E) // dark surfaces (license card)
    static let paper        = Color(hex: 0xFFFFFF) // main background
    static let paperMuted   = Color(hex: 0xF5F5F7) // soft fills (cells)
    static let paperRaised  = Color(hex: 0xFAFAFA) // cards
    static let grey900      = Color(hex: 0x1C1C1E)
    static let grey700      = Color(hex: 0x3A3A3C)
    static let grey600      = Color(hex: 0x636366)
    static let grey500      = Color(hex: 0x6E6E73)
    static let grey400      = Color(hex: 0x8E8E93)
    static let grey300      = Color(hex: 0xC7C7CC)
    static let grey200      = Color(hex: 0xD1D1D6)
    static let grey100      = Color(hex: 0xE5E5EA)
    static let grey50       = Color(hex: 0xF2F2F7)

    static let positive     = Color(hex: 0x111111) // active/loading bars đều đen
    static let negative     = Color(hex: 0x111111)

    // MARK: Borders
    static let borderHairline = Color(hex: 0xD1D1D6)
    static let borderStrong   = Color(hex: 0x111111)

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
    static let pageBackground: Color = .white
    static let consoleBackground: Color = paperMuted

    /// Legacy colors kept for backward compatibility with existing helpers
    /// (AirLiftSettingsSection, PatchProjectEditorView, v.v.).
    /// Sử dụng `.ink` thay vì các giá trị này cho code mới.
    static let accent = ink
    static let accentLight = ink

    /// Aliases cho các tên cũ - trỏ về palette trắng-đen 2026
    static let cyberCyan  = ink
    static let cyberBlue  = ink
    static let cyberPurple = ink
    static let cyberViolet = ink
    static let cyberPink   = ink
    static let cyberGreen  = ink
    static let cyberOLED   = Color.white
    static let cyberSurface = paperMuted

    static let cyberGradient = LinearGradient(
        colors: [ink, ink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let cyberBorderGradient = LinearGradient(
        colors: [ink.opacity(0.5), ink.opacity(0.1)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let cyberSubtleBorder = LinearGradient(
        colors: [Color.black.opacity(0.12), Color.black.opacity(0.02)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

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
            .fill(Color.white)
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
            .background(Color.white)
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

/// Solid black primary button (đồng bộ với "XÁC THỰC NGAY" trong preview)
struct PrimaryButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 15
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(AppTheme.ink)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.ink, lineWidth: 1)
            )
            .foregroundStyle(Color.white)
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.10 : 0.16),
                    radius: configuration.isPressed ? 4 : 14, y: configuration.isPressed ? 2 : 6)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
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
                                .foregroundColor(AppTheme.ink)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(AppTheme.ink)
                                Text(t.message)
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.grey600)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppTheme.ink, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.18), radius: 25, y: 15)
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
    static func success(){ UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error()  { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

// MARK: - Mesh backdrop (trắng, tĩnh)

struct MeshBackground: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            // Soft radial glow nhẹ để có "tầng" rất nhẹ
            RadialGradient(
                colors: [Color.white, AppTheme.grey50, AppTheme.grey100],
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
            Color.white.ignoresSafeArea()
            RadialGradient(
                colors: [Color.white, AppTheme.grey50],
                center: .init(x: 0.5, y: 0.4),
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()
            Rectangle()
                .fill(
                    LinearGradient(colors: [Color.clear, Color.black.opacity(0.05), Color.clear],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
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
