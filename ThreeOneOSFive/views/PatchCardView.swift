import SwiftUI

struct PatchCardView: View {
    let patch: PatchItem
    @ObservedObject var service: FeaturePatchService
    @State private var isApplied = false
    @State private var isWorking = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
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
                    .fill(Color.white.opacity(isApplied ? 0.05 : 0.02))

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isApplied
                            ? LinearGradient(
                                colors: [AppTheme.accent.opacity(0.5), AppTheme.accent.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                            : LinearGradient(
                                colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              ),
                        lineWidth: isApplied ? 1.5 : 0.5
                    )

                if isApplied {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.accent.opacity(glowPulse ? 0.06 : 0.02))
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: glowPulse)
                }
            }
            .shadow(color: isApplied ? AppTheme.accent.opacity(0.2) : .clear, radius: 16, y: 4)
        )
        .onAppear {
            isApplied = service.isPatchApplied(patch)
            if isApplied { startGlow() }
        }
        .onChange(of: isApplied) { applied in
            if applied { startGlow() } else { glowPulse = false }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func startGlow() {
        glowPulse = true
    }

    // MARK: - Patch Image

    @ViewBuilder
    private var patchImage: some View {
        if let uiImage = service.cachedImage(for: patch) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isApplied ? AppTheme.accent.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: isApplied ? AppTheme.accent.opacity(0.3) : .clear, radius: 8)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.15), AppTheme.accent.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "puzzlepiece.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(AppTheme.accent.opacity(0.5))
            }
            .frame(width: 52, height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.accent.opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Toggle

    @ViewBuilder
    private var toggleButton: some View {
        if isWorking {
            ZStack {
                Capsule()
                    .fill(AppTheme.accent.opacity(0.15))
                    .frame(width: 56, height: 30)
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.accent.opacity(0.3), lineWidth: 0.5)
                    )
                ProgressView()
                    .tint(AppTheme.accent)
                    .scaleEffect(0.8)
            }
        } else {
            Button(action: { togglePatch() }) {
                ZStack {
                    Capsule()
                        .fill(isApplied ? AppTheme.accent.opacity(0.2) : Color.white.opacity(0.06))
                        .frame(width: 56, height: 30)
                        .overlay(
                            Capsule()
                                .stroke(
                                    isApplied ? AppTheme.accent.opacity(0.5) : Color.white.opacity(0.1),
                                    lineWidth: 1
                                )
                        )

                    Circle()
                        .fill(isApplied ? AppTheme.accent : .white)
                        .frame(width: 24, height: 24)
                        .offset(x: isApplied ? 13 : -13)
                        .shadow(color: isApplied ? AppTheme.accent.opacity(0.5) : .clear, radius: 6)

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
            if isApplied {
                await service.restorePatch(patch)
                isApplied = false
                isWorking = false
                alertTitle = "Khôi phục thành công"
                alertMessage = "Đã khôi phục file gốc của \(patch.name)."
                showAlert = true
            } else {
                do {
                    try await service.applyPatch(patch)
                    isApplied = true
                    isWorking = false
                    alertTitle = "Áp dụng thành công"
                    alertMessage = "Đã áp dụng \(patch.name) lên thiết bị."
                    showAlert = true
                } catch {
                    isWorking = false
                    let detail = (error as NSError).domain != "NSPOSIXError" ? error.localizedDescription : "Lỗi không xác định (\((error as NSError).code))"
                    alertTitle = "Lỗi áp dụng"
                    alertMessage = "Không thể áp dụng \(patch.name).\n\nChi tiết: \(detail)\n\nFile: \(patch.fileUrl.isEmpty ? "trống" : patch.fileUrl)"
                    showAlert = true
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
