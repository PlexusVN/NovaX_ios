import SwiftUI

struct PatchCardView: View {
    let patch: PatchItem
    @ObservedObject var service: FeaturePatchService
    @ObservedObject var auth: AuthManager
    @State private var isApplied = false
    @State private var isWorking = false
    @Binding var activeToast: ToastInfo?
    @State private var glowPulse = false

    var body: some View {
        HStack(spacing: 14) {
            patchImage

            VStack(alignment: .leading, spacing: 4) {
                Text(patch.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if !patch.description.isEmpty {
                    Text(patch.description)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 9))
                    Text(formatSize(patch.fileSize))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.3))
            }

            Spacer()

            toggleButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isApplied ? AppTheme.cyberSurface.opacity(0.7) : AppTheme.cyberOLED.opacity(0.4))

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isApplied
                            ? AppTheme.cyberBorderGradient
                            : LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              ),
                        lineWidth: isApplied ? 1.5 : 0.5
                    )

                if isApplied {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.cyberCyan.opacity(glowPulse ? 0.08 : 0.02), AppTheme.cyberPurple.opacity(glowPulse ? 0.06 : 0.01)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: glowPulse)
                }
            }
            .shadow(color: isApplied ? AppTheme.cyberCyan.opacity(0.25) : .clear, radius: 16, y: 4)
        )
        .onAppear {
            isApplied = service.isPatchApplied(patch)
            if isApplied { startGlow() }
        }
        .onChange(of: isApplied) { applied in
            if applied { startGlow() } else { glowPulse = false }
        }
    }

    private func startGlow() {
        glowPulse = true
    }

    // MARK: - Patch Image

    @ViewBuilder
    private var patchImage: some View {
        if let uiImage = service.cachedImage(for: patch) ?? service.categoryImage(for: patch.categoryId) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isApplied ? AppTheme.cyberBorderGradient : LinearGradient(colors: [Color.white.opacity(0.1), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
                .shadow(color: isApplied ? AppTheme.cyberCyan.opacity(0.35) : .clear, radius: 8)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.cyberCyan.opacity(0.15), AppTheme.cyberPurple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "puzzlepiece.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(AppTheme.cyberCyan.opacity(0.7))
            }
            .frame(width: 52, height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.cyberCyan.opacity(0.25), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Toggle

    @ViewBuilder
    private var toggleButton: some View {
        if isWorking {
            ZStack {
                Capsule()
                    .fill(AppTheme.cyberCyan.opacity(0.15))
                    .frame(width: 56, height: 30)
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.cyberCyan.opacity(0.4), lineWidth: 1)
                    )
                ProgressView()
                    .tint(AppTheme.cyberCyan)
                    .scaleEffect(0.8)
            }
        } else {
            Button(action: { togglePatch() }) {
                ZStack {
                    Capsule()
                        .fill(
                            isApplied
                                ? LinearGradient(colors: [AppTheme.cyberCyan.opacity(0.25), AppTheme.cyberPurple.opacity(0.25)], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.04)], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: 56, height: 30)
                        .overlay(
                            Capsule()
                                .stroke(
                                    isApplied ? AppTheme.cyberBorderGradient : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 1
                                )
                        )

                    Circle()
                        .fill(isApplied ? AppTheme.cyberGradient : LinearGradient(colors: [Color.white, Color(white: 0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 24, height: 24)
                        .offset(x: isApplied ? 13 : -13)
                        .shadow(color: isApplied ? AppTheme.cyberCyan.opacity(0.6) : .clear, radius: 6)

                    if isApplied {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.black)
                            .offset(x: 13)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isApplied)
            }
        }
    }

    // MARK: - Actions

    private func togglePatch() {
        Haptics.light()
        isWorking = true

        Task { @MainActor in
            defer { isWorking = false }
            if isApplied {
                await service.restorePatch(patch, auth: auth)
                isApplied = false
                activeToast = ToastInfo(title: "Thành công", message: "Đã tắt thành công \(patch.name)", isSuccess: true)
            } else {
                do {
                    try await service.applyPatch(patch, auth: auth)
                    isApplied = true
                    activeToast = ToastInfo(title: "Thành công", message: "Đã áp dụng thành công \(patch.name)!", isSuccess: true)
                } catch {
                    let detail = (error as NSError).domain != "NSPOSIXError" ? error.localizedDescription : "Lỗi không xác định (\((error as NSError).code))"
                    activeToast = ToastInfo(title: "Lỗi áp dụng", message: "Không thể áp dụng \(patch.name).\n\nChi tiết: \(detail)", isSuccess: false)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatSize(_ bytes: Int) -> String {
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        } else if bytes >= 1024 {
            return String(format: "%.0f KB", Double(bytes) / 1024)
        }
        return "\(bytes) B"
    }
}
