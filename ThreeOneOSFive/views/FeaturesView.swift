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
        let features = service.nativeFeatures.isEmpty ? FeaturePatchService.defaultFeatures : service.nativeFeatures
        let orderedSections = ["ESP", "Aim", "Khác", "Màu sắc", "Trang phục", "Hệ thống"]
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

                    Text(isInject ? "CHỌN FREE FIRE ĐỂ INJECT" : "CHỌN FREE FIRE ĐỂ KHÔI PHỤC")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)

                    Text(isInject
                        ? "Hệ thống sẽ tải file MOD từ máy chủ và ghi vào thư mục codepatch của game được chọn."
                        : "Hệ thống sẽ tải file GỐC từ máy chủ và ghi đè lại file codepatch để khôi phục mặc định.")
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
                        Text(isInject ? "Đang tải file MOD và ghi vào game..." : "Đang tải file GỐC và khôi phục...")
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
                    Text("assembly-csharp-patch...")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(AppTheme.grey400)
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
        do {
            try await service.loadNativeMenuForBothVariants(auth: authManager, showLoading: showLoading)
        } catch {
            activeToast = ToastInfo(title: "Không thể tải Patch Menu", message: error.localizedDescription, isSuccess: false)
        }
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
                        title: "Inject thành công",
                        message: "Đã tải file MOD và ghi vào: \(variant.bundleID)/Documents/.../codepatch/\(FeaturePatchService.codePatchFileName)",
                        isSuccess: true
                    )
                } else {
                    try await service.unjectCodePatch(variant: variant, auth: authManager)
                    activeToast = ToastInfo(
                        title: "Khôi phục thành công",
                        message: "Đã tải file GỐC và ghi lại cho \(variant.title).",
                        isSuccess: true
                    )
                }
            } catch {
                activeToast = ToastInfo(
                    title: inject ? "Inject thất bại" : "Khôi phục thất bại",
                    message: error.localizedDescription,
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

    var body: some View {
        VStack(spacing: 10) {
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

            if feature.type == "range" {
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
        guard assemblyOnline else { return desired != nil ? .green : AppTheme.grey400 }
        guard let desired else { return AppTheme.grey400 }
        if let actual, actual.enabled == desired.enabled, actual.value == desired.value { return .green }
        return .blue
    }

    private var stateText: String {
        guard assemblyOnline else { return desired != nil ? "SẴN SÀNG" : "CHƯA BẬT" }
        guard let desired else { return "CHƯA GỬI" }
        if let actual, actual.enabled == desired.enabled, actual.value == desired.value { return "ĐÃ ÁP DỤNG" }
        return "ĐANG ĐỒNG BỘ"
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
