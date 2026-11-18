import SwiftUI

private func userFacingFeatureText(_ raw: String, fallback: String) -> String {
    let hiddenTerms = [".3105", "3105", "patch", "file", "tệp"]
    let cleaned = hiddenTerms.reduce(raw) { value, term in
        value.replacingOccurrences(of: term, with: "", options: .caseInsensitive)
    }
    let normalized = cleaned.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    return normalized.isEmpty ? fallback : normalized
}

struct FeaturesView: View {
    var showSystemDashboard: Binding<Bool>? = nil
    @EnvironmentObject private var service: FeaturePatchService
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var protectedDownloads = ProtectedDownloadService.shared
    @State private var selectedCategoryID: Int?
    @State private var selectedEdition: CatalogGameEdition = .ffth
    @State private var showsAllCategories = false
    @State private var showCategoryPicker = false
    @State private var categorySearch = ""
    @State private var searchText = ""
    @State private var appliedOnly = false
    @State private var activeToast: ToastInfo?

    private var selectedCategory: PatchCategory? {
        guard let id = selectedCategoryID else { return nil }
        return service.categories.first { $0.id == id }
    }
    private var categoryPatches: [PatchItem] {
        guard let id = selectedCategoryID else { return service.patches }
        return service.patches.filter { $0.categoryId == id }
    }
    private var filteredPatches: [PatchItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let editions = CatalogGameGrouping.editions(in: categoryPatches)
        let gamePatches = CatalogGameGrouping.patches(categoryPatches, for: editions.isEmpty ? nil : selectedEdition)
        return gamePatches.filter { patch in
            (!appliedOnly || service.patchApplicationState(patch).requiresRestore)
                && (query.isEmpty || patch.name.localizedStandardContains(query)
                    || patch.description.localizedStandardContains(query))
        }
    }
    private var searchedCategories: [PatchCategory] {
        let query = categorySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return service.categories.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
    }
    private var hasSearchFilters: Bool { appliedOnly || !searchText.isEmpty }
    private var availableEditions: [CatalogGameEdition] { CatalogGameGrouping.pickerEditions(in: categoryPatches) }
    private var accessMessage: String? { protectedDownloads.accessNotice ?? service.catalogError }

    private func categoryTint(_ category: PatchCategory?) -> Color {
        switch category?.icon {
        case "scope":
            return AppTheme.gamingBlue
        case "location.fill":
            return AppTheme.statusSuccess
        case "tshirt.fill":
            return Color(hex: 0xFF9F2E)
        default:
            return AppTheme.gamingBlueBright
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GamingBackdrop()
                ScrollView {
                    VStack(spacing: 16) {
                        categoryPanel
                        if availableEditions.count > 1 { gameEditionPicker }
                        searchAndFilter
                        functionPanel
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Chức năng")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.gamingBlueBright)
            .toolbar {
                if let showSystemDashboard {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Haptics.soft()
                            showSystemDashboard.wrappedValue = true
                        } label: {
                            Image(systemName: "gearshape.fill").font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.gamingBlueBright)
                                .frame(width: 36, height: 36)
                                .background(AppTheme.gamingBlue.opacity(0.10), in: Circle())
                                .overlay(Circle().stroke(AppTheme.gamingBlue.opacity(0.25), lineWidth: 1))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Cài đặt thiết bị và ứng dụng")
                    }
                }
            }
            .refreshable { await service.syncFromServer(auth: authManager) }
            .onAppear { reconcileCategory(); service.preloadCategoryImages() }
            .onChange(of: service.categories) { _ in reconcileCategory(); service.preloadCategoryImages() }
            .onChange(of: service.patches) { _ in reconcileEdition() }
            .onChange(of: selectedCategoryID) { _ in reconcileEdition() }
            .sheet(isPresented: $showCategoryPicker) { categoryPicker }
        }
        .preferredColorScheme(.dark)
        .glassToast(toast: $activeToast)
    }

