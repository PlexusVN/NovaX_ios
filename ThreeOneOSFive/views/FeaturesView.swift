import SwiftUI

struct FeaturesView: View {
    @EnvironmentObject private var service: FeaturePatchService
    @State private var selectedCategoryID: Int?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryPicker

                if service.isLoading && service.patches.isEmpty {
                    Spacer()
                    ProgressView()
                        .tint(AppTheme.accent)
                    Text("Đang tải...")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, 12)
                    Spacer()
                } else if filteredPatches.isEmpty {
                    emptyState
                } else {
                    patchList
                }
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("Chức năng")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.accent)
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
        HStack(spacing: 0) {
            Menu {
                Button {
                    Haptics.light()
                    selectedCategoryID = nil
                } label: {
                    HStack {
                        Text("Tất cả")
                        if selectedCategoryID == nil { Spacer(); Image(systemName: "checkmark") }
                    }
                }

                ForEach(service.categories) { cat in
                    Button {
                        Haptics.light()
                        selectedCategoryID = cat.id
                    } label: {
                        HStack {
                            if !cat.imageUrl.isEmpty, let url = URL(string: cat.imageUrl) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    default:
                                        Image(systemName: "photo")
                                    }
                                }
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            Text(cat.name)
                            if selectedCategoryID == cat.id { Spacer(); Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if let selectedCat = selectedCategory, let url = URL(string: selectedCat.imageUrl), !selectedCat.imageUrl.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Image(systemName: "photo")
                            }
                        }
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    Text(selectedCategory?.name ?? "Tất cả")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
            }
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.02))
    }

    private var selectedCategory: PatchCategory? {
        guard let id = selectedCategoryID else { return nil }
        return service.categories.first { $0.id == id }
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
