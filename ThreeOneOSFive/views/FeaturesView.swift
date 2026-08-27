import SwiftUI

struct FeaturesView: View {
    @EnvironmentObject private var service: FeaturePatchService
    @State private var selectedCategoryID: Int?
    @State private var showCategoryPicker = false

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
                    .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                categorySelect
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

    private var categorySelect: some View {
        Button {
            Haptics.light()
            showCategoryPicker = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.15))

                    if let imageURL = selectedCategory?.imageUrl, !imageURL.isEmpty, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Image(systemName: selectedCategory?.icon ?? "gamecontroller.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppTheme.accent)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: selectedCategory?.icon ?? "square.grid.2x2.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppTheme.accent)
                    }
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedCategory?.name ?? "Chọn danh mục")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(selectedCategory != nil ? .white : .white.opacity(0.4))

                    if selectedCategory != nil {
                        Text("\(filteredPatches.count) chức năng")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .rotationEffect(.degrees(showCategoryPicker ? 180 : 0))
                    .animation(.spring(response: 0.3), value: showCategoryPicker)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.accent.opacity(0.25), lineWidth: 1)
                    )
            )
            .shadow(color: AppTheme.accent.opacity(0.1), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .confirmationDialog("Chọn danh mục", isPresented: $showCategoryPicker, titleVisibility: .visible) {
            ForEach(service.categories) { cat in
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedCategoryID = cat.id
                    }
                } label: {
                    HStack {
                        Text(cat.name)
                        if selectedCategoryID == cat.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Button(role: .destructive) {
                Haptics.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedCategoryID = nil
                }
            } label: {
                Text("Xóa bộ lọc")
            }
        }
    }

    private var selectedCategory: PatchCategory? {
        guard let id = selectedCategoryID else { return nil }
        return service.categories.first { $0.id == id }
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
