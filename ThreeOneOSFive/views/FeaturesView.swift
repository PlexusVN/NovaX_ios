import SwiftUI

struct FeaturesView: View {
    var showSystemDashboard: Binding<Bool>? = nil
    @EnvironmentObject private var service: FeaturePatchService
    @EnvironmentObject private var authManager: AuthManager
    @State private var selectedCategoryID: Int?
    @State private var showCategoryPicker = false
    @State private var activeToast: ToastInfo?

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
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("Chức năng")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.accent)
            .toolbar {
                if let showSystemDashboard = showSystemDashboard {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Haptics.light()
                            showSystemDashboard.wrappedValue = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(AppTheme.cyberCyan)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(AppTheme.cyberSurface.opacity(0.8)))
                                .overlay(Circle().stroke(AppTheme.cyberCyan.opacity(0.35), lineWidth: 1))
                                .shadow(color: AppTheme.cyberCyan.opacity(0.3), radius: 6)
                        }
                    }
                }
            }
            .refreshable { await service.syncFromServer(auth: authManager) }
            .onAppear {
                if selectedCategoryID == nil, let first = service.categories.first {
                    selectedCategoryID = first.id
                }
                service.preloadCategoryImages()
            }
            .onChange(of: service.categories, perform: { categories in
                if selectedCategoryID == nil, let first = categories.first {
                    selectedCategoryID = first.id
                }
                service.preloadCategoryImages()
            })
        }
        .glassToast(toast: $activeToast)
        .overlay {
            if showCategoryPicker {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showCategoryPicker = false
                            }
                        }
                    
                    customCategoryPicker
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
                .zIndex(100)
            }
        }
    }

    // MARK: - Category Panel

    private var categoryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.cyberCyan)
                    .shadow(color: AppTheme.cyberCyan.opacity(0.4), radius: 4)
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
                            .tint(AppTheme.cyberCyan)
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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.cyberSurface.opacity(0.65))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.cyberBorderGradient, lineWidth: 1.2)
                )
                .shadow(color: AppTheme.cyberCyan.opacity(0.12), radius: 20, y: 8)
        )
    }

    private var categorySelect: some View {
        Button {
            Haptics.light()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showCategoryPicker = true
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.cyberCyan.opacity(0.2), AppTheme.cyberPurple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    if let cat = selectedCategory, let uiImage = service.categoryImage(for: cat.id) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else if let imageURL = selectedCategory?.imageUrl, !imageURL.isEmpty, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Image(systemName: selectedCategory?.icon.isEmpty == false ? selectedCategory!.icon : "gamecontroller.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppTheme.cyberCyan)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: selectedCategory?.icon.isEmpty == false ? selectedCategory!.icon : "square.grid.2x2.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppTheme.cyberCyan)
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
                            .foregroundColor(AppTheme.cyberCyan.opacity(0.7))
                    }
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.cyberCyan.opacity(0.7))
                    .rotationEffect(.degrees(showCategoryPicker ? 180 : 0))
                    .animation(.spring(response: 0.3), value: showCategoryPicker)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.cyberOLED.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [AppTheme.cyberCyan.opacity(0.35), AppTheme.cyberPurple.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: AppTheme.cyberCyan.opacity(0.08), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var selectedCategory: PatchCategory? {
        guard let id = selectedCategoryID else { return nil }
        return service.categories.first { $0.id == id }
    }

    private var customCategoryPicker: some View {
        VStack(spacing: 0) {
            Text("Chọn danh mục")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.vertical, 18)
            
            Divider().background(Color.white.opacity(0.1))
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(service.categories) { cat in
                        Button {
                            Haptics.light()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedCategoryID = cat.id
                                showCategoryPicker = false
                            }
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [AppTheme.cyberCyan.opacity(0.2), AppTheme.cyberPurple.opacity(0.2)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    
                                    if let uiImage = service.categoryImage(for: cat.id) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 42, height: 42)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    } else if !cat.imageUrl.isEmpty, let url = URL(string: cat.imageUrl) {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image.resizable().aspectRatio(contentMode: .fill)
                                            default:
                                                Image(systemName: cat.icon.isEmpty ? "gamecontroller.fill" : cat.icon)
                                                    .foregroundColor(AppTheme.cyberCyan)
                                            }
                                        }
                                        .frame(width: 42, height: 42)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    } else {
                                        Image(systemName: cat.icon.isEmpty ? "gamecontroller.fill" : cat.icon)
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(AppTheme.cyberCyan)
                                    }
                                }
                                .frame(width: 42, height: 42)
                                
                                Text(cat.name)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                ZStack {
                                    Circle()
                                        .stroke(selectedCategoryID == cat.id ? AppTheme.cyberCyan : Color.white.opacity(0.2), lineWidth: 2)
                                        .frame(width: 22, height: 22)
                                    
                                    if selectedCategoryID == cat.id {
                                        Circle()
                                            .fill(AppTheme.cyberCyan)
                                            .frame(width: 12, height: 12)
                                            .shadow(color: AppTheme.cyberCyan.opacity(0.8), radius: 6)
                                    }
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(
                                        selectedCategoryID == cat.id
                                            ? LinearGradient(colors: [AppTheme.cyberCyan.opacity(0.18), AppTheme.cyberPurple.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                            : LinearGradient(colors: [Color.white.opacity(0.03), Color.white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        selectedCategoryID == cat.id
                                            ? AppTheme.cyberBorderGradient
                                            : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 350)
            
            Divider().background(Color.white.opacity(0.1))
            
            Button {
                Haptics.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showCategoryPicker = false
                }
            } label: {
                Text("Hủy")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.cyberSurface.opacity(0.92))
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.cyberBorderGradient, lineWidth: 1.5)
        )
        .shadow(color: AppTheme.cyberCyan.opacity(0.25), radius: 35, x: 0, y: 15)
        .padding(.horizontal, 24)
    }

    // MARK: - Patch Panel

    private var patchPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.cyberCyan)
                    .shadow(color: AppTheme.cyberCyan.opacity(0.4), radius: 4)
                Text("Chức năng")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text("\(filteredPatches.count)")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(AppTheme.cyberCyan)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.cyberCyan.opacity(0.2), AppTheme.cyberPurple.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                Capsule().stroke(AppTheme.cyberCyan.opacity(0.4), lineWidth: 1)
                            )
                    )
            }

            if service.isLoading && service.patches.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(AppTheme.cyberCyan)
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
                        PatchCardView(patch: patch, service: service, auth: authManager, activeToast: $activeToast)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.cyberSurface.opacity(0.65))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.cyberBorderGradient, lineWidth: 1.2)
                )
                .shadow(color: AppTheme.cyberCyan.opacity(0.12), radius: 20, y: 8)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 36, weight: .medium))
                .foregroundColor(AppTheme.cyberCyan.opacity(0.3))
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

// MARK: - Patch Card View

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
