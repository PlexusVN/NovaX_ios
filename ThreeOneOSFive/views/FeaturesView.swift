import SwiftUI

struct FeaturesView: View {
    var showSystemDashboard: Binding<Bool>? = nil

    @EnvironmentObject private var service: FeaturePatchService
    @EnvironmentObject private var authManager: AuthManager
    @State private var activeToast: ToastInfo?
    @State private var showGamePickerForInject = false
    @State private var showGamePickerForUnject = false
    @State private var isCodePatchWorking = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppTheme.pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        releaseCard
                        allFeatureSections
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 220)
                }
                .refreshable { await reload(showLoading: false) }

                injectBar
                    .padding(.bottom, 88)
            }
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
                await reload(showLoading: true)
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { break }
                    await service.refreshNativeStateForBothVariants(auth: authManager)
                }
            }
            .sheet(isPresented: $showGamePickerForInject) {
                GamePickerSheet(
                    title: "Chọn game để INJECT",
                    subtitle: "Inject sẽ tải file MOD từ server và ghi đè vào thư mục codepatch trong container Free Fire.",
                    buttonTitle: "INJECT NGAY",
                    isWorking: isCodePatchWorking
                ) { variant in
                    performCodePatch(variant: variant, inject: true)
                }
            }
            .sheet(isPresented: $showGamePickerForUnject) {
                GamePickerSheet(
                    title: "Chọn game để KHÔI PHỤC GỐC",
                    subtitle: "Khôi phục sẽ tải file GỐC từ server và ghi đè lại file codepatch trong container Free Fire.",
                    buttonTitle: "KHÔI PHỤC GỐC",
                    isWorking: isCodePatchWorking
                ) { variant in
                    performCodePatch(variant: variant, inject: false)
                }
            }
        }
        .glassToast(toast: $activeToast)
    }

    // Gom tất cả feature sections từ cả 2 variant
    private var allFeatureSections: some View {
        let sections = combinedSections()
        return Group {
            if sections.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "switch.2")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(AppTheme.grey400)
                    Text("Server chưa phát hành patch hoặc chưa có chức năng nào được khai báo")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.grey500)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .cardStyle()
            } else {
                ForEach(sections, id: \.id) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(section.title.uppercased())
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Text("\(section.features.count)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppTheme.grey500)
                        }
                        ForEach(section.features) { item in
                            NativeFeatureControlRow(
                                feature: item.feature,
                                variant: item.variant,
                                service: service,
                                auth: authManager,
                                activeToast: $activeToast
                            )
                        }
                    }
                    .cardStyle()
                }
            }
        }
    }

    private struct CombinedFeatureItem: Identifiable {
        let variant: GamePatchVariant
        let feature: NovaXFeatureDefinition
        var id: String { "\(variant.rawValue)|\(feature.id)" }
    }

    private struct CombinedSection: Identifiable {
        let id: String
        let title: String
        let features: [CombinedFeatureItem]
    }

    private func combinedSections() -> [CombinedSection] {
        // Gom theo (variant, section): mỗi variant có section riêng
        var map: [String: CombinedSection] = [:]
        let variants: [GamePatchVariant] = [.ffth, .ffmax]
        for v in variants {
            let features = service.nativeFeaturesByVariant[v] ?? []
            let sectionGroups = Dictionary(grouping: features, by: { $0.section })
            for (sectionName, list) in sectionGroups {
                let title = "\(v.shortTitle) · \(sectionName)"
                let key = "\(v.rawValue)|\(sectionName)"
                let items = list.map { CombinedFeatureItem(variant: v, feature: $0) }
                let existing = map[key]
                if let existing = existing {
                    var combined = existing.features
                    combined.append(contentsOf: items)
                    map[key] = CombinedSection(id: key, title: existing.title, features: combined)
                } else {
                    map[key] = CombinedSection(id: key, title: title, features: items)
                }
            }
        }
        return map.values.sorted { $0.title < $1.title }
    }

    private var releaseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Patch Menu", systemImage: "shippingbox.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                statusBadge
            }

            HStack(spacing: 10) {
                ForEach(GamePatchVariant.allCases) { variant in
                    let release = service.nativeReleaseByVariant[variant]
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(release != nil ? Color.green : Color.red)
                                .frame(width: 6, height: 6)
                            Text(variant.shortTitle)
                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                .foregroundStyle(AppTheme.ink)
                        }
                        if let r = release {
                            Text("v\(r.version) · \(formatSize(r.fileSize))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AppTheme.grey500)
                        } else {
                            Text("Chưa phát hành")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(AppTheme.grey50)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .cardStyle()
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(service.nativeAssemblyOnline ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(service.nativeAssemblyOnline ? "ONLINE" : "OFFLINE")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
        }
        .foregroundStyle(service.nativeAssemblyOnline ? Color.green : Color.red)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background((service.nativeAssemblyOnline ? Color.green : Color.red).opacity(0.1))
        .clipShape(Capsule())
    }

    private var injectBar: some View {
        VStack(spacing: 8) {
            Text(service.nativeStatusMessage)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.grey500)
                .lineLimit(1)

            HStack(spacing: 10) {
                Button {
                    Haptics.medium()
                    showGamePickerForInject = true
                } label: {
                    HStack(spacing: 8) {
                        if isCodePatchWorking {
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
                    showGamePickerForUnject = true
                } label: {
                    HStack(spacing: 8) {
                        if isCodePatchWorking {
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

    private func reload(showLoading: Bool) async {
        guard authManager.authState == .verified else { return }
        do {
            try await service.loadNativeMenuForBothVariants(auth: authManager, showLoading: showLoading)
        } catch {
            activeToast = ToastInfo(title: "Không thể tải Patch Menu", message: error.localizedDescription, isSuccess: false)
        }
    }

    private func performCodePatch(variant: GamePatchVariant, inject: Bool) {
        showGamePickerForInject = false
        showGamePickerForUnject = false
        Haptics.medium()
        isCodePatchWorking = true
        Task { @MainActor in
            defer { isCodePatchWorking = false }
            do {
                if inject {
                    try await service.injectCodePatch(variant: variant, auth: authManager)
                    activeToast = ToastInfo(
                        title: "Inject thành công",
                        message: "Đã ghi file MOD cho \(variant.title) vào thư mục codepatch.",
                        isSuccess: true
                    )
                } else {
                    try await service.unjectCodePatch(variant: variant, auth: authManager)
                    activeToast = ToastInfo(
                        title: "Khôi phục thành công",
                        message: "Đã ghi file GỐC cho \(variant.title) vào thư mục codepatch.",
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

    private func formatSize(_ bytes: Int) -> String {
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if bytes >= 1024 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        return "\(bytes) B"
    }
}

// MARK: - Game Picker Sheet (chọn FF TH hoặc FF MAX)

private struct GamePickerSheet: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let isWorking: Bool
    let onPick: (GamePatchVariant) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var gameIcons: [String: UIImage] = [:]

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { if !isWorking { dismiss() } }

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.ink)
                        .padding(.top, 8)
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.grey600)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.vertical, 20)

                Rectangle().fill(AppTheme.grey200).frame(height: 1)

                VStack(spacing: 12) {
                    ForEach(GamePatchVariant.allCases) { variant in
                        gameButton(variant: variant)
                    }
                }
                .padding(16)

                Rectangle().fill(AppTheme.grey200).frame(height: 1)

                Button {
                    if !isWorking { dismiss() }
                } label: {
                    Text("Hủy")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.grey600)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 35, x: 0, y: 15)
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .onAppear { loadIcons() }
    }

    private func gameButton(variant: GamePatchVariant) -> some View {
        Button {
            Haptics.medium()
            onPick(variant)
        } label: {
            HStack(spacing: 14) {
                Group {
                    if let img = gameIcons[variant.bundleID] {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppTheme.grey100)
                            Image(systemName: variant == .ffth ? "flame.fill" : "bolt.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(AppTheme.ink)
                        }
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.grey200, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(variant.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text(variant.bundleID)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.grey500)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.grey400)
            }
            .padding(12)
            .background(AppTheme.grey50)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.grey200, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    private func loadIcons() {
        DispatchQueue.global(qos: .userInitiated).async {
            var map: [String: UIImage] = [:]
            let apps = ContainerStore.installedAppsFromAPI() + ContainerStore.installedAppsFromMCM(identifiers: nil, bundleMetadata: [:])
            for app in apps {
                if let icon = app.icon, map[app.bundleID] == nil {
                    map[app.bundleID] = icon
                }
            }
            DispatchQueue.main.async { self.gameIcons = map }
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

private struct NativeFeatureControlRow: View {
    let feature: NovaXFeatureDefinition
    let variant: GamePatchVariant
    @ObservedObject var service: FeaturePatchService
    @ObservedObject var auth: AuthManager
    @Binding var activeToast: ToastInfo?

    @State private var isSending = false
    @State private var sliderValue: Double = 0

    private var desired: NovaXRemoteFeatureState? { service.nativeDesiredStateByVariant[variant]?[feature.id] }
    private var actual: NovaXRemoteFeatureState? { service.nativeActualStateByVariant[variant]?[feature.id] }
    private var assemblyOnline: Bool { service.nativeAssemblyOnlineByVariant[variant] ?? false }
    private var desiredEnabled: Bool { desired?.enabled ?? false }
    private var desiredValue: Int { desired?.value ?? feature.default }

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
        guard assemblyOnline else { return .red }
        guard let desired else { return AppTheme.grey400 }
        if let actual, actual.enabled == desired.enabled, actual.value == desired.value { return .green }
        return .blue
    }

    private var stateText: String {
        guard assemblyOnline else { return "ASSEMBLY OFFLINE" }
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
                    variant: variant,
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
