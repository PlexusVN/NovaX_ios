import SwiftUI

struct PatchCardView: View {
    let patch: PatchItem
    @ObservedObject var service: FeaturePatchService
    @State private var isApplied = false
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 14) {
            patchImage

            Text(patch.name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            toggleButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isApplied ? 0.06 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isApplied ? AppTheme.accent.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 0.5)
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
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.08))
                Image(systemName: "puzzlepiece.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(AppTheme.accent.opacity(0.4))
            }
            .frame(width: 48, height: 48)
        }
    }

    // MARK: - Toggle

    @ViewBuilder
    private var toggleButton: some View {
        if isWorking {
            ProgressView()
                .tint(AppTheme.accent)
                .frame(width: 48, height: 28)
        } else {
            Button(action: { togglePatch() }) {
                ZStack {
                    Capsule()
                        .fill(isApplied ? Color.green.opacity(0.25) : Color.white.opacity(0.08))
                        .frame(width: 48, height: 28)
                        .overlay(
                            Capsule()
                                .stroke(isApplied ? Color.green.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 0.5)
                        )

                    Circle()
                        .fill(isApplied ? Color.green : .white)
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
