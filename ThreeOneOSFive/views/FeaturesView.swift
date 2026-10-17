import SwiftUI

struct FeaturesView: View {
    var showSystemDashboard: Binding<Bool>? = nil

    @EnvironmentObject private var service: FeaturePatchService
    @EnvironmentObject private var authManager: AuthManager
    @State private var activeToast: ToastInfo?
    @State private var showGamePickerForInject = false
    @State private var showGamePickerForUnject = false
    @State private var isCodePatchWorking = false
    @State private var workingVariant: GamePatchVariant? = nil
    @State private var gameIcons: [String: UIImage] = [:]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppTheme.pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        allFeatureSections
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 220)
                }
                .refreshable { await reload(showLoading: false) }

                injectBar
                    .padding(.bottom, 88)

                // Panel thông báo chọn Free Fire khi bấm INJECT hoặc KHÔI PHỤC GỐC
                if showGamePickerForInject || showGamePickerForUnject {
                    gamePickerModal
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .zIndex(999)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showGamePickerForInject || showGamePickerForUnject)
            .navigationTitle("Chức năng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let showSystemDashboard {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Haptics.light()
                            showSystemDashboard.wrappedValue = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(AppTheme.ink)
                                .frame(width: 34, height: 34)
                                .background(Color.white)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(AppTheme.grey200, lineWidth: 1))
                        }
                    }
                }
            }
            .task {
                loadGameIcons()
                await reload(showLoading: true)
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { break }
                    await service.refreshNativeStateForBothVariants(auth: authManager)
                }
            }
        }
        .glassToast(toast: $activeToast)
    }

    // MARK: - Sections chức năng

    private var allFeatureSections: some View {
        let sections = featureSections()
        return ForEach(sections) { section in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(section.title.uppercased())
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Text("\(section.features.count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.grey500)
                }
                ForEach(section.features) { feature in
                    NativeFeatureControlRow(
                        feature: feature,
                        service: service,
                        auth: authManager,
                        activeToast: $activeToast
                    )
                }
            }
            .cardStyle()
        }
    }

    private struct FeatureSectionModel: Identifiable {
        let title: String
        let features: [NovaXFeatureDefinition]
        var id: String { title }
    }

    private func featureSections() -> [FeatureSectionModel] {
        let all = service.nativeFeatures.isEmpty ? FeaturePatchService.defaultFeatures : service.nativeFeatures
        // Loại bỏ hoàn toàn phần Trang phục và các mục skin
        let features = all.filter { $0.section != "Trang phục" && !$0.id.hasPrefix("mod.") }
        let orderedSections = ["ESP", "Aim", "Khác", "Màu sắc", "Hệ thống"]
        let groups = Dictionary(grouping: features, by: { $0.section })

        var result: [FeatureSectionModel] = []
        for name in orderedSections {
            if let list = groups[name], !list.isEmpty {
                result.append(FeatureSectionModel(title: name, features: list))
            }
        }
        for (name, list) in groups {
            if !orderedSections.contains(name) && !list.isEmpty {
                result.append(FeatureSectionModel(title: name, features: list))
            }
        }
        return result
    }

    // MARK: - Thanh Inject & Khôi phục ở đáy màn hình

    private var injectBar: some View {
        VStack(spacing: 8) {
            Text(service.nativeStatusMessage)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.grey500)
                .lineLimit(1)

            HStack(spacing: 10) {
                Button {
                    Haptics.medium()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showGamePickerForUnject = false
                        showGamePickerForInject = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isCodePatchWorking && showGamePickerForInject {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.down.app.fill")
                        }
                        Text("INJECT")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: AppTheme.ink.opacity(0.35), radius: 14, x: 0, y: 6)
                }
                .disabled(isCodePatchWorking)

                Button {
                    Haptics.medium()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showGamePickerForInject = false
                        showGamePickerForUnject = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isCodePatchWorking && showGamePickerForUnject {
                            ProgressView().tint(AppTheme.ink)
                        } else {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                        }
                        Text("KHÔI PHỤC GỐC")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(AppTheme.ink, lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .disabled(isCodePatchWorking)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(
            VisualEffectBlur()
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Panel thông báo chọn Free Fire (Popup Modal)

    private var gamePickerModal: some View {
        let isInject = showGamePickerForInject
        return ZStack {
            // Nền làm mờ + làm tối
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isCodePatchWorking {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showGamePickerForInject = false
                            showGamePickerForUnject = false
                        }
                    }
                }

            // Hộp thông báo popup chính giữa
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(isInject ? Color(hex: 0xFF5E3A).opacity(0.12) : Color.blue.opacity(0.12))
                            .frame(width: 54, height: 54)
                        Image(systemName: isInject ? "arrow.down.app.fill" : "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(isInject ? Color(hex: 0xFF5E3A) : Color.blue)
                    }
                    .padding(.top, 4)

                    Text(isInject ? "CHỌN GAME ĐỂ KÍCH HOẠT CHEAT" : "CHỌN GAME ĐỂ KHÔI PHỤC")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)

                    Text(isInject
                        ? "Hệ thống sẽ tự động kích hoạt cheat cho game được chọn."
                        : "Hệ thống sẽ khôi phục game về trạng thái nguyên bản.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.grey500)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 22)
                .padding(.bottom, 16)

                Rectangle()
                    .fill(AppTheme.grey200)
                    .frame(height: 1)

                // 2 nút chọn game Free Fire TH và Free Fire MAX
                VStack(spacing: 12) {
                    gameOptionButton(
                        variant: .ffth,
                        title: "Free Fire TH",
                        bundleID: "com.dts.freefireth",
                        isInject: isInject
                    )
                    gameOptionButton(
                        variant: .ffmax,
                        title: "Free Fire MAX",
                        bundleID: "com.dts.freefiremax",
                        isInject: isInject
                    )
                }
                .padding(16)

                if isCodePatchWorking {
                    HStack(spacing: 8) {
                        ProgressView().tint(AppTheme.ink).scaleEffect(0.85)
                        Text(isInject ? "Đang kích hoạt cheat..." : "Đang khôi phục bản gốc...")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.grey500)
                    }
                    .padding(.bottom, 14)
                }

                Rectangle()
                    .fill(AppTheme.grey200)
                    .frame(height: 1)

                // Nút Đóng
                Button {
                    Haptics.light()
                    withAnimation(.easeOut(duration: 0.2)) {
                        showGamePickerForInject = false
                        showGamePickerForUnject = false
                    }
                } label: {
                    Text("Đóng")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.grey500)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .disabled(isCodePatchWorking)
            }
            .frame(maxWidth: 340)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.22), radius: 30, x: 0, y: 12)
            .padding(.horizontal, 24)
        }
    }

    private func gameOptionButton(
        variant: GamePatchVariant,
        title: String,
        bundleID: String,
        isInject: Bool
    ) -> some View {
        Button {
            performCodePatch(variant: variant, inject: isInject)
        } label: {
            HStack(spacing: 14) {
                // Ảnh icon app Free Fire
                Group {
                    if let img = gameIcons[bundleID] {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(LinearGradient(
                                    colors: variant == .ffth
                                        ? [Color(hex: 0xFF5E3A), Color(hex: 0xFF2A68)]
                                        : [Color(hex: 0x00C0FF), Color(hex: 0x7000FF)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                            VStack(spacing: 2) {
                                Image(systemName: variant == .ffth ? "flame.fill" : "bolt.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(variant == .ffth ? "FF TH" : "MAX")
                                    .font(.system(size: 9, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(AppTheme.grey200, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text(bundleID)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.grey500)
                    Text(isInject ? "Kích hoạt cheat" : "Khôi phục gốc")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(isInject ? Color(hex: 0xFF5E3A) : Color.blue)
                }

                Spacer()

                if isCodePatchWorking && workingVariant == variant {
                    ProgressView().tint(AppTheme.ink)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.grey400)
                }
            }
            .padding(12)
            .background(AppTheme.grey50)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.grey200, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isCodePatchWorking)
    }

    // MARK: - Actions

    private func reload(showLoading: Bool) async {
        guard authManager.authState == .verified else { return }
        // Danh sách chức năng đã được đóng gói cố định trong app. Server chỉ còn
        // cung cấp release và trạng thái đồng bộ, nên lỗi kết nối không được chặn
        // giao diện hoặc hiện banner "không thể tải danh sách chức năng" nữa.
        try? await service.loadNativeMenuForBothVariants(auth: authManager, showLoading: showLoading)
    }

    private func performCodePatch(variant: GamePatchVariant, inject: Bool) {
        Haptics.medium()
        isCodePatchWorking = true
        workingVariant = variant
        Task { @MainActor in
            defer {
                isCodePatchWorking = false
                workingVariant = nil
                withAnimation(.easeOut(duration: 0.2)) {
                    showGamePickerForInject = false
                    showGamePickerForUnject = false
                }
            }
            do {
                if inject {
                    try await service.injectCodePatch(variant: variant, auth: authManager)
                    activeToast = ToastInfo(
                        title: "Kích hoạt cheat thành công",
                        message: "Đã kích hoạt cheat cho \(variant.title) thành công.",
                        isSuccess: true
                    )
                } else {
                    try await service.unjectCodePatch(variant: variant, auth: authManager)
                    activeToast = ToastInfo(
                        title: "Khôi phục thành công",
                        message: "Đã khôi phục game \(variant.title) về ban đầu.",
                        isSuccess: true
                    )
                }
            } catch {
                let raw = error.localizedDescription
                let cleanMsg = (raw.contains("Documents") || raw.contains("codepatch") || raw.contains("/") || raw.contains("container") || raw.contains("assembly"))
                    ? "Không thể áp dụng cho \(variant.title). Vui lòng kiểm tra lại quyền ứng dụng."
                    : raw
                activeToast = ToastInfo(
                    title: inject ? "Kích hoạt cheat thất bại" : "Khôi phục thất bại",
                    message: cleanMsg,
                    isSuccess: false
                )
            }
        }
    }

    private func loadGameIcons() {
        DispatchQueue.global(qos: .userInitiated).async {
            var map: [String: UIImage] = [:]
            for v in GamePatchVariant.allCases {
                let bid = v.bundleID
                if let info = appInfoForBundleID(bid) as? [String: Any],
                   let icon = info["icon"] as? UIImage {
                    map[bid] = icon
                }
            }
            if map.count < GamePatchVariant.allCases.count {
                let apps = ContainerStore.installedAppsFromAPI()
                for app in apps {
                    if (app.bundleID == "com.dts.freefireth" || app.bundleID == "com.dts.freefiremax"),
                       let icon = app.icon {
                        map[app.bundleID] = icon
                    }
                }
            }
            DispatchQueue.main.async {
                self.gameIcons = map
            }
        }
    }
}

private extension GamePatchVariant {
    var bundleID: String {
        switch self {
        case .ffth: return "com.dts.freefireth"
        case .ffmax: return "com.dts.freefiremax"
        }
    }
}

// MARK: - Preset màu sắc 0..10

private struct ColorPresetItem: Identifiable {
    let value: Int
    let name: String
    let color: Color

    var id: Int { value }

    static let all: [ColorPresetItem] = [
        ColorPresetItem(value: 0, name: "Cầu vồng", color: .purple),
        ColorPresetItem(value: 1, name: "Mặc định", color: Color(white: 0.85)),
        ColorPresetItem(value: 2, name: "Đỏ", color: Color(red: 1.0, green: 0.15, blue: 0.15)),
        ColorPresetItem(value: 3, name: "Xanh lá", color: Color(red: 0.1, green: 1.0, blue: 0.3)),
        ColorPresetItem(value: 4, name: "Xanh dương", color: Color(red: 0.0, green: 0.55, blue: 1.0)),
        ColorPresetItem(value: 5, name: "Vàng", color: Color(red: 1.0, green: 0.95, blue: 0.1)),
        ColorPresetItem(value: 6, name: "Xanh ngọc", color: Color(red: 0.0, green: 1.0, blue: 1.0)),
        ColorPresetItem(value: 7, name: "Hồng", color: Color(red: 1.0, green: 0.2, blue: 0.75)),
        ColorPresetItem(value: 8, name: "Cam", color: Color(red: 1.0, green: 0.55, blue: 0.0)),
        ColorPresetItem(value: 9, name: "Tím", color: Color(red: 0.7, green: 0.25, blue: 1.0)),
        ColorPresetItem(value: 10, name: "Trắng", color: Color.white)
    ]
}

// MARK: - Row điều khiển chức năng

private struct NativeFeatureControlRow: View {
    let feature: NovaXFeatureDefinition
    @ObservedObject var service: FeaturePatchService
    @ObservedObject var auth: AuthManager
    @Binding var activeToast: ToastInfo?

    @State private var isSending = false
    @State private var sliderValue: Double = 0

    private var desired: NovaXRemoteFeatureState? {
        service.nativeDesiredState[feature.id]
    }
    private var actual: NovaXRemoteFeatureState? {
        service.nativeActualState[feature.id]
    }
    private var assemblyOnline: Bool {
        service.nativeAssemblyOnline
    }
    private var desiredEnabled: Bool {
        desired?.enabled ?? false
    }
    private var desiredValue: Int {
        desired?.value ?? feature.default
    }
    private var isColorFeature: Bool {
        feature.type == "color" || feature.section == "Màu sắc" || feature.id.contains("Color") || feature.id.hasPrefix("colors.")
    }
    private var selectedColorName: String {
        ColorPresetItem.all.first(where: { $0.value == desiredValue })?.name ?? "Mặc định"
    }

    @ViewBuilder
    private func colorCirclePreview(for value: Int, size: CGFloat) -> some View {
        if value == 0 {
            Circle()
                .fill(AngularGradient(
                    gradient: Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]),
                    center: .center
                ))
                .frame(width: size, height: size)
                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                .shadow(color: Color.purple.opacity(0.3), radius: 2, x: 0, y: 1)
        } else {
            let preset = ColorPresetItem.all.first(where: { $0.value == value }) ?? ColorPresetItem.all[1]
            Circle()
                .fill(preset.color)
                .frame(width: size, height: size)
                .overlay(Circle().stroke(preset.value == 10 ? AppTheme.grey300 : Color.black.opacity(0.12), lineWidth: 1))
                .shadow(color: preset.color.opacity(0.35), radius: 2, x: 0, y: 1)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(feature.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    HStack(spacing: 5) {
                        Circle().fill(stateColor).frame(width: 6, height: 6)
                        Text(stateText)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(stateColor)
                    }
                }
                Spacer()

                if isSending {
                    ProgressView().tint(AppTheme.ink).scaleEffect(0.8)
                } else if isColorFeature {
                    Menu {
                        ForEach(ColorPresetItem.all) { preset in
                            Button {
                                send(enabled: true, value: preset.value)
                            } label: {
                                HStack {
                                    Text(preset.name)
                                    if preset.value == desiredValue {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            colorCirclePreview(for: desiredValue, size: 14)
                            Text(selectedColorName)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.ink)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.grey500)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppTheme.grey200, lineWidth: 1))
                    }
                } else if feature.type == "toggle" {
                    Toggle("", isOn: Binding(
                        get: { desiredEnabled },
                        set: { send(enabled: $0, value: desiredValue) }
                    ))
                    .labelsHidden()
                    .tint(AppTheme.ink)
                } else if feature.type == "select" {
                    if feature.options.isEmpty {
                        Text("Chưa có dữ liệu")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.grey400)
                    } else {
                        Menu {
                            ForEach(feature.options) { option in
                                Button(option.title) { send(enabled: true, value: option.value) }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(selectedOptionTitle)
                                Image(systemName: "chevron.down")
                            }
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(AppTheme.grey50)
                            .clipShape(Capsule())
                        }
                    }
                }
            }

            if isColorFeature {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(ColorPresetItem.all) { preset in
                            let isSelected = (preset.value == desiredValue)
                            Button {
                                send(enabled: true, value: preset.value)
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        colorCirclePreview(for: preset.value, size: 26)
                                        if isSelected {
                                            Circle()
                                                .stroke(AppTheme.ink, lineWidth: 2)
                                                .frame(width: 32, height: 32)
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .black))
                                                .foregroundStyle(preset.value == 10 || preset.value == 1 || preset.value == 5 ? Color.black : Color.white)
                                        }
                                    }
                                    .frame(width: 34, height: 34)

                                    Text(preset.name)
                                        .font(.system(size: 9, weight: isSelected ? .bold : .medium, design: .rounded))
                                        .foregroundStyle(isSelected ? AppTheme.ink : AppTheme.grey500)
                                }
                                .padding(.horizontal, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 2)
                }
            } else if feature.type == "range" {
                HStack(spacing: 10) {
                    Slider(
                        value: $sliderValue,
                        in: Double(feature.min)...Double(max(feature.min + 1, feature.max)),
                        step: 1,
                        onEditingChanged: { editing in
                            if !editing { send(enabled: true, value: Int(sliderValue)) }
                        }
                    )
                    .tint(AppTheme.ink)
                    Text("\(Int(sliderValue))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.ink)
                        .frame(minWidth: 30)
                }
            }
        }
        .padding(12)
        .background(AppTheme.grey50)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AppTheme.grey200, lineWidth: 1))
        .onAppear { sliderValue = Double(desiredValue) }
        .onChange(of: desiredValue) { sliderValue = Double($0) }
    }

    private var stateColor: Color {
        if isColorFeature {
            if assemblyOnline {
                let isApplied = actual?.value == desiredValue
                return isApplied ? .green : .blue
            }
            return .orange
        }

        if feature.type == "toggle" {
            if !desiredEnabled {
                if assemblyOnline && actual?.enabled == true {
                    return .blue
                }
                return AppTheme.grey400
            } else {
                if assemblyOnline {
                    return actual?.enabled == true ? .green : .blue
                }
                return .orange
            }
        }

        // Range & Select
        let isDefaultOrOff: Bool
        if feature.type == "range" {
            isDefaultOrOff = desiredValue <= feature.min
        } else {
            isDefaultOrOff = !desiredEnabled || desiredValue == 0
        }

        if isDefaultOrOff {
            return AppTheme.grey400
        }

        if assemblyOnline {
            let isApplied = actual?.value == desiredValue && (feature.type != "select" || actual?.enabled == true)
            return isApplied ? .green : .blue
        }
        return .orange
    }

    private var stateText: String {
        if isColorFeature {
            let name = selectedColorName.uppercased()
            if assemblyOnline {
                let isApplied = actual?.value == desiredValue
                return isApplied ? "ĐÃ CHỌN: \(name)" : "ĐANG ĐỒNG BỘ..."
            }
            return "ĐÃ CHỌN: \(name)"
        }

        if feature.type == "toggle" {
            if !desiredEnabled {
                if assemblyOnline && actual?.enabled == true {
                    return "ĐANG TẮT..."
                }
                return "ĐÃ TẮT"
            } else {
                if assemblyOnline {
                    return actual?.enabled == true ? "ĐANG BẬT" : "ĐANG BẬT..."
                }
                return "SẴN SÀNG"
            }
        }

        // Range
        if feature.type == "range" {
            if desiredValue <= feature.min {
                return "MẶC ĐỊNH"
            }
            if assemblyOnline {
                return actual?.value == desiredValue ? "ĐÃ ÁP DỤNG (\(desiredValue))" : "ĐANG ĐỒNG BỘ..."
            }
            return "SẴN SÀNG (\(desiredValue))"
        }

        // Select
        if !desiredEnabled || desiredValue == 0 {
            return "CHƯA BẬT"
        }
        if assemblyOnline {
            let isApplied = actual?.value == desiredValue && actual?.enabled == true
            return isApplied ? "ĐANG BẬT" : "ĐANG ĐỒNG BỘ..."
        }
        return "SẴN SÀNG"
    }

    private var selectedOptionTitle: String {
        feature.options.first(where: { $0.value == desiredValue })?.title ?? "\(desiredValue)"
    }

    private func send(enabled: Bool, value: Int) {
        Haptics.light()
        isSending = true
        Task { @MainActor in
            defer { isSending = false }
            do {
                try await service.sendNativeCommand(
                    feature: feature,
                    enabled: enabled,
                    value: value,
                    auth: auth
                )
            } catch {
                activeToast = ToastInfo(title: "Không thể gửi lệnh", message: error.localizedDescription, isSuccess: false)
            }
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.grey200, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 6)
    }
}

private struct VisualEffectBlur: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
