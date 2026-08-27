import SwiftUI

struct PatchCardView: View {
    let patch: PatchItem
    @ObservedObject var service: FeaturePatchService
    @State private var isApplied = false
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 14) {
            patchImage

            VStack(alignment: .leading, spacing: 4) {
                Text(patch.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                if !patch.description.isEmpty {
                    Text(patch.description)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(2)
                }

                HStack(spacing: 4) {
                    Circle()
                        .fill(isApplied ? Color.green : Color.white.opacity(0.2))
                        .frame(width: 6, height: 6)
                    Text(isApplied ? "Đang kích hoạt" : "Chưa kích hoạt")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(isApplied ? .green : .white.opacity(0.3))
                }
            }

            Spacer()

            toggleButton
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isApplied ? 0.06 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isApplied ? AppTheme.accent.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
        .onAppear { isApplied = service.isPatchApplied(patch) }
    }

    // MARK: - Patch Image

    @ViewBuilder
    private var patchImage: some View {
        if let uiImage = service.cachedImage(for: patch) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.1))
                Image(systemName: "puzzlepiece.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(AppTheme.accent.opacity(0.5))
            }
            .frame(width: 56, height: 56)
        }
    }

    // MARK: - Toggle

    @ViewBuilder
    private var toggleButton: some View {
        if isWorking {
            ProgressView()
                .tint(AppTheme.accent)
                .frame(width: 50, height: 28)
        } else {
            Button(action: { togglePatch() }) {
                ZStack {
                    Capsule()
                        .fill(isApplied ? Color.green.opacity(0.25) : Color.white.opacity(0.08))
                        .frame(width: 50, height: 28)
                        .overlay(
                            Capsule()
                                .stroke(isApplied ? Color.green.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 0.5)
                        )

                    Circle()
                        .fill(isApplied ? Color.green : Color.white.opacity(0.5))
                        .frame(width: 22, height: 22)
                        .offset(x: isApplied ? 11 : -11)
                        .shadow(color: isApplied ? Color.green.opacity(0.4) : .clear, radius: 4)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isApplied)
            }
        }
    }

    // MARK: - Actions

    private func togglePatch() {
        Haptics.light()
        isWorking = true

        Task {
            if isApplied {
                service.restorePatch(patch)
                isApplied = false
            } else {
                do {
                    try await service.applyPatch(patch)
                    isApplied = true
                } catch {
                    print("[PatchCard] apply error: \(error)")
                }
            }
            isWorking = false
        }
    }
}
