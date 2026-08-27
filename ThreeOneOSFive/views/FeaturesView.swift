import SwiftUI

struct FeaturesView: View {
    @StateObject private var service = FeaturePatchService()
    @State private var selectedCategoryID: Int?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if service.isLoading && service.categories.isEmpty {
                    Spacer()
                    ProgressView()
                        .tint(AppTheme.accent)
                    Text("Đang tải...")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, 12)
                    Spacer()
                } else if service.categories.isEmpty {
                    emptyState
                } else {
                    categoryPicker
                    patchList
                }
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("Chức năng")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.accent)
            .task { await service.syncFromServer() }
            .refreshable { await service.syncFromServer() }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "wand.and.stars")
                .font(.system(size: 40, weight: .medium))
                .foregroundColor(AppTheme.accent.opacity(0.3))
            Text("Chưa có chức năng nào")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text("Đang cập nhật từ máy chủ...")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
            Spacer()
        }
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(label: "Tất cả", isSelected: selectedCategoryID == nil) {
                    selectedCategoryID = nil
                }

                ForEach(service.categories) { cat in
                    categoryChip(label: cat.name, isSelected: selectedCategoryID == cat.id) {
                        selectedCategoryID = cat.id
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.white.opacity(0.02))
    }

    private func categoryChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.light(); action() }) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? AppTheme.accent.opacity(0.25) : Color.white.opacity(0.05))
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? AppTheme.accent.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
        }
    }

    // MARK: - Patch List

    private var patchList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredPatches) { patch in
                    PatchCardView(patch: patch, service: service)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
    }

    private var filteredPatches: [PatchItem] {
        if let catID = selectedCategoryID {
            return service.patches.filter { $0.categoryId == catID }
        }
        return service.patches
    }
}