    private var categoryPanel: some View {
        let tint = categoryTint(selectedCategory)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill").foregroundStyle(AppTheme.gamingBlueBright)
                Text("DANH MỤC").tracking(1.5).foregroundStyle(AppTheme.gamingTextSecondary)
                Spacer()
                Text("ITECH").tracking(1.8).foregroundStyle(AppTheme.statusInfo)
            }.font(.caption2.weight(.bold))
            if service.categories.isEmpty && !showsAllCategories {
                HStack(spacing: 14) {
                    Image(systemName: "square.grid.2x2").font(.title2)
                        .foregroundStyle(AppTheme.gamingBlueBright).frame(width: 54, height: 54)
                        .background(AppTheme.gamingSurfaceRaised, in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(service.isLoading ? "Đang tải danh mục…" : "Danh mục Astra")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.gamingText)
                        Text(service.isLoading ? "Đang đồng bộ với máy chủ" : (accessMessage == nil ? "Chưa có danh mục được phát hành" : "Cần kiểm tra kết nối máy chủ"))
                            .font(.caption).foregroundStyle(AppTheme.gamingTextSecondary)
                    }
                    Spacer(minLength: 0)
                    if service.isLoading { ProgressView().tint(AppTheme.gamingBlueBright) }
                }
            } else {
                Button {
                    categorySearch = ""
                    showCategoryPicker = service.categories.count > 1
                    Haptics.soft()
                } label: {
                    HStack(spacing: 14) {
                        categoryArtwork(selectedCategory, size: 56)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(selectedCategory.map { userFacingFeatureText($0.name, fallback: "Danh mục") } ?? "Tất cả danh mục")
                                .font(.headline).foregroundStyle(AppTheme.gamingText)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 7) {
                                Circle().fill(tint).frame(width: 4, height: 4)
                                Text("\(categoryPatches.count) chức năng").font(.caption.weight(.medium))
                            }.foregroundStyle(AppTheme.gamingTextSecondary)
                        }
                        Spacer(minLength: 4)
                        if service.categories.count > 1 {
                            Image(systemName: "chevron.down").font(.caption.weight(.bold))
                                .foregroundStyle(tint).frame(width: 30, height: 30)
                                .background(tint.opacity(0.12), in: Circle())
                        } else {
                            Image(systemName: "crown.fill").foregroundStyle(AppTheme.statusInfo)
                        }
                    }.contentShape(Rectangle())
                }
                .buttonStyle(GamingPressButtonStyle(scale: 0.99))
                .accessibilityLabel(selectedCategory?.name ?? "Tất cả danh mục")
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [AppTheme.gamingSurfaceRaised, AppTheme.gamingSurface], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(tint.opacity(0.28), lineWidth: 1))
        .shadow(color: tint.opacity(0.07), radius: 18, y: 6)
    }

    private var gameEditionPicker: some View {
        HStack(spacing: 6) {
            ForEach(availableEditions) { edition in
                let isSelected = selectedEdition == edition
                Button {
                    Haptics.selection()
                    selectedEdition = edition
                } label: {
                    VStack(spacing: 5) {
                        Text(edition.title).font(.subheadline.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(CatalogGameGrouping.patches(categoryPatches, for: edition).count) chức năng")
                            .font(.caption2)
                    }
                    .foregroundStyle(isSelected ? AppTheme.gamingBlueBright : AppTheme.gamingTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 54).padding(.vertical, 5)
                    .background(isSelected ? AppTheme.gamingBlue.opacity(0.17) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13)
                        .stroke(isSelected ? AppTheme.gamingBlue.opacity(0.4) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(GamingPressButtonStyle(scale: 0.98))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(5).background(AppTheme.gamingSurface, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(AppTheme.gamingBorder, lineWidth: 1))
        .accessibilityElement(children: .contain).accessibilityLabel("Chọn phiên bản Free Fire")
    }

    private var searchAndFilter: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.gamingTextSecondary).accessibilityHidden(true)
                TextField("Tìm chức năng…", text: $searchText)
                    .font(.subheadline).foregroundStyle(AppTheme.gamingText)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    .accessibilityLabel("Tìm kiếm chức năng trong danh mục")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.gamingTextSecondary)
                            .frame(width: 32, height: 44)
                    }.accessibilityLabel("Xóa nội dung tìm kiếm")
                }
            }
            .padding(.horizontal, 13).frame(minHeight: 46)
            .background(AppTheme.gamingSurface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(AppTheme.gamingBorder, lineWidth: 1))
            Menu {
                Toggle("Chỉ hiện chức năng đang bật", isOn: $appliedOnly)
                if hasSearchFilters { Button("Xóa bộ lọc") { clearSearchFilters() } }
                if service.categories.count > 1 { Button("Chọn danh mục") { showCategoryPicker = true } }
            } label: {
                Image(systemName: "line.3.horizontal.decrease").font(.body.weight(.semibold))
                    .foregroundStyle(appliedOnly ? AppTheme.statusInfo : AppTheme.gamingBlueBright)
                    .frame(width: 46, height: 46)
                    .background(appliedOnly ? AppTheme.statusInfo.opacity(0.10) : AppTheme.gamingSurface, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(appliedOnly ? AppTheme.statusInfo.opacity(0.4) : AppTheme.gamingBorder, lineWidth: 1))
            }.accessibilityLabel(appliedOnly ? "Bộ lọc, đang hiện chức năng bật" : "Lọc chức năng")
        }
    }

    private var functionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(AppTheme.gamingBlueBright)
                Text("CHỨC NĂNG").tracking(1.5).foregroundStyle(AppTheme.gamingText)
                Spacer()
                Text("\(filteredPatches.count)").font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(AppTheme.statusInfo).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(AppTheme.statusInfo.opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(AppTheme.statusInfo.opacity(0.23), lineWidth: 1))
            }.font(.caption.weight(.bold))
            if let message = accessMessage {
                feedbackState(icon: "wifi.exclamationmark", title: "Chưa tải được chức năng", message: message, retry: true)
            } else if service.isLoading && service.patches.isEmpty {
                HStack(spacing: 12) {
                    ProgressView().tint(AppTheme.gamingBlueBright)
                    Text("Đang đồng bộ chức năng…").font(.subheadline).foregroundStyle(AppTheme.gamingTextSecondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 32)
            } else if filteredPatches.isEmpty {
                feedbackState(icon: hasSearchFilters ? "magnifyingglass" : "square.stack.3d.up", title: hasSearchFilters ? "Không tìm thấy chức năng" : "Chưa có chức năng", message: hasSearchFilters ? "Thử từ khóa khác hoặc xóa bộ lọc." : (availableEditions.isEmpty ? "Danh sách sẽ hiển thị khi máy chủ phát hành chức năng cho danh mục này." : "Danh mục này chưa có chức năng cho \(selectedEdition.title)."), retry: false)
                if hasSearchFilters {
                    Button("Xóa bộ lọc") { clearSearchFilters() }.font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredPatches, id: \.downloadIdentity) { patch in
                        PatchCardView(patch: patch, service: service, auth: authManager, activeToast: $activeToast)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.gamingSurface.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.gamingBorder, lineWidth: 1))
    }

    private func feedbackState(icon: String, title: String, message: String, retry: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(AppTheme.gamingBlueBright)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.gamingText)
            Text(message).font(.caption).foregroundStyle(AppTheme.gamingTextSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if retry {
                Button("Thử lại") { Task { await service.syncFromServer(auth: authManager) } }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(service.isLoading)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 26)
    }

    private var categoryPicker: some View {
        NavigationStack {
            List {
                if categorySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    categoryPickerRow(category: nil)
                }
                ForEach(searchedCategories) { category in categoryPickerRow(category: category) }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(AppTheme.gamingBackground)
            .navigationTitle("Chọn danh mục").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $categorySearch, prompt: "Tìm danh mục")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Xong") { showCategoryPicker = false }.font(.subheadline.weight(.semibold))
                }
            }
        }
        .tint(AppTheme.gamingBlueBright).preferredColorScheme(.dark)
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }

    private func categoryPickerRow(category: PatchCategory?) -> some View {
        let selected = category.map { selectedCategoryID == $0.id } ?? showsAllCategories
        return Button {
            selectedCategoryID = category?.id
            showsAllCategories = category == nil
            showCategoryPicker = false
            Haptics.selection()
        } label: {
            HStack(spacing: 12) {
                categoryArtwork(category, size: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text(category.map { userFacingFeatureText($0.name, fallback: "Danh mục") } ?? "Tất cả danh mục")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.gamingText)
                    Text("\(category.map { category in service.patches.filter { $0.categoryId == category.id }.count } ?? service.patches.count) chức năng")
                        .font(.caption).foregroundStyle(AppTheme.gamingTextSecondary)
                }
                Spacer(minLength: 4)
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(categoryTint(category)) }
            }.padding(.vertical, 6)
        }
        .listRowBackground(AppTheme.gamingSurface)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func categoryArtwork(_ category: PatchCategory?, size: CGFloat) -> some View {
        if let category, !category.imageUrl.isEmpty, let image = service.categoryImage(for: category.id) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26)).accessibilityHidden(true)
        } else {
            let tint = categoryTint(category)
            Image(systemName: category?.icon.isEmpty == false ? category!.icon : "square.grid.2x2.fill")
                .font(.system(size: size * 0.34, weight: .semibold)).foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: size * 0.26))
                .overlay(RoundedRectangle(cornerRadius: size * 0.26).stroke(tint.opacity(0.25), lineWidth: 1))
                .accessibilityHidden(true)
        }
    }
    private func reconcileCategory() {
        if let id = selectedCategoryID, service.categories.contains(where: { $0.id == id }) {
            reconcileEdition()
            return
        }
        selectedCategoryID = showsAllCategories && service.categories.count > 1 ? nil : service.categories.first?.id
        reconcileEdition()
    }
    private func reconcileEdition() {
        let editions = availableEditions
        if !editions.contains(selectedEdition), let first = editions.first { selectedEdition = first }
    }
    private func clearSearchFilters() { searchText = ""; appliedOnly = false }
}

