import SwiftUI

struct FeaturesView: View {
    @EnvironmentObject private var service: FeaturePatchService
    @State private var selectedCategoryID: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        categoryPanel
                        patchPanel
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Chức năng")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.accent)
            .refreshable { await service.syncFromServer() }
        }
    }

    // MARK: - Category Panel

    private var categoryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.accent)
                Text("Danh mục")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text("\(service.categories.count)")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(AppTheme.accent.opacity(0.15))
                    )
            }

            if service.categories.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(AppTheme.accent)
                        Text("Đang tải danh mục...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                categoryGrid
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.accent.opacity(0.3), AppTheme.accent.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: AppTheme.accent.opacity(0.08), radius: 20, y: 4)
        )
    }

    private var categoryGrid: some View {
        VStack(spacing: 10) {
            categoryButton(id: nil, name: "Tất cả", imageURL: nil, icon: "square.grid.2x2.fill")

            ForEach(service.categories) { cat in
                categoryButton(id: cat.id, name: cat.name, imageURL: cat.imageUrl.isEmpty ? nil : cat.imageUrl, icon: cat.icon)
            }
        }
    }

    private func categoryButton(id: Int?, name: String, imageURL: String?, icon: String) -> some View {
        let isSelected = selectedCategoryID == id

        return Button {
            Haptics.light()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedCategoryID = id
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? AppTheme.accent.opacity(0.2) : Color.white.opacity(0.05))

                    if let imageURL, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Image(systemName: icon)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(isSelected ? AppTheme.accent : .white.opacity(0.4))
                            }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isSelected ? AppTheme.accent : .white.opacity(0.4))
                    }
                }
                .frame(width: 36, height: 36)

                Text(name)
                    .font(.system(size: 14, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AppTheme.accent.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                isSelected ? AppTheme.accent.opacity(0.4) : Color.white.opacity(0.06),
                                lineWidth: isSelected ? 1.5 : 0.5
                            )
                    )
            )
            .shadow(color: isSelected ? AppTheme.accent.opacity(0.15) : .clear, radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Patch Panel

    private var patchPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.accent)
                Text("Chức năng")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text("\(filteredPatches.count)")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(AppTheme.accent.opacity(0.15))
                    )
            }

            if service.isLoading && service.patches.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(AppTheme.accent)
                        Text("Đang tải chức năng...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .padding(.vertical, 40)
                    Spacer()
                }
            } else if filteredPatches.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredPatches) { patch in
                        PatchCardView(patch: patch, service: service)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.accent.opacity(0.2), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: AppTheme.accent.opacity(0.05), radius: 16, y: 4)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 36, weight: .medium))
                .foregroundColor(AppTheme.accent.opacity(0.25))
            Text("Chưa có chức năng nào")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            Text("Đang cập nhật từ máy chủ...")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var filteredPatches: [PatchItem] {
        if let catID = selectedCategoryID {
            return service.patches.filter { $0.categoryId == catID }
        }
        return service.patches
    }
}