struct PatchCardView: View {
    let patch: PatchItem
    @ObservedObject var service: FeaturePatchService
    @ObservedObject var auth: AuthManager
    @ObservedObject private var storage = StorageEngineCoordinator.shared
    @Binding var activeToast: ToastInfo?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var isWorking = false
    @State private var showUpgradePrompt = false
    private var isLocked: Bool {
        !CatalogFeatureAccess.allows(licenseType: auth.keyType.rawValue, requiredKeyType: patch.requiredKeyType)
    }
    private var upgradeCode: String { patch.requiredKeyType == "pro" ? "pro_required" : "vip_required" }
    private var applicationState: PatchApplicationState { service.patchApplicationState(patch) }
    private var isApplied: Bool { applicationState.requiresRestore }
    private var stateTitle: String {
        if service.isPendingActivation(patch) { return "Cần thử lại" }
        if isLocked && !isApplied { return patch.requiredKeyType == "pro" ? "Yêu cầu key PRO" : "Dành cho key VIP" }
        if service.isSuppressedByCatalogMode(patch) { return "Đã tắt theo chế độ" }
        switch applicationState {
        case .off: return "Sẵn sàng"
        case .applied: return "Đang bật"
        case .recoveryRequired: return "Cần khôi phục"
        }
    }
    private var stateColor: Color {
        if isLocked && !isApplied { return AppTheme.statusInfo }
        switch applicationState {
        case .off: return AppTheme.gamingTextSecondary
        case .applied: return AppTheme.statusSuccess
        case .recoveryRequired: return AppTheme.statusInfo
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                patchImage
                VStack(alignment: .leading, spacing: 6) {
                    Text(userFacingFeatureText(patch.name, fallback: "Chức năng"))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.gamingText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Circle().fill(stateColor).frame(width: 5, height: 5)
                        Text(stateTitle).font(.caption2.weight(.medium)).foregroundStyle(stateColor)
                        Text("· v\(patch.version)").font(.caption2.monospaced()).foregroundStyle(AppTheme.gamingTextSecondary)
                    }
                }
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize { toggleButton }
            }
            if !patch.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(userFacingFeatureText(patch.description, fallback: "Chức năng Astra"))
                    .font(.caption).foregroundStyle(AppTheme.gamingTextSecondary).lineLimit(2)
            }
            if service.isRestorationPatch(patch) {
                Text("Bật mục này sẽ tắt công tắc các chức năng khác. Chỉ các file có trong gói được khôi phục.")
                    .font(.caption2).foregroundStyle(AppTheme.statusInfo)
            } else if isApplied && storage.isAirLiftActive {
                Text("AirLift chưa hỗ trợ khôi phục dữ liệu gốc.").font(.caption2).foregroundStyle(AppTheme.statusInfo)
            }
            if patch.artifactVariant == "ffvn" {
                Text("Đích: Free Fire Việt Nam").font(.caption2).foregroundStyle(AppTheme.statusInfo)
            } else if let display = patch.displayVariant, let target = patch.artifactVariant,
               display != target, let edition = CatalogGameEdition(rawValue: target) {
                Text("Đích trong gói: \(edition.title)").font(.caption2).foregroundStyle(AppTheme.statusInfo)
            }
            if dynamicTypeSize.isAccessibilitySize { HStack { Spacer(); toggleButton } }
        }
        .padding(14)
        .background(
            LinearGradient(colors: [AppTheme.gamingSurfaceRaised.opacity(isApplied ? 0.95 : 0.7), AppTheme.gamingSurfaceRaised.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(isApplied ? AppTheme.gamingBlue.opacity(0.5) : AppTheme.gamingBorder.opacity(0.7), lineWidth: 1))
        .overlay(alignment: .leading) {
            if isApplied { Capsule().fill(AppTheme.statusInfo).frame(width: 2, height: 22) }
        }
        .shadow(color: isApplied ? AppTheme.gamingBlue.opacity(0.10) : .clear, radius: 12, y: 3)
        .alert(patch.requiredKeyType == "pro" ? "Nâng cấp key PRO" : "Chức năng dành cho key VIP", isPresented: $showUpgradePrompt) {
            Button("Liên hệ admin") {
                if let url = URL(string: "https://t.me/trnmnhkh") { openURL(url) }
            }
            Button("Đóng", role: .cancel) {}
        } message: {
            Text(ProtectedDownloadError.rejected(upgradeCode).localizedDescription)
        }
    }

    @ViewBuilder private var patchImage: some View {
        if let image = service.cachedImage(for: patch) ?? service.categoryImage(for: patch.categoryId) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
        } else {
            Image(systemName: "puzzlepiece.fill").font(.body).foregroundStyle(AppTheme.gamingBlueBright)
                .frame(width: 44, height: 44).background(AppTheme.gamingBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
        }
    }

    private var toggleButton: some View {
        Button { togglePatch() } label: {
            ZStack {
                Capsule().fill(isApplied ? AppTheme.gamingBlue.opacity(0.24) : AppTheme.gamingBackground)
                    .overlay(Capsule().stroke(isApplied ? AppTheme.gamingBlueBright.opacity(0.55) : AppTheme.gamingBorder, lineWidth: 1))
                if isWorking {
                    ProgressView().tint(AppTheme.gamingBlueBright).scaleEffect(0.8)
                } else {
                    Circle().fill(isApplied ? AppTheme.gamingBlue : AppTheme.gamingTextSecondary)
                        .frame(width: 24, height: 24).offset(x: isApplied ? 12 : -12)
                        .overlay {
                            if isApplied {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .black))
                                    .foregroundStyle(.white).offset(x: 12)
                            } else if isLocked {
                                Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(AppTheme.gamingBackground).offset(x: -12)
                            }
                        }
                }
            }.frame(width: 56, height: 30).frame(minHeight: 44)
        }
        .buttonStyle(GamingPressButtonStyle(scale: 0.96))
        .disabled(isWorking || service.isCatalogOperationInProgress)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isApplied)
        .accessibilityLabel("\(service.isPendingActivation(patch) ? "Thử lại" : isApplied ? "Tắt" : "Bật") \(userFacingFeatureText(patch.name, fallback: "chức năng"))")
        .accessibilityValue(isWorking ? "Đang xử lý" : stateTitle)
        .accessibilityHint(isLocked && !isApplied ? "Nhấn để liên hệ admin nâng cấp và mở khóa." : (service.isRestorationPatch(patch) ? "Tắt chế độ vẫn giữ file đã khôi phục." : isApplied && storage.isAirLiftActive ? "AirLift chưa hỗ trợ khôi phục dữ liệu gốc." : ""))
    }

    private func togglePatch() {
        guard !isWorking, !service.isCatalogOperationInProgress else { return }
        if !isApplied && isLocked {
            Haptics.soft()
            showUpgradePrompt = true
            return
        }
        Haptics.medium()
        isWorking = true
        let restoring = isApplied && !service.isPendingActivation(patch)
        Task { @MainActor in
            defer { isWorking = false }
            do {
                if restoring { try await service.restorePatch(patch, auth: auth) }
                else { try await service.applyPatch(patch, auth: auth) }
                Haptics.success()
                let message: String
                if restoring {
                    message = service.isRestorationPatch(patch)
                        ? "Đã tắt chế độ khôi phục. Các file đã khôi phục được giữ nguyên."
                        : "Đã hoàn lại dữ liệu trước lần bật chức năng này."
                } else {
                    message = service.isRestorationPatch(patch)
                        ? "Đã áp dụng gói khôi phục và tắt công tắc các chức năng khác."
                        : "Chức năng đã được áp dụng; chế độ khôi phục đã tắt."
                }
                activeToast = ToastInfo(title: restoring ? "Đã tắt chức năng" : "Đã bật chức năng", message: message, isSuccess: true)
            } catch {
                Haptics.error()
                if let protectedError = error as? ProtectedDownloadError,
                   case .rejected(let code) = protectedError, ["vip_required", "pro_required"].contains(code) {
                    showUpgradePrompt = true
                    return
                }
                activeToast = ToastInfo(title: restoring ? "Chưa thể khôi phục" : "Chưa thể bật chức năng", message: (error as? LocalizedError)?.errorDescription ?? "Không thể hoàn tất thao tác (mã \((error as NSError).code)).", isSuccess: false)
            }
        }
    }
}
